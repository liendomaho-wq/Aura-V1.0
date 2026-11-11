# Links Aura's JNI bridge (aura_llm_jni.cpp) against the pinned llama.cpp
# CPU-only static libraries produced by buildAuraLlmRuntime in build.gradle.
#
# The include paths and library locations are injected with -D at configure
# time so this file never hardcodes build directories.
cmake_minimum_required(VERSION 3.22.1)
project(aura_llm LANGUAGES CXX)

add_library(aura_llm SHARED aura_llm_jni.cpp)

if(NOT EXISTS "${LLAMA_INCLUDE_DIR}/llama.h")
    message(FATAL_ERROR "llama.h not found under LLAMA_INCLUDE_DIR; the pinned llama.cpp source is not prepared.")
endif()
if(NOT EXISTS "${GGML_CPU_STATIC_LIB}")
    message(FATAL_ERROR "libggml-cpu.a not found; the llama.cpp static runtime was not built for this ABI.")
endif()

find_package(Threads REQUIRED)

target_include_directories(aura_llm PRIVATE
    "${LLAMA_INCLUDE_DIR}"
    "${GGML_INCLUDE_DIR}"
)

# Static link order matters: dependents must precede their dependencies.
# Upstream: llama -> ggml -> ggml-cpu -> ggml-base.
target_link_libraries(aura_llm PRIVATE
    "${LLAMA_STATIC_LIB}"
    "${GGML_STATIC_LIB}"
    "${GGML_CPU_STATIC_LIB}"
    "${GGML_BASE_STATIC_LIB}"
    Threads::Threads
    ${CMAKE_DL_LIBS}
    m
)

if(ANDROID)
    target_link_libraries(aura_llm PRIVATE log android)
endif()
