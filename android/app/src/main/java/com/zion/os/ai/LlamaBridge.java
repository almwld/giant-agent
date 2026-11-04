package com.zion.os.ai;

public final class LlamaBridge {
    static { System.loadLibrary("llama_jni"); }

    public native boolean nativeLoadModel(String modelPath, int threads, String loraPath, float loraScale);
    public native String nativeGenerate(String prompt, int maxTokens, float temperature);
    public native boolean nativeCancelGeneration();
    public native void nativeFreeModel();
    public native boolean nativeIsLoaded();
    public native String nativeVersion();
}
