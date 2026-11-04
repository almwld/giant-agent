package com.example.giant_agent;

import androidx.annotation.Keep;

/** Stable JNI callback contract for streamed native tokens. */
@Keep
public interface TokenCallback {
    @Keep
    void onToken(String token);
}
