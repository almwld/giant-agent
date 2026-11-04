#include <jni.h>
#include <android/log.h>
#include <algorithm>
#include <atomic>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>
#include "llama.h"

#define LOG_TAG "ZionLLM"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace {
std::mutex g_mutex;
llama_model * g_model = nullptr;
llama_context * g_ctx = nullptr;
llama_sampler * g_sampler = nullptr;
llama_adapter_lora * g_lora = nullptr;
std::atomic<bool> g_generation_active{false};
std::atomic<bool> g_cancel_requested{false};

struct GenerationStateGuard {
    GenerationStateGuard() {
        g_cancel_requested.store(false, std::memory_order_relaxed);
        g_generation_active.store(true, std::memory_order_release);
    }
    ~GenerationStateGuard() {
        g_generation_active.store(false, std::memory_order_release);
        g_cancel_requested.store(false, std::memory_order_relaxed);
    }
};

void freeLocked() {
    if (g_sampler) { llama_sampler_free(g_sampler); g_sampler = nullptr; }
    if (g_ctx) { llama_free(g_ctx); g_ctx = nullptr; }
    if (g_lora) { llama_adapter_lora_free(g_lora); g_lora = nullptr; }
    if (g_model) { llama_model_free(g_model); g_model = nullptr; }
}

std::string fail(const char * message) { LOGE("%s", message); return std::string("ERROR: ") + message; }
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_zion_os_ai_LlamaBridge_nativeLoadModel(JNIEnv * env, jobject, jstring modelPath, jint threads, jstring loraPath, jfloat loraScale) {
    if (!modelPath) return JNI_FALSE;
    const char * path = env->GetStringUTFChars(modelPath, nullptr);
    if (!path) {
        LOGE("Unable to access model path from JNI");
        return JNI_FALSE;
    }
    std::lock_guard<std::mutex> lock(g_mutex);
    LOGE("Loading local GGUF model");
    freeLocked();
    llama_backend_init();

    auto params = llama_model_default_params();
    params.n_gpu_layers = 0;
    params.load_mode = LLAMA_LOAD_MODE_MMAP;
    g_model = llama_model_load_from_file(path, params);
    env->ReleaseStringUTFChars(modelPath, path);
    if (!g_model) return JNI_FALSE;

    auto ctxParams = llama_context_default_params();
    // Keep the context bounded for Android memory, but large enough for the
    // agent's real tool catalog, local inventory, and repair plans.
    ctxParams.n_ctx = 4096;
    ctxParams.n_batch = 64;
    ctxParams.n_ubatch = 32;
    ctxParams.n_seq_max = 1;
    const int safeThreads = std::clamp(static_cast<int>(threads), 1, 8);
    ctxParams.n_threads = safeThreads;
    ctxParams.n_threads_batch = safeThreads;
    g_ctx = llama_init_from_model(g_model, ctxParams);
    if (!g_ctx) {
        LOGE("llama_init_from_model failed; releasing partial model state");
        freeLocked();
        return JNI_FALSE;
    }

    if (loraPath) {
        const char * adapterPath = env->GetStringUTFChars(loraPath, nullptr);
        if (adapterPath && adapterPath[0] != '\\0') {
            g_lora = llama_adapter_lora_init(g_model, adapterPath);
            env->ReleaseStringUTFChars(loraPath, adapterPath);
            if (!g_lora) { freeLocked(); return JNI_FALSE; }
            llama_adapter_lora * adapters[] = { g_lora };
            float scales[] = { loraScale > 0.0f ? loraScale : 1.0f };
            if (llama_set_adapters_lora(g_ctx, adapters, 1, scales) != 0) {
                freeLocked();
                return JNI_FALSE;
            }
        } else if (adapterPath) {
            env->ReleaseStringUTFChars(loraPath, adapterPath);
        }
    }

    auto samplerParams = llama_sampler_chain_default_params();
    g_sampler = llama_sampler_chain_init(samplerParams);
    if (!g_sampler) {
        LOGE("Unable to initialize llama sampler");
        freeLocked();
        return JNI_FALSE;
    }
    llama_sampler_chain_add(g_sampler, llama_sampler_init_top_k(40));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_top_p(0.95f, 1));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_temp(0.7f));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));
    return JNI_TRUE;
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_zion_os_ai_LlamaBridge_nativeGenerate(JNIEnv * env, jobject, jstring prompt, jint maxTokens, jfloat temperature) {
    if (!prompt) return env->NewStringUTF("ERROR: Empty prompt");
    const char * text = env->GetStringUTFChars(prompt, nullptr);
    if (!text) return env->NewStringUTF("ERROR: Unable to read prompt");
    std::lock_guard<std::mutex> lock(g_mutex);
    LOGE("Starting local inference");
    if (!g_model || !g_ctx || !g_sampler) {
        env->ReleaseStringUTFChars(prompt, text);
        return env->NewStringUTF("ERROR: Model not loaded");
    }
    GenerationStateGuard generationState;

    llama_memory_clear(llama_get_memory(g_ctx), true);
    llama_sampler_reset(g_sampler);

    const auto * vocab = llama_model_get_vocab(g_model);
    const int32_t textLen = static_cast<int32_t>(strlen(text));
    int32_t capacity = std::max(256, textLen + 128);
    std::vector<llama_token> tokens(capacity);
    int32_t nTokens = llama_tokenize(vocab, text, textLen, tokens.data(), capacity, true, false);
    if (nTokens < 0) {
        capacity = -nTokens;
        tokens.resize(capacity);
        nTokens = llama_tokenize(vocab, text, textLen, tokens.data(), capacity, true, false);
    }
    env->ReleaseStringUTFChars(prompt, text);
    if (nTokens <= 0) return env->NewStringUTF("ERROR: Tokenization failed");
    tokens.resize(nTokens);

    const uint32_t nCtx = llama_n_ctx(g_ctx);
    if (nCtx <= 8 || tokens.size() >= static_cast<size_t>(nCtx - 8)) {
        LOGE("Prompt too long for bounded context: tokens=%zu context=%u", tokens.size(), nCtx);
        return env->NewStringUTF("ERROR: Prompt exceeds the safe local context window; shorten the message or clear chat history.");
    }

    // Rebuild the sampler for every request so a temperature of zero does not
    // accidentally reuse the previous request's sampling configuration. The
    // current llama.cpp temperature sampler expects a positive value, so map
    // zero to a very low deterministic-like temperature.
    llama_sampler_free(g_sampler);
    g_sampler = nullptr;
    auto samplerParams = llama_sampler_chain_default_params();
    g_sampler = llama_sampler_chain_init(samplerParams);
    if (!g_sampler) {
        LOGE("Unable to initialize request sampler");
        return env->NewStringUTF("ERROR: Unable to initialize local sampler.");
    }
    const float safeTemperature = std::clamp(static_cast<float>(temperature), 0.05f, 1.5f);
    llama_sampler_chain_add(g_sampler, llama_sampler_init_top_k(40));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_top_p(0.95f, 1));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_temp(safeTemperature));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));

    // n_batch is deliberately small on phones. Never submit the whole prompt
    // as one batch: long Arabic/system prompts can exceed n_batch and cause
    // inference failures on some llama.cpp builds.
    constexpr int32_t kDecodeBatch = 32;
    for (int32_t offset = 0; offset < nTokens;) {
        const int32_t count = std::min<int32_t>(kDecodeBatch, nTokens - offset);
        auto batch = llama_batch_get_one(tokens.data() + offset, count);
        const int decodeStatus = llama_decode(g_ctx, batch);
        if (decodeStatus != 0) {
            LOGE("Prompt decode failed at token offset %d (status=%d)", offset, decodeStatus);
            return env->NewStringUTF("ERROR: Prompt decode failed; try a shorter message.");
        }
        offset += count;
    }

    std::string output;
    // Bound generation to both the remaining context and a phone-safe limit.
    const int remaining = static_cast<int>(nCtx - tokens.size() - 1);
    const int limit = std::min(std::clamp(static_cast<int>(maxTokens), 1, 2048), remaining);
    LOGE("Prompt tokenized: %d tokens; generation limit: %d", nTokens, limit);

    for (int i = 0; i < limit; ++i) {
        if (g_cancel_requested.load(std::memory_order_acquire)) {
            LOGE("Inference cancelled after %d generated tokens", i);
            break;
        }
        llama_token next = llama_sampler_sample(g_sampler, g_ctx, -1);
        if (llama_vocab_is_eog(vocab, next)) break;

        char piece[1024];
        const int32_t n = llama_token_to_piece(vocab, next, piece, sizeof(piece), 0, true);
        if (n > 0) output.append(piece, n);

        llama_sampler_accept(g_sampler, next);
        auto nextBatch = llama_batch_get_one(&next, 1);
        if (llama_decode(g_ctx, nextBatch) != 0) {
            LOGE("Decode stopped after %d generated tokens", i + 1);
            break;
        }
    }
    LOGE("Inference finished; generated %zu UTF-8 bytes", output.size());
    return env->NewStringUTF(output.c_str());
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_zion_os_ai_LlamaBridge_nativeCancelGeneration(JNIEnv *, jobject) {
    if (!g_generation_active.load(std::memory_order_acquire)) return JNI_FALSE;
    g_cancel_requested.store(true, std::memory_order_release);
    return JNI_TRUE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_zion_os_ai_LlamaBridge_nativeFreeModel(JNIEnv *, jobject) {
    std::lock_guard<std::mutex> lock(g_mutex);
    freeLocked();
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_zion_os_ai_LlamaBridge_nativeIsLoaded(JNIEnv *, jobject) {
    std::lock_guard<std::mutex> lock(g_mutex);
    return g_model != nullptr && g_ctx != nullptr;
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_zion_os_ai_LlamaBridge_nativeVersion(JNIEnv * env, jobject) {
    return env->NewStringUTF(llama_version());
}
