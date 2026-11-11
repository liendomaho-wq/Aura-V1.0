// Aura local LLM JNI bridge over the pinned llama.cpp revision
// 806b3c2bed44490233f1e8ffa403519370965fe7 (CPU-only Android build).
//
// Design contract (mirrors lib/llm/aura_llm_runtime.dart):
//   * Fail-closed: any native failure stops the operation and is reported
//     through the event stream; it never becomes a silent success.
//   * One llama_model/llama_context at a time, guarded by mutexes.
//   * One persistent worker thread serializes generations; tokens are
//     streamed through AuraLlmBridge.onNativeEvent(opId, typeCode, text).
//   * Cancellation is cooperative: an atomic flag checked between tokens and
//     through the llama_decode abort callback (CPU execution supports it).
//   * JNI references are released on every path (RAII helpers below).
//   * Callbacks into the JVM never happen while a native lock is held.

#include <jni.h>

#include <llama.h>

#include <atomic>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <deque>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

namespace {

// Event type codes shared with AuraLlmBridge.onNativeEvent(int typeCode).
enum class AuraLlmEventType : jint {
    kToken = 0,
    kCompleted = 1,
    kError = 2,
};

// Result codes shared with AuraLlmBridge.nativeLoadModel/nativeStartGeneration.
enum AuraLlmNativeResult : jint {
    kResultOk = 0,
    kResultNoModel = 1,
    kResultLoadFailed = 2,
    kResultContextFailed = 3,
    kResultReject = 4,
};

constexpr jint kMaxPromptTokens = 32768;
constexpr jint kMaxOutputTokens = 4096;
constexpr int kTokenPieceBuffer = 256;

struct GenerationJob {
    std::string operation_id;
    std::string prompt;
    jint max_tokens = 0;
    float temperature = 0.0f;
    std::shared_ptr<std::atomic<bool>> cancel;
};

// ---------------------------------------------------------------------------
// Global runtime state.
// ---------------------------------------------------------------------------

std::mutex g_state_mutex;
llama_model *g_model = nullptr;
llama_context *g_ctx = nullptr;
bool g_backend_initialized = false;
std::string g_last_error;

std::mutex g_queue_mutex;
std::condition_variable g_queue_cv;
std::deque<GenerationJob> g_queue;
bool g_worker_stop = false;

// op id -> live cancel flag for queued or running generations.
std::mutex g_cancel_mutex;
std::unordered_map<std::string, std::shared_ptr<std::atomic<bool>>> g_cancel_map;

JavaVM *g_vm = nullptr;
jclass g_bridge_class = nullptr;
jmethodID g_on_event = nullptr;

// Worker lifecycle: 0 = starting, 1 = running, 2 = failed (sticky).
// The thread object is never joined or deleted: the library lives for the
// whole process and Android does not unload it.
constexpr int kWorkerStarting = 0;
constexpr int kWorkerRunning = 1;
constexpr int kWorkerFailed = 2;
std::thread *g_worker = nullptr;
std::atomic<int> g_worker_state{kWorkerStarting};

// Cooperative abort hook handed to llama_decode; only ever read from the
// single worker thread, set before each generation and cleared afterwards.
std::atomic<bool> *g_active_cancel = nullptr;

bool aura_abort_callback(void * /*user_data*/) {
    return g_active_cancel != nullptr && g_active_cancel->load(std::memory_order_relaxed);
}

// ---------------------------------------------------------------------------
// JNI helpers (RAII).
// ---------------------------------------------------------------------------

class ScopedJString {
public:
    ScopedJString(JNIEnv *env, jstring value)
        : env_(env), value_(value) {
        if (env_ != nullptr && value_ != nullptr) {
            chars_ = env_->GetStringUTFChars(value_, nullptr);
        }
    }

    ~ScopedJString() {
        if (chars_ != nullptr && env_ != nullptr && value_ != nullptr) {
            env_->ReleaseStringUTFChars(value_, chars_);
        }
    }

    const char *c_str() const { return chars_; }
    bool valid() const { return chars_ != nullptr; }
    std::string std_string() const { return chars_ != nullptr ? std::string(chars_) : std::string(); }

private:
    JNIEnv *env_;
    jstring value_;
    const char *chars_ = nullptr;
};

void set_last_error(const std::string &message) {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    g_last_error = message;
}

// Emits one event to AuraLlmBridge.onNativeEvent(opId, typeCode, text).
// Called from the worker thread only, with no native lock held.
void emit_event(JNIEnv *env, const std::string &op_id, AuraLlmEventType type,
                const std::string &text) {
    if (env == nullptr || g_bridge_class == nullptr || g_on_event == nullptr) {
        return;
    }
    jstring java_op_id = env->NewStringUTF(op_id.c_str());
    jstring java_text = text.empty() ? nullptr : env->NewStringUTF(text.c_str());
    env->CallStaticVoidMethod(g_bridge_class, g_on_event, java_op_id,
                              static_cast<jint>(type), java_text);
    if (env->ExceptionCheck()) {
        env->ExceptionDescribe();
        env->ExceptionClear();
        set_last_error("Java event callback threw while reporting a native LLM event.");
    }
    if (java_op_id != nullptr) {
        env->DeleteLocalRef(java_op_id);
    }
    if (java_text != nullptr) {
        env->DeleteLocalRef(java_text);
    }
}

// ---------------------------------------------------------------------------
// Generation worker.
// ---------------------------------------------------------------------------

void remember_cancel_flag(const std::string &op_id,
                          const std::shared_ptr<std::atomic<bool>> &flag) {
    std::lock_guard<std::mutex> lock(g_cancel_mutex);
    g_cancel_map[op_id] = flag;
}

void forget_cancel_flag(const std::string &op_id) {
    std::lock_guard<std::mutex> lock(g_cancel_mutex);
    g_cancel_map.erase(op_id);
}

bool request_cancel(const std::string &op_id) {
    std::lock_guard<std::mutex> lock(g_cancel_mutex);
    auto entry = g_cancel_map.find(op_id);
    if (entry == g_cancel_map.end() || entry->second == nullptr) {
        return false;
    }
    entry->second->store(true, std::memory_order_relaxed);
    return true;
}

void run_generation(JNIEnv *env, const GenerationJob &job) {
    llama_model *model = nullptr;
    llama_context *ctx = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_state_mutex);
        model = g_model;
        ctx = g_ctx;
    }
    if (model == nullptr || ctx == nullptr) {
        emit_event(env, job.operation_id, AuraLlmEventType::kError, "llm_not_loaded");
        return;
    }

    const llama_vocab *vocab = llama_model_get_vocab(model);
    if (vocab == nullptr) {
        emit_event(env, job.operation_id, AuraLlmEventType::kError, "llm_vocab_unavailable");
        return;
    }

    // Tokenize the prompt with special tokens so BOS/EOS behave like the
    // upstream simple example for the pinned revision.
    const std::string &prompt = job.prompt;
    const jint prompt_bytes = static_cast<jint>(prompt.size());
    if (prompt_bytes > kMaxPromptTokens * 16) {  // Hard bound before tokenizing.
        emit_event(env, job.operation_id, AuraLlmEventType::kError, "prompt_too_large");
        return;
    }
    const int prompt_tokens_needed =
        -llama_tokenize(vocab, prompt.c_str(), static_cast<int32_t>(prompt.size()),
                       nullptr, 0, true, true);
    if (prompt_tokens_needed <= 0) {
        emit_event(env, job.operation_id, AuraLlmEventType::kError, "tokenization_failed");
        return;
    }
    std::vector<llama_token> prompt_tokens(static_cast<size_t>(prompt_tokens_needed));
    if (llama_tokenize(vocab, prompt.c_str(), static_cast<int32_t>(prompt.size()),
                       prompt_tokens.data(), static_cast<int32_t>(prompt_tokens.size()),
                       true, true) < 0) {
        emit_event(env, job.operation_id, AuraLlmEventType::kError, "tokenization_failed");
        return;
    }

    // The context must fit prompt plus the requested output window.
    const uint32_t n_ctx = llama_n_ctx(ctx);
    if (n_ctx < static_cast<uint32_t>(prompt_tokens.size()) ||
        static_cast<uint32_t>(prompt_tokens.size() + job.max_tokens + 1) > n_ctx) {
        emit_event(env, job.operation_id, AuraLlmEventType::kError, "context_window_exceeded");
        return;
    }

    // Sampler chain: temperature when requested, greedy otherwise.
    auto sampler_params = llama_sampler_chain_default_params();
    sampler_params.no_perf = true;
    llama_sampler *sampler = llama_sampler_chain_init(sampler_params);
    if (sampler == nullptr) {
        emit_event(env, job.operation_id, AuraLlmEventType::kError, "sampler_init_failed");
        return;
    }
    if (job.temperature > 0.01f) {
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(job.temperature));
    } else {
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy());
    }

    g_active_cancel = job.cancel.get();
    std::string generated;
    bool cancelled = false;
    bool failed = false;
    std::string failure;
    llama_token next_token = 0;  // Must outlive the batch that references it.
    llama_token *next_tokens = prompt_tokens.data();
    int32_t next_count = static_cast<int32_t>(prompt_tokens.size());
    int32_t produced = 0;

    while (true) {
        if (job.cancel->load(std::memory_order_relaxed)) {
            cancelled = true;
            break;
        }
        llama_batch batch = llama_batch_get_one(next_tokens, next_count);
        if (llama_decode(ctx, batch) != 0) {
            if (job.cancel->load(std::memory_order_relaxed)) {
                cancelled = true;
            } else {
                failed = true;
                failure = "decode_failed";
            }
            break;
        }

        const llama_token token = llama_sampler_sample(sampler, ctx, -1);
        if (llama_vocab_is_eog(vocab, token)) {
            break;
        }

        char piece[kTokenPieceBuffer];
        const int piece_length = llama_token_to_piece(vocab, token, piece,
                                                      sizeof(piece), 0, true);
        if (piece_length < 0) {
            failed = true;
            failure = "detokenization_failed";
            break;
        }
        const std::string text(piece, static_cast<size_t>(piece_length));
        generated.append(text);
        emit_event(env, job.operation_id, AuraLlmEventType::kToken, text);

        produced += 1;
        if (produced >= job.max_tokens) {
            break;
        }
        next_token = token;
        next_tokens = &next_token;
        next_count = 1;
    }
    g_active_cancel = nullptr;

    llama_sampler_free(sampler);

    if (cancelled) {
        emit_event(env, job.operation_id, AuraLlmEventType::kError, "operation_cancelled");
    } else if (failed) {
        emit_event(env, job.operation_id, AuraLlmEventType::kError, failure);
    } else {
        emit_event(env, job.operation_id, AuraLlmEventType::kCompleted, generated);
    }
}

void worker_loop() {
    JNIEnv *env = nullptr;
    if (g_vm == nullptr || g_vm->AttachCurrentThread(&env, nullptr) != JNI_OK) {
        g_worker_state.store(kWorkerFailed, std::memory_order_release);
        return;
    }
    g_worker_state.store(kWorkerRunning, std::memory_order_release);

    while (true) {
        GenerationJob job;
        {
            std::unique_lock<std::mutex> lock(g_queue_mutex);
            g_queue_cv.wait(lock, [] { return g_worker_stop || !g_queue.empty(); });
            if (g_worker_stop && g_queue.empty()) {
                break;
            }
            job = std::move(g_queue.front());
            g_queue.pop_front();
        }
        run_generation(env, job);
        forget_cancel_flag(job.operation_id);
    }

    g_vm->DetachCurrentThread();
}

bool start_worker_locked() {
    const int state = g_worker_state.load(std::memory_order_acquire);
    if (state == kWorkerRunning) {
        return true;
    }
    if (state == kWorkerFailed) {
        return false;  // Sticky failure: JVM attachment did not succeed.
    }
    g_worker_stop = false;
    try {
        g_worker = new std::thread(worker_loop);
    } catch (...) {
        g_worker_state.store(kWorkerFailed, std::memory_order_release);
        return false;
    }
    // Wait until the worker reports a definitive JVM attachment outcome so
    // callers never observe a runtime that claims availability without it.
    int current = g_worker_state.load(std::memory_order_acquire);
    while (current == kWorkerStarting) {
        std::this_thread::yield();
        current = g_worker_state.load(std::memory_order_acquire);
    }
    return current == kWorkerRunning;
}

}  // namespace

extern "C" {

JNIEXPORT jint JNI_OnLoad(JavaVM *vm, void * /*reserved*/) {
    g_vm = vm;
    JNIEnv *env = nullptr;
    if (vm->GetEnv(reinterpret_cast<void **>(&env), JNI_VERSION_1_6) != JNI_OK || env == nullptr) {
        return JNI_ERR;
    }
    jclass local_class = env->FindClass("com/ciberdefensa/aura/AuraLlmBridge");
    if (local_class == nullptr) {
        env->ExceptionClear();
        return JNI_ERR;
    }
    g_bridge_class = static_cast<jclass>(env->NewGlobalRef(local_class));
    env->DeleteLocalRef(local_class);
    if (g_bridge_class == nullptr) {
        return JNI_ERR;
    }
    g_on_event = env->GetStaticMethodID(g_bridge_class, "onNativeEvent",
                                        "(Ljava/lang/String;ILjava/lang/String;)V");
    if (g_on_event == nullptr) {
        env->ExceptionClear();
        env->DeleteGlobalRef(g_bridge_class);
        g_bridge_class = nullptr;
        return JNI_ERR;
    }
    return JNI_VERSION_1_6;
}

JNIEXPORT jboolean JNICALL
Java_com_ciberdefensa_aura_AuraLlmBridge_nativeStartup(JNIEnv * /*env*/, jobject /*thiz*/) {
    std::lock_guard<std::mutex> lock(g_queue_mutex);
    if (g_vm == nullptr || g_bridge_class == nullptr || g_on_event == nullptr) {
        return JNI_FALSE;
    }
    return start_worker_locked() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_com_ciberdefensa_aura_AuraLlmBridge_nativeIsModelLoaded(JNIEnv * /*env*/, jobject /*thiz*/) {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    return (g_model != nullptr && g_ctx != nullptr) ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jint JNICALL
Java_com_ciberdefensa_aura_AuraLlmBridge_nativeMaxContextTokens(JNIEnv * /*env*/, jobject /*thiz*/) {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    if (g_ctx == nullptr) {
        return 0;
    }
    const uint32_t value = llama_n_ctx(g_ctx);
    return value > static_cast<uint32_t>(INT32_MAX) ? INT32_MAX : static_cast<jint>(value);
}

JNIEXPORT jint JNICALL
Java_com_ciberdefensa_aura_AuraLlmBridge_nativeLoadModel(JNIEnv *env, jobject /*thiz*/,
                                                        jstring model_path, jint context_tokens,
                                                        jint threads) {
    if (model_path == nullptr) {
        return kResultReject;
    }
    const ScopedJString path(env, model_path);
    if (!path.valid()) {
        return kResultReject;
    }
    if (context_tokens < 512 || context_tokens > 65536 || threads < 1 || threads > 8) {
        return kResultReject;
    }

    std::lock_guard<std::mutex> lock(g_state_mutex);
    if (g_model != nullptr || g_ctx != nullptr) {
        return kResultReject;  // A model is already loaded; unload first.
    }

    if (!g_backend_initialized) {
        llama_backend_init();
        g_backend_initialized = true;
    }

    llama_model_params model_params = llama_model_default_params();
    model_params.n_gpu_layers = 0;  // CPU-only Android build.
    llama_model *model = llama_model_load_from_file(path.c_str(), model_params);
    if (model == nullptr) {
        set_last_error("llama_model_load_from_file failed for the requested GGUF.");
        return kResultLoadFailed;
    }

    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = static_cast<uint32_t>(context_tokens);
    ctx_params.n_batch = 256;
    ctx_params.n_threads = threads;
    ctx_params.n_threads_batch = threads;
    ctx_params.abort_callback = &aura_abort_callback;
    ctx_params.abort_callback_data = nullptr;
    ctx_params.no_perf = true;
    llama_context *ctx = llama_init_from_model(model, ctx_params);
    if (ctx == nullptr) {
        llama_model_free(model);
        set_last_error("llama_init_from_model failed to allocate the context.");
        return kResultContextFailed;
    }

    g_model = model;
    g_ctx = ctx;
    g_last_error.clear();
    return kResultOk;
}

JNIEXPORT jstring JNICALL
Java_com_ciberdefensa_aura_AuraLlmBridge_nativeGetLastError(JNIEnv *env, jobject /*thiz*/) {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    if (g_last_error.empty()) {
        return nullptr;
    }
    return env->NewStringUTF(g_last_error.c_str());
}

JNIEXPORT jint JNICALL
Java_com_ciberdefensa_aura_AuraLlmBridge_nativeStartGeneration(JNIEnv *env, jobject /*thiz*/,
                                                              jstring operation_id, jstring prompt,
                                                              jint max_tokens, jdouble temperature) {
    if (operation_id == nullptr || prompt == nullptr) {
        return kResultReject;
    }
    const ScopedJString op_id(env, operation_id);
    const ScopedJString prompt_text(env, prompt);
    if (!op_id.valid() || !prompt_text.valid()) {
        return kResultReject;
    }
    if (max_tokens < 1 || max_tokens > kMaxOutputTokens ||
        !(temperature >= 0.0 && temperature <= 2.0)) {
        return kResultReject;
    }

    {
        std::lock_guard<std::mutex> lock(g_state_mutex);
        if (g_model == nullptr || g_ctx == nullptr) {
            return kResultNoModel;
        }
    }

    GenerationJob job;
    job.operation_id = op_id.std_string();
    job.prompt = prompt_text.std_string();
    job.max_tokens = max_tokens;
    job.temperature = static_cast<float>(temperature);
    job.cancel = std::make_shared<std::atomic<bool>>(false);

    {
        std::lock_guard<std::mutex> lock(g_queue_mutex);
        if (!start_worker_locked()) {
            return kResultReject;
        }
        remember_cancel_flag(job.operation_id, job.cancel);
        g_queue.push_back(std::move(job));
    }
    g_queue_cv.notify_one();
    return kResultOk;
}

JNIEXPORT jboolean JNICALL
Java_com_ciberdefensa_aura_AuraLlmBridge_nativeCancelGeneration(JNIEnv *env, jobject /*thiz*/,
                                                                jstring operation_id) {
    if (operation_id == nullptr) {
        return JNI_FALSE;
    }
    const ScopedJString op_id(env, operation_id);
    if (!op_id.valid()) {
        return JNI_FALSE;
    }
    return request_cancel(op_id.std_string()) ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jint JNICALL
Java_com_ciberdefensa_aura_AuraLlmBridge_nativeUnloadModel(JNIEnv * /*env*/, jobject /*thiz*/) {
    std::lock_guard<std::mutex> state_lock(g_state_mutex);
    {
        std::lock_guard<std::mutex> queue_lock(g_queue_mutex);
        if (!g_queue.empty()) {
            return kResultReject;  // Queued generations exist; fail-closed.
        }
    }
    {
        std::lock_guard<std::mutex> cancel_lock(g_cancel_mutex);
        if (!g_cancel_map.empty()) {
            return kResultReject;  // A generation is running; fail-closed.
        }
    }
    if (g_model == nullptr && g_ctx == nullptr) {
        return kResultOk;  // Idempotent unload.
    }
    if (g_ctx != nullptr) {
        llama_free(g_ctx);
        g_ctx = nullptr;
    }
    if (g_model != nullptr) {
        llama_model_free(g_model);
        g_model = nullptr;
    }
    g_last_error.clear();
    return kResultOk;
}

}  // extern "C"
