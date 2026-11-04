#include <jni.h>

extern "C" JNIEXPORT jboolean JNICALL
Java_com_zion_os_ai_LlamaBridge_nativeLoadModel(
    JNIEnv*, jobject, jstring, jint, jstring, jfloat) {
    return JNI_FALSE;
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_zion_os_ai_LlamaBridge_nativeGenerate(
    JNIEnv* env, jobject, jstring, jint, jfloat) {
    return env->NewStringUTF("ERROR: Local AI engine is available only on ARM64.");
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_zion_os_ai_LlamaBridge_nativeCancelGeneration(JNIEnv*, jobject) {
    return JNI_FALSE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_zion_os_ai_LlamaBridge_nativeFreeModel(JNIEnv*, jobject) {}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_zion_os_ai_LlamaBridge_nativeIsLoaded(JNIEnv*, jobject) {
    return JNI_FALSE;
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_zion_os_ai_LlamaBridge_nativeVersion(JNIEnv* env, jobject) {
    return env->NewStringUTF("unsupported");
}
