/*
 ============================================================================
 Name        : hev-jni.c
 Author      : hev <r@hev.cc>
 Copyright   : Copyright (c) 2019 - 2023 hev
 Description : Jave Native Interface
 ============================================================================
 */

#ifdef __ANDROID__

#include <jni.h>
#include <pthread.h>
#include <stdatomic.h>

#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <string.h>
#include <arpa/inet.h>
#include <errno.h>
#include <time.h>

#include "hev-main.h"
#include "hev-socks5-tunnel.h"
#include "aura_sni_firewall.h"

#include "hev-jni.h"

/* clang-format off */
#ifndef PKGNAME
#define PKGNAME hev/htproxy
#endif
#ifndef CLSNAME
#define CLSNAME TProxyService
#endif
/* clang-format on */

#define STR(s) STR_ARG (s)
#define STR_ARG(c) #c
#define N_ELEMENTS(arr) (sizeof (arr) / sizeof ((arr)[0]))

typedef struct _ThreadData ThreadData;

struct _ThreadData
{
    char *path;
    int fd;
};

static atomic_int is_running;
static atomic_int aura_join_in_progress;
static int thread_joinable;
static JavaVM *java_vm;
static jclass tproxy_class;
static jmethodID dns_event_method;
static jmethodID sni_event_method;
static jmethodID encrypted_dns_event_method;
static jmethodID protect_socket_method;
static jmethodID resolve_host_method;
static pthread_t work_thread;
static pthread_mutex_t mutex;
static pthread_key_t current_jni_env;

static jboolean native_start_service (JNIEnv *env, jobject thiz,
                                      jstring conig_path, jint fd);
static jboolean native_stop_service (JNIEnv *env, jobject thiz);
static jboolean native_is_running (JNIEnv *env, jobject thiz);
static jboolean native_is_domain_blocked (JNIEnv *env, jobject thiz,
                                         jstring domain);
static jlongArray native_get_stats (JNIEnv *env, jobject thiz);
static void native_set_blocked_ips (JNIEnv *env, jobject thiz,
                                    jobjectArray addresses);
static jboolean native_block_domain (JNIEnv *env, jobject thiz,
                                     jstring domain);
static void native_add_dynamic_sni_rule (JNIEnv *env, jclass klass,
                                         jstring domain);
static jboolean native_set_dynamic_sni_allowlist (JNIEnv *env, jobject thiz,
                                                  jobjectArray domains);

static JNINativeMethod native_methods[] = {
    { "TProxyStartService", "(Ljava/lang/String;I)Z",
      (void *)native_start_service },
    { "TProxyStopService", "()Z", (void *)native_stop_service },
    { "TProxyIsRunning", "()Z", (void *)native_is_running },
        { "TProxyIsDomainBlocked", "(Ljava/lang/String;)Z",
            (void *)native_is_domain_blocked },
    { "TProxyGetStats", "()[J", (void *)native_get_stats },
        { "TProxySetBlockedIps", "([Ljava/lang/String;)V",
            (void *)native_set_blocked_ips },
    { "TProxyBlockDomain", "(Ljava/lang/String;)Z", (void *)native_block_domain },
    { "addDynamicSniRule", "(Ljava/lang/String;)V",
      (void *)native_add_dynamic_sni_rule },
    { "TProxySetDynamicSniAllowlist", "([Ljava/lang/String;)Z",
      (void *)native_set_dynamic_sni_allowlist },
};

static void
detach_current_thread (void *env)
{
    (*java_vm)->DetachCurrentThread (java_vm);
}

jint
JNI_OnLoad (JavaVM *vm, void *reserved)
{
    JNIEnv *env = NULL;
    jclass klass;
    jint res;

    java_vm = vm;
    res = (*vm)->GetEnv (vm, (void **)&env, JNI_VERSION_1_4);
    if (res != JNI_OK)
        return JNI_ERR;

    klass = (*env)->FindClass (env, STR (PKGNAME) "/" STR (CLSNAME));
    if (!klass)
        return JNI_ERR;
    tproxy_class = (*env)->NewGlobalRef (env, klass);
    dns_event_method = (*env)->GetStaticMethodID (
        env, klass, "dispatchDnsEvent",
        "(Ljava/lang/String;ILjava/lang/String;I)V");
    sni_event_method = (*env)->GetStaticMethodID (
        env, klass, "dispatchSniEvent",
        "(Ljava/lang/String;Ljava/lang/String;I)V");
    encrypted_dns_event_method = (*env)->GetStaticMethodID (
        env, klass, "dispatchEncryptedDnsEvent",
        "(Ljava/lang/String;ILjava/lang/String;)V");
    protect_socket_method = (*env)->GetStaticMethodID (
        env, klass, "protectSocket", "(I)Z");
    resolve_host_method = (*env)->GetStaticMethodID (
        env, klass, "resolveHostForTunnel",
        "(Ljava/lang/String;)Ljava/lang/String;");
    res = (*env)->RegisterNatives (env, klass, native_methods,
                                   N_ELEMENTS (native_methods));
    (*env)->DeleteLocalRef (env, klass);
    if (res < 0 || !tproxy_class || !dns_event_method || !sni_event_method ||
        !encrypted_dns_event_method || !protect_socket_method ||
        !resolve_host_method)
        return JNI_ERR;

    pthread_key_create (&current_jni_env, detach_current_thread);
    pthread_mutex_init (&mutex, NULL);

    return JNI_VERSION_1_4;
}

/*
 * JNI bridge thread.
 *
 * hev-socks5-tunnel runs every session, the lwIP input loop and the local
 * SOCKS5 server as hev-task coroutines on small mmap()ed stacks. ART must
 * never run (or attach) Java code while the CPU is on one of those stacks:
 * AttachCurrentThread() installs its stack-overflow guard relative to the
 * current stack pointer and the interpreter checks frame addresses against
 * the pthread stack bounds, so a JNI call from a coroutine aborts or corrupts
 * the process (SIGSEGV/SIGABRT) a few milliseconds after the TUN comes up,
 * when the first DNS query, DoT probe or TCP session reaches the tunnel.
 *
 * Every native -> Java call therefore goes through one dedicated pthread that
 * is attached once on its own normal stack. Socket protection and DNS
 * resolution are synchronous requests (the coroutine waits, exactly like the
 * previous direct call); DNS/SNI telemetry events are queued and dropped when
 * the bounded queue is full.
 */

#define AURA_JNI_MAX_PENDING_EVENTS 256
#define AURA_JNI_TEXT_CAPACITY 256
#define AURA_JNI_SMALL_TEXT_CAPACITY 64
#define AURA_JNI_PROTECT_TIMEOUT_MS 5000
#define AURA_JNI_RESOLVE_TIMEOUT_MS 10000

enum
{
    AURA_JNI_REQUEST_PROTECT = 1,
    AURA_JNI_REQUEST_RESOLVE,
    AURA_JNI_EVENT_DNS,
    AURA_JNI_EVENT_SNI,
    AURA_JNI_EVENT_ENCRYPTED_DNS,
};

typedef struct _AuraJniRequest AuraJniRequest;

struct _AuraJniRequest
{
    AuraJniRequest *next;
    int type;
    int synchronous;
    int completed;
    int abandoned;
    int result;
    int number;
    int number2;
    char text[AURA_JNI_TEXT_CAPACITY];
    char text2[AURA_JNI_SMALL_TEXT_CAPACITY];
    char output[AURA_JNI_SMALL_TEXT_CAPACITY];
};

static pthread_mutex_t bridge_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t bridge_work_cond = PTHREAD_COND_INITIALIZER;
static pthread_cond_t bridge_done_cond = PTHREAD_COND_INITIALIZER;
static AuraJniRequest *bridge_sync_head;
static AuraJniRequest *bridge_sync_tail;
static AuraJniRequest *bridge_event_head;
static AuraJniRequest *bridge_event_tail;
static unsigned int bridge_pending_events;
/* 0 = not started, 1 = running, -1 = unavailable (attach/create failed). */
static int bridge_state;

static int
copy_text (char *destination, size_t capacity, const char *source)
{
    size_t length;

    if (!source)
        return -1;
    length = strlen (source);
    if (length >= capacity)
        return -1;
    memcpy (destination, source, length + 1);
    return 0;
}

static void
bridge_execute (JNIEnv *env, AuraJniRequest *request)
{
    if ((*env)->PushLocalFrame (env, 8) != JNI_OK) {
        (*env)->ExceptionClear (env);
        request->result = 0;
        return;
    }

    switch (request->type) {
    case AURA_JNI_REQUEST_PROTECT: {
        jboolean protected = (*env)->CallStaticBooleanMethod (
            env, tproxy_class, protect_socket_method, (jint)request->number);
        if ((*env)->ExceptionCheck (env)) {
            (*env)->ExceptionClear (env);
            protected = JNI_FALSE;
        }
        request->result = protected == JNI_TRUE;
        break;
    }
    case AURA_JNI_REQUEST_RESOLVE: {
        jstring java_hostname = (*env)->NewStringUTF (env, request->text);
        jstring java_address = NULL;
        const char *resolved = NULL;

        request->result = 0;
        request->output[0] = '\0';
        if (java_hostname) {
            java_address = (jstring)(*env)->CallStaticObjectMethod (
                env, tproxy_class, resolve_host_method, java_hostname);
            if (!(*env)->ExceptionCheck (env) && java_address) {
                resolved = (*env)->GetStringUTFChars (env, java_address, NULL);
                if (resolved && resolved[0] != '\0' &&
                    copy_text (request->output, sizeof (request->output),
                               resolved) == 0)
                    request->result = 1;
                if (resolved)
                    (*env)->ReleaseStringUTFChars (env, java_address, resolved);
            }
        }
        if ((*env)->ExceptionCheck (env))
            (*env)->ExceptionClear (env);
        break;
    }
    case AURA_JNI_EVENT_DNS: {
        jstring java_domain = (*env)->NewStringUTF (env, request->text);
        jstring java_source = (*env)->NewStringUTF (env, request->text2);
        if (java_domain && java_source)
            (*env)->CallStaticVoidMethod (env, tproxy_class, dns_event_method,
                                         java_domain, (jint)request->number,
                                         java_source, (jint)request->number2);
        if ((*env)->ExceptionCheck (env))
            (*env)->ExceptionClear (env);
        break;
    }
    case AURA_JNI_EVENT_SNI: {
        jstring java_domain = (*env)->NewStringUTF (env, request->text);
        jstring java_destination = (*env)->NewStringUTF (env, request->text2);
        if (java_domain && java_destination)
            (*env)->CallStaticVoidMethod (env, tproxy_class, sni_event_method,
                                         java_domain, java_destination,
                                         (jint)request->number);
        if ((*env)->ExceptionCheck (env))
            (*env)->ExceptionClear (env);
        break;
    }
    case AURA_JNI_EVENT_ENCRYPTED_DNS: {
        jstring java_destination = (*env)->NewStringUTF (env, request->text);
        jstring java_protocol = (*env)->NewStringUTF (env, request->text2);
        if (java_destination && java_protocol)
            (*env)->CallStaticVoidMethod (env, tproxy_class,
                                         encrypted_dns_event_method,
                                         java_destination,
                                         (jint)request->number, java_protocol);
        if ((*env)->ExceptionCheck (env))
            (*env)->ExceptionClear (env);
        break;
    }
    default:
        break;
    }

    (*env)->PopLocalFrame (env, NULL);
}

/* Call with bridge_mutex held. Fails every queued request. */
static void
bridge_fail_pending_locked (void)
{
    AuraJniRequest *request;

    while ((request = bridge_sync_head)) {
        bridge_sync_head = request->next;
        if (request->abandoned) {
            free (request);
        } else {
            request->result = 0;
            request->completed = 1;
        }
    }
    bridge_sync_tail = NULL;
    while ((request = bridge_event_head)) {
        bridge_event_head = request->next;
        free (request);
    }
    bridge_event_tail = NULL;
    bridge_pending_events = 0;
    pthread_cond_broadcast (&bridge_done_cond);
}

static void *
bridge_thread_handler (void *data)
{
    JNIEnv *env = NULL;
    JavaVMAttachArgs args;

    (void)data;
    args.version = JNI_VERSION_1_4;
    args.name = "AuraJniBridge";
    args.group = NULL;
    if ((*java_vm)->AttachCurrentThreadAsDaemon (java_vm, (void *)&env, &args) !=
        JNI_OK) {
        pthread_mutex_lock (&bridge_mutex);
        bridge_state = -1;
        bridge_fail_pending_locked ();
        pthread_mutex_unlock (&bridge_mutex);
        return NULL;
    }

    for (;;) {
        AuraJniRequest *request;

        pthread_mutex_lock (&bridge_mutex);
        while (!bridge_sync_head && !bridge_event_head)
            pthread_cond_wait (&bridge_work_cond, &bridge_mutex);
        if (bridge_sync_head) {
            request = bridge_sync_head;
            bridge_sync_head = request->next;
            if (!bridge_sync_head)
                bridge_sync_tail = NULL;
            if (request->abandoned) {
                /* The waiting coroutine already timed out; its fd may be closed. */
                free (request);
                pthread_mutex_unlock (&bridge_mutex);
                continue;
            }
        } else {
            request = bridge_event_head;
            bridge_event_head = request->next;
            if (!bridge_event_head)
                bridge_event_tail = NULL;
            if (bridge_pending_events)
                bridge_pending_events--;
        }
        pthread_mutex_unlock (&bridge_mutex);

        request->next = NULL;
        bridge_execute (env, request);

        if (!request->synchronous) {
            free (request);
            continue;
        }
        pthread_mutex_lock (&bridge_mutex);
        if (request->abandoned) {
            free (request);
        } else {
            request->completed = 1;
            pthread_cond_broadcast (&bridge_done_cond);
        }
        pthread_mutex_unlock (&bridge_mutex);
    }

    return NULL;
}

/* Starts the bridge once per process. Returns 0 when it is usable. */
static int
bridge_start (void)
{
    pthread_attr_t attr;
    pthread_t thread;
    int result;

    pthread_mutex_lock (&bridge_mutex);
    if (bridge_state != 0) {
        result = bridge_state > 0 ? 0 : -1;
        pthread_mutex_unlock (&bridge_mutex);
        return result;
    }

    result = -1;
    if (java_vm && pthread_attr_init (&attr) == 0) {
        pthread_attr_setdetachstate (&attr, PTHREAD_CREATE_DETACHED);
        /* ART needs a real, generously sized stack for Java frames. */
        pthread_attr_setstacksize (&attr, 1024 * 1024);
        if (pthread_create (&thread, &attr, bridge_thread_handler, NULL) == 0) {
            bridge_state = 1;
            result = 0;
        }
        pthread_attr_destroy (&attr);
    }
    pthread_mutex_unlock (&bridge_mutex);
    return result;
}

static void
add_ms_to_now (struct timespec *deadline, int timeout_ms)
{
    clock_gettime (CLOCK_REALTIME, deadline);
    deadline->tv_sec += timeout_ms / 1000;
    deadline->tv_nsec += (long)(timeout_ms % 1000) * 1000000L;
    if (deadline->tv_nsec >= 1000000000L) {
        deadline->tv_sec++;
        deadline->tv_nsec -= 1000000000L;
    }
}

/*
 * Runs @request synchronously on the bridge thread. On success the caller
 * owns @request again and must free it. On failure (bridge unavailable or
 * timeout) ownership has been released and the caller must not touch it.
 */
static int
bridge_call (AuraJniRequest *request, int timeout_ms)
{
    struct timespec deadline;

    request->synchronous = 1;
    request->next = NULL;
    pthread_mutex_lock (&bridge_mutex);
    if (bridge_state != 1) {
        pthread_mutex_unlock (&bridge_mutex);
        free (request);
        return -1;
    }
    if (bridge_sync_tail)
        bridge_sync_tail->next = request;
    else
        bridge_sync_head = request;
    bridge_sync_tail = request;
    pthread_cond_signal (&bridge_work_cond);

    add_ms_to_now (&deadline, timeout_ms);
    while (!request->completed) {
        int wait = pthread_cond_timedwait (&bridge_done_cond, &bridge_mutex,
                                           &deadline);
        if (wait == ETIMEDOUT && !request->completed) {
            /* The bridge (or bridge_fail_pending_locked) frees it later. */
            request->abandoned = 1;
            pthread_mutex_unlock (&bridge_mutex);
            return -1;
        }
    }
    pthread_mutex_unlock (&bridge_mutex);
    return 0;
}

static void
bridge_post_event (AuraJniRequest *request)
{
    request->synchronous = 0;
    request->next = NULL;
    pthread_mutex_lock (&bridge_mutex);
    if (bridge_state != 1 ||
        bridge_pending_events >= AURA_JNI_MAX_PENDING_EVENTS) {
        pthread_mutex_unlock (&bridge_mutex);
        free (request);
        return;
    }
    if (bridge_event_tail)
        bridge_event_tail->next = request;
    else
        bridge_event_head = request;
    bridge_event_tail = request;
    bridge_pending_events++;
    pthread_cond_signal (&bridge_work_cond);
    pthread_mutex_unlock (&bridge_mutex);
}

/* Threads already known to ART (Java threads, the bridge) call directly. */
static JNIEnv *
current_attached_env (void)
{
    JNIEnv *env = NULL;

    if (!java_vm)
        return NULL;
    if ((*java_vm)->GetEnv (java_vm, (void **)&env, JNI_VERSION_1_4) != JNI_OK)
        return NULL;
    return env;
}

static void
bridge_run_or_post (AuraJniRequest *request)
{
    JNIEnv *env = current_attached_env ();

    if (env) {
        bridge_execute (env, request);
        free (request);
        return;
    }
    bridge_post_event (request);
}

int
hev_jni_protect_socket (int socket_fd)
{
    AuraJniRequest *request;
    JNIEnv *env;
    int result;

    if (!java_vm || !tproxy_class || !protect_socket_method)
        return 0;

    request = calloc (1, sizeof (*request));
    if (!request)
        return 0;
    request->type = AURA_JNI_REQUEST_PROTECT;
    request->number = socket_fd;

    env = current_attached_env ();
    if (env) {
        bridge_execute (env, request);
    } else if (bridge_call (request, AURA_JNI_PROTECT_TIMEOUT_MS) < 0) {
        return 0;
    }
    result = request->result;
    free (request);
    return result;
}

int
hev_jni_resolve_host (const char *hostname, char *address, size_t address_size)
{
    AuraJniRequest *request;
    JNIEnv *env;
    int result = 0;

    if (!hostname || !address || address_size == 0 || !java_vm ||
        !tproxy_class || !resolve_host_method)
        return 0;

    address[0] = '\0';
    request = calloc (1, sizeof (*request));
    if (!request)
        return 0;
    request->type = AURA_JNI_REQUEST_RESOLVE;
    if (copy_text (request->text, sizeof (request->text), hostname) < 0) {
        free (request);
        return 0;
    }

    env = current_attached_env ();
    if (env) {
        bridge_execute (env, request);
    } else if (bridge_call (request, AURA_JNI_RESOLVE_TIMEOUT_MS) < 0) {
        return 0;
    }
    if (request->result &&
        copy_text (address, address_size, request->output) == 0)
        result = 1;
    free (request);
    return result;
}

void
hev_jni_report_dns_event (const char *domain, int action,
                          uint32_t source_ipv4, uint16_t source_port)
{
    AuraJniRequest *request;
    char source_address[INET_ADDRSTRLEN] = "0.0.0.0";

    if (!java_vm || !tproxy_class || !dns_event_method || !domain)
        return;
    if (source_ipv4)
        inet_ntop (AF_INET, &source_ipv4, source_address, sizeof (source_address));

    request = calloc (1, sizeof (*request));
    if (!request)
        return;
    request->type = AURA_JNI_EVENT_DNS;
    request->number = action;
    request->number2 = source_port;
    if (copy_text (request->text, sizeof (request->text), domain) < 0 ||
        copy_text (request->text2, sizeof (request->text2), source_address) < 0) {
        free (request);
        return;
    }
    bridge_run_or_post (request);
}

void
hev_jni_report_sni_event (const char *domain,
                          const char *destination_address,
                          uint16_t destination_port)
{
    AuraJniRequest *request;

    if (!java_vm || !tproxy_class || !sni_event_method ||
        !domain || !destination_address)
        return;

    request = calloc (1, sizeof (*request));
    if (!request)
        return;
    request->type = AURA_JNI_EVENT_SNI;
    request->number = destination_port;
    if (copy_text (request->text, sizeof (request->text), domain) < 0 ||
        copy_text (request->text2, sizeof (request->text2),
                   destination_address) < 0) {
        free (request);
        return;
    }
    bridge_run_or_post (request);
}

void
hev_jni_report_encrypted_dns_event (const char *destination_address,
                                   uint16_t destination_port,
                                   const char *transport_protocol)
{
    AuraJniRequest *request;

    if (!java_vm || !tproxy_class || !encrypted_dns_event_method ||
        !destination_address || !transport_protocol)
        return;

    request = calloc (1, sizeof (*request));
    if (!request)
        return;
    request->type = AURA_JNI_EVENT_ENCRYPTED_DNS;
    request->number = destination_port;
    if (copy_text (request->text, sizeof (request->text),
                   destination_address) < 0 ||
        copy_text (request->text2, sizeof (request->text2),
                   transport_protocol) < 0) {
        free (request);
        return;
    }
    bridge_run_or_post (request);
}

static void *
thread_handler (void *data)
{
    ThreadData *tdata = data;

    hev_socks5_tunnel_main (tdata->path, tdata->fd);

    atomic_store_explicit (&is_running, 0, memory_order_release);

    free (tdata->path);
    free (tdata);

    return NULL;
}

static jboolean
native_start_service (JNIEnv *env, jobject thiz, jstring config_path, jint fd)
{
    const jbyte *bytes;
    ThreadData *tdata;
    int res;
    jboolean result = JNI_FALSE;

    pthread_mutex_lock (&mutex);

    if (atomic_load_explicit (&is_running, memory_order_acquire))
        goto exit;

    /* A timed-out stop still owns work_thread. Joining it here is undefined
     * and can deadlock on mutex, which the helper needs to finish. */
    if (atomic_load_explicit (&aura_join_in_progress, memory_order_acquire))
        goto exit;

    if (thread_joinable) {
        res = pthread_join (work_thread, NULL);
        if (res != 0)
            goto exit;
        thread_joinable = 0;
    }

    /* Native -> Java callbacks must never run on hev-task coroutine stacks. */
    if (bridge_start () < 0)
        goto exit;

    tdata = malloc (sizeof (ThreadData));
    if (!tdata)
        goto exit;
    tdata->fd = fd;

    bytes = (const jbyte *)(*env)->GetStringUTFChars (env, config_path, NULL);
    if (!bytes) {
        free (tdata);
        goto exit;
    }
    tdata->path = strdup ((const char *)bytes);
    (*env)->ReleaseStringUTFChars (env, config_path, (const char *)bytes);
    if (!tdata->path) {
        free (tdata);
        goto exit;
    }

    atomic_store_explicit (&is_running, 1, memory_order_release);
    res = pthread_create (&work_thread, NULL, thread_handler, tdata);
    if (res != 0) {
        atomic_store_explicit (&is_running, 0, memory_order_release);
        free (tdata->path);
        free (tdata);
        goto exit;
    }

    thread_joinable = 1;
    result = JNI_TRUE;
exit:
    pthread_mutex_unlock (&mutex);
    return result;
}

#define AURA_JOIN_TIMEOUT_MS 3000

typedef struct _AuraJoinWait
{
    pthread_t target;
    int result;
    int finished;
    int caller_gone;
    pthread_mutex_t lock;
    pthread_cond_t cond;
} AuraJoinWait;

static void *
aura_join_helper (void *data)
{
    AuraJoinWait *wait = data;
    int res = pthread_join (wait->target, NULL);
    int caller_gone;

    pthread_mutex_lock (&wait->lock);
    wait->result = res;
    wait->finished = 1;
    pthread_cond_signal (&wait->cond);
    caller_gone = wait->caller_gone;
    pthread_mutex_unlock (&wait->lock);

    if (caller_gone) {
        pthread_mutex_lock (&mutex);
        if (res == 0) {
            thread_joinable = 0;
            atomic_store_explicit (&is_running, 0, memory_order_release);
        }
        atomic_store_explicit (&aura_join_in_progress, 0, memory_order_release);
        pthread_mutex_unlock (&mutex);
        pthread_cond_destroy (&wait->cond);
        pthread_mutex_destroy (&wait->lock);
        free (wait);
    }
    return NULL;
}

static int
aura_join_worker_with_timeout (pthread_t target)
{
    AuraJoinWait *wait;
    pthread_t helper;
    struct timespec deadline;
    int res;
    int finished;

    wait = calloc (1, sizeof (AuraJoinWait));
    if (!wait) {
        atomic_store_explicit (&aura_join_in_progress, 0, memory_order_release);
        return ENOMEM;
    }
    wait->target = target;
    pthread_mutex_init (&wait->lock, NULL);
    pthread_cond_init (&wait->cond, NULL);
    res = pthread_create (&helper, NULL, aura_join_helper, wait);
    if (res != 0) {
        pthread_cond_destroy (&wait->cond);
        pthread_mutex_destroy (&wait->lock);
        free (wait);
        atomic_store_explicit (&aura_join_in_progress, 0, memory_order_release);
        return res;
    }

    clock_gettime (CLOCK_REALTIME, &deadline);
    deadline.tv_sec += AURA_JOIN_TIMEOUT_MS / 1000;
    pthread_mutex_lock (&wait->lock);
    while (!wait->finished) {
        res = pthread_cond_timedwait (&wait->cond, &wait->lock, &deadline);
        if (res == ETIMEDOUT)
            break;
    }
    finished = wait->finished;
    if (finished) {
        res = wait->result;
        pthread_mutex_unlock (&wait->lock);
        pthread_join (helper, NULL);
        pthread_cond_destroy (&wait->cond);
        pthread_mutex_destroy (&wait->lock);
        free (wait);
        return res;
    }

    wait->caller_gone = 1;
    pthread_mutex_unlock (&wait->lock);
    pthread_detach (helper);
    return ETIMEDOUT;
}

static jboolean
native_stop_service (JNIEnv *env, jobject thiz)
{
    int res = 0;

    pthread_mutex_lock (&mutex);

    if (!thread_joinable)
        goto exit;

    res = atomic_load_explicit (&aura_join_in_progress, memory_order_acquire)
              ? ETIMEDOUT
              : 0;
    if (res != 0)
        goto exit;

    if (atomic_load_explicit (&is_running, memory_order_acquire))
        hev_socks5_tunnel_quit ();
    atomic_store_explicit (&aura_join_in_progress, 1, memory_order_release);
    res = aura_join_worker_with_timeout (work_thread);
    if (res != 0)
        goto exit;

    /* Keep the thread joinable after a failed or timed-out join so a later
     * stop/start can reconcile it instead of falsely reporting shutdown. */
    thread_joinable = 0;
    atomic_store_explicit (&aura_join_in_progress, 0, memory_order_release);
    atomic_store_explicit (&is_running, 0, memory_order_release);
exit:
    pthread_mutex_unlock (&mutex);
    return res == 0 ? JNI_TRUE : JNI_FALSE;
}

static jboolean
native_is_running (JNIEnv *env, jobject thiz)
{
    return atomic_load_explicit (&is_running, memory_order_acquire) ? JNI_TRUE :
                                                                      JNI_FALSE;
}

static jlongArray
native_get_stats (JNIEnv *env, jobject thiz)
{
    size_t tx_packets, rx_packets, tx_bytes, rx_bytes;
    jlongArray res;
    jlong array[4];

    hev_socks5_tunnel_stats (&tx_packets, &tx_bytes, &rx_packets, &rx_bytes);
    array[0] = tx_packets;
    array[1] = tx_bytes;
    array[2] = rx_packets;
    array[3] = rx_bytes;

    res = (*env)->NewLongArray (env, 4);
    (*env)->SetLongArrayRegion (env, res, 0, 4, array);

    return res;
}

static void
native_set_blocked_ips (JNIEnv *env, jobject thiz, jobjectArray addresses)
{
    const jsize input_count = (*env)->GetArrayLength (env, addresses);
    const size_t capacity = input_count > 8192 ? 8192 : (size_t)input_count;
    uint32_t *parsed_ipv4 = calloc (capacity, sizeof (uint32_t));
    uint8_t (*parsed_ipv6)[16] = calloc (capacity, sizeof (*parsed_ipv6));
    size_t count_ipv4 = 0;
    size_t count_ipv6 = 0;
    jsize i;

    if ((!parsed_ipv4 || !parsed_ipv6) && capacity) {
        free (parsed_ipv4);
        free (parsed_ipv6);
        return;
    }

    for (i = 0; i < input_count && i < (jsize)capacity; i++) {
        jstring value = (jstring)(*env)->GetObjectArrayElement (env, addresses, i);
        const char *text;
        struct in_addr address_ipv4;
        struct in6_addr address_ipv6;

        if (!value)
            continue;
        text = (*env)->GetStringUTFChars (env, value, NULL);
        if (text) {
            if (inet_pton (AF_INET, text, &address_ipv4) == 1) {
                parsed_ipv4[count_ipv4++] = address_ipv4.s_addr;
            } else if (inet_pton (AF_INET6, text, &address_ipv6) == 1) {
                memcpy (parsed_ipv6[count_ipv6++], &address_ipv6, 16);
            }
            (*env)->ReleaseStringUTFChars (env, value, text);
        }
        (*env)->DeleteLocalRef (env, value);
    }

    hev_socks5_tunnel_set_blocked_ipv4 (parsed_ipv4, count_ipv4);
    hev_socks5_tunnel_set_blocked_ipv6 (
        (const uint8_t (*)[16])parsed_ipv6, count_ipv6);
    free (parsed_ipv4);
    free (parsed_ipv6);
}

static jboolean
native_block_domain (JNIEnv *env, jobject thiz, jstring domain)
{
    const char *value;
    int result;

    if (!domain)
        return JNI_FALSE;
    value = (*env)->GetStringUTFChars (env, domain, NULL);
    if (!value)
        return JNI_FALSE;
    result = hev_socks5_tunnel_block_domain (value);
    (*env)->ReleaseStringUTFChars (env, domain, value);
    return result > 0 ? JNI_TRUE : JNI_FALSE;
}

static jboolean
native_is_domain_blocked (JNIEnv *env, jobject thiz, jstring domain)
{
    const char *value;
    int result;

    (void)thiz;
    if (!domain)
        return JNI_FALSE;
    value = (*env)->GetStringUTFChars (env, domain, NULL);
    if (!value)
        return JNI_FALSE;
    result = hev_socks5_tunnel_is_domain_blocked (value);
    (*env)->ReleaseStringUTFChars (env, domain, value);
    return result > 0 ? JNI_TRUE : JNI_FALSE;
}

static void
native_add_dynamic_sni_rule (JNIEnv *env, jclass klass, jstring domain)
{
    const char *value;
    int result;

    (void)klass;
    if (!domain) {
        jclass exception_class = (*env)->FindClass (env, "java/lang/IllegalArgumentException");
        if (exception_class)
            (*env)->ThrowNew (env, exception_class, "SNI domain must not be null.");
        return;
    }

    value = (*env)->GetStringUTFChars (env, domain, NULL);
    if (!value)
        return;

    result = aura_add_dynamic_sni_rule (value);
    (*env)->ReleaseStringUTFChars (env, domain, value);
    if (result > 0)
        return;

    {
        const char *class_name = result < 0
                                     ? "java/lang/IllegalArgumentException"
                                     : "java/lang/IllegalStateException";
        const char *message = result < 0
                                  ? "Invalid SNI domain."
                                  : "Dynamic SNI rule capacity is exhausted.";
        jclass exception_class = (*env)->FindClass (env, class_name);
        if (exception_class)
            (*env)->ThrowNew (env, exception_class, message);
    }
}

JNIEXPORT jboolean JNICALL
Java_com_ciberdefensa_aura_MainActivity_addDnsBlockRuleNative (
    JNIEnv *env, jobject thiz, jstring domain)
{
    const char *value;
    int result;

    (void)thiz;
    if (!domain)
        return JNI_FALSE;

    value = (*env)->GetStringUTFChars (env, domain, NULL);
    if (!value)
        return JNI_FALSE;

    result = aura_add_dynamic_sni_rule (value);
    (*env)->ReleaseStringUTFChars (env, domain, value);
    return result > 0 ? JNI_TRUE : JNI_FALSE;
}

static jboolean
native_set_dynamic_sni_allowlist (JNIEnv *env, jobject thiz,
                                  jobjectArray domains)
{
    const jsize domain_count = domains
                                   ? (*env)->GetArrayLength (env, domains)
                                   : 0;
    const size_t capacity = (size_t)domain_count;
    char **parsed;
    size_t count = 0;
    jsize i;
    int result;

    (void)thiz;
    if (!domains) {
        jclass exception_class =
            (*env)->FindClass (env, "java/lang/IllegalArgumentException");
        if (exception_class)
            (*env)->ThrowNew (env, exception_class,
                              "Dynamic SNI allowlist must not be null.");
        return JNI_FALSE;
    }
    if (capacity > 1024) {
        jclass exception_class =
            (*env)->FindClass (env, "java/lang/IllegalArgumentException");
        if (exception_class)
            (*env)->ThrowNew (env, exception_class,
                              "Dynamic SNI allowlist exceeds 1024 domains.");
        return JNI_FALSE;
    }
    parsed = calloc (capacity ? capacity : 1, sizeof (*parsed));
    if (!parsed)
        return JNI_FALSE;
    for (i = 0; i < domain_count; i++) {
        jstring value =
            (jstring)(*env)->GetObjectArrayElement (env, domains, i);
        const char *text;
        size_t length;

        if (!value)
            goto invalid_domain;
        text = (*env)->GetStringUTFChars (env, value, NULL);
        if (!text) {
            (*env)->DeleteLocalRef (env, value);
            goto jni_failure;
        }
        length = strlen (text);
        if (!length || length > 253) {
            (*env)->ReleaseStringUTFChars (env, value, text);
            (*env)->DeleteLocalRef (env, value);
            goto invalid_domain;
        }
        parsed[count] = malloc (length + 1);
        if (!parsed[count]) {
            (*env)->ReleaseStringUTFChars (env, value, text);
            (*env)->DeleteLocalRef (env, value);
            goto allocation_failed;
        }
        memcpy (parsed[count], text, length + 1);
        count++;
        (*env)->ReleaseStringUTFChars (env, value, text);
        (*env)->DeleteLocalRef (env, value);
    }

    result = aura_set_dynamic_sni_allowlist (
        (const char *const *)parsed, count);
    for (i = 0; i < (jsize)count; i++)
        free (parsed[i]);
    free (parsed);
    return result > 0 ? JNI_TRUE : JNI_FALSE;

invalid_domain:
    for (i = 0; i < (jsize)count; i++)
        free (parsed[i]);
    free (parsed);
    {
        jclass exception_class =
            (*env)->FindClass (env, "java/lang/IllegalArgumentException");
        if (exception_class)
            (*env)->ThrowNew (env, exception_class,
                              "Dynamic SNI allowlist contains an invalid domain.");
    }
    return JNI_FALSE;

allocation_failed:
    for (i = 0; i < (jsize)count; i++)
        free (parsed[i]);
    free (parsed);
    {
        jclass exception_class =
            (*env)->FindClass (env, "java/lang/OutOfMemoryError");
        if (exception_class)
            (*env)->ThrowNew (env, exception_class,
                              "Could not allocate the dynamic SNI allowlist.");
    }
    return JNI_FALSE;

jni_failure:
    for (i = 0; i < (jsize)count; i++)
        free (parsed[i]);
    free (parsed);
    return JNI_FALSE;
}

#endif /* ANDROID */
