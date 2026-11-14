import 'dart:async';

import 'package:flutter/foundation.dart';

import 'local_speech_recognition_service.dart';
import 'voice_output_service.dart';
import 'model_provider_settings.dart';

enum VoiceSessionPhase { idle, listening, thinking, speaking, error }

class VoiceSessionSnapshot {
  const VoiceSessionSnapshot({
    this.phase = VoiceSessionPhase.idle,
    this.active = false,
    this.isListening = false,
    this.voiceRequestActive = false,
    this.bargeInActive = false,
    this.bargeInReady = false,
    this.aecAvailable = false,
    this.finalizing = false,
    this.transcript = '',
    this.error,
  });

  final VoiceSessionPhase phase;
  final bool active;
  final bool isListening;
  final bool voiceRequestActive;
  final bool bargeInActive;
  final bool bargeInReady;
  final bool aecAvailable;
  final bool finalizing;
  final String transcript;
  final String? error;

  VoiceSessionSnapshot copyWith({
    VoiceSessionPhase? phase,
    bool? active,
    bool? isListening,
    bool? voiceRequestActive,
    bool? bargeInActive,
    bool? bargeInReady,
    bool? aecAvailable,
    bool? finalizing,
    String? transcript,
    String? error,
    bool clearError = false,
  }) => VoiceSessionSnapshot(
    phase: phase ?? this.phase,
    active: active ?? this.active,
    isListening: isListening ?? this.isListening,
    voiceRequestActive: voiceRequestActive ?? this.voiceRequestActive,
    bargeInActive: bargeInActive ?? this.bargeInActive,
    bargeInReady: bargeInReady ?? this.bargeInReady,
    aecAvailable: aecAvailable ?? this.aecAvailable,
    finalizing: finalizing ?? this.finalizing,
    transcript: transcript ?? this.transcript,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Application-scoped owner of microphone capture, VAD/AEC events and voice
/// output coordination. Screens attach UI callbacks; disposing a screen only
/// detaches those callbacks and never tears down an active voice session.
class VoiceSessionController {
  VoiceSessionController._();

  static final VoiceSessionController instance = VoiceSessionController._();

  final LocalSpeechRecognitionService speech =
      LocalSpeechRecognitionService.instance;
  final VoiceOutputService output = VoiceOutputService.instance;
  final ValueNotifier<VoiceSessionSnapshot> state =
      ValueNotifier<VoiceSessionSnapshot>(const VoiceSessionSnapshot());

  StreamSubscription<Map<String, dynamic>>? _activitySubscription;
  Future<void> Function()? _onSpeechEnded;
  String? _pendingTranscript;
  bool _disposed = false;
  ModelProviderMode? _previousProviderMode;

  VoiceSessionSnapshot get snapshot => state.value;
  bool get isActive => snapshot.active;
  bool get hasAttachedScreen => _onSpeechEnded != null;
  bool get isListening => speech.isListening;
  bool get voiceRequestActive => snapshot.voiceRequestActive;
  bool get bargeInActive => snapshot.bargeInActive;
  bool get bargeInReady => snapshot.bargeInReady;
  bool get aecAvailable => snapshot.aecAvailable;
  bool get finalizing => snapshot.finalizing;

  void attach({Future<void> Function()? onSpeechEnded}) {
    _onSpeechEnded = onSpeechEnded;
    if (snapshot.active && _activitySubscription == null) {
      _listenToActivity();
    }
    if (snapshot.bargeInReady && !snapshot.voiceRequestActive &&
        !snapshot.finalizing && _onSpeechEnded != null) {
      unawaited(_dispatchSpeechEnded());
    }
  }

  /// A route/screen can detach without cancelling microphone capture or VAD.
  void detach() {
    _onSpeechEnded = null;
  }

  void _emit(VoiceSessionSnapshot next) {
    if (!_disposed) state.value = next;
  }

  void setPhase(VoiceSessionPhase phase) {
    _emit(snapshot.copyWith(phase: phase));
  }

  void setTranscript(String transcript) {
    _emit(snapshot.copyWith(transcript: transcript));
  }

  void setVoiceRequestActive(bool value) {
    _emit(snapshot.copyWith(
      voiceRequestActive: value,
      phase: value ? VoiceSessionPhase.thinking : snapshot.phase,
    ));
  }

  void setFinalizing(bool value) {
    _emit(snapshot.copyWith(finalizing: value));
  }

  void rememberProviderMode(ModelProviderMode mode) {
    _previousProviderMode ??= mode;
  }

  Future<void> restoreProviderMode() async {
    final previous = _previousProviderMode;
    if (previous == null) return;
    _previousProviderMode = null;
    await ModelProviderSettings.instance.setMode(previous);
  }

  void setAecAvailable(bool value) {
    _emit(snapshot.copyWith(aecAvailable: value));
  }

  void setBargeInActive(bool value) {
    _emit(snapshot.copyWith(bargeInActive: value));
  }

  void setBargeInReady(bool value) {
    _emit(snapshot.copyWith(bargeInReady: value));
  }

  Future<void> startCapture() async {
    if (_disposed) throw StateError('Voice session controller is disposed.');
    if (speech.isListening) {
      _emit(snapshot.copyWith(active: true, isListening: true,
        phase: VoiceSessionPhase.listening, clearError: true));
      _listenToActivity();
      return;
    }
    await speech.startListening();
    _emit(snapshot.copyWith(active: true, isListening: true,
      transcript: '',
      phase: VoiceSessionPhase.listening, finalizing: false,
      clearError: true));
    _listenToActivity();
  }

  void _listenToActivity() {
    _activitySubscription ??= speech.activityEvents.listen(
      _handleActivity,
      onError: (Object error) {
        _emit(snapshot.copyWith(error: error.toString(),
          phase: VoiceSessionPhase.error));
      },
    );
  }

  void _handleActivity(Map<String, dynamic> event) {
    final type = event['type']?.toString() ?? '';
    if (type == 'speech_started' &&
        snapshot.voiceRequestActive &&
        snapshot.phase == VoiceSessionPhase.speaking &&
        speech.isListening &&
        snapshot.aecAvailable) {
      _emit(snapshot.copyWith(
        bargeInActive: true,
        bargeInReady: false,
        phase: VoiceSessionPhase.listening,
      ));
      unawaited(output.stop());
      return;
    }
    if (type == 'speech_ended' && snapshot.bargeInActive) {
      _emit(snapshot.copyWith(bargeInReady: true));
      if (!snapshot.voiceRequestActive && !snapshot.finalizing) {
        unawaited(_dispatchSpeechEnded());
      }
    }
  }

  Future<void> _dispatchSpeechEnded() async {
    final callback = _onSpeechEnded;
    if (callback != null) {
      await callback();
      return;
    }
    // The chat route may be temporarily absent. Preserve the user's completed
    // utterance instead of dropping it or binding work to a disposed State.
    if (speech.isListening && !snapshot.finalizing) {
      try {
        setFinalizing(true);
        final transcript = await speech.stopListening();
        _pendingTranscript = transcript;
        _emit(snapshot.copyWith(
          isListening: false,
          active: true,
          finalizing: false,
          bargeInActive: false,
          bargeInReady: false,
          phase: VoiceSessionPhase.listening,
          transcript: transcript,
        ));
      } catch (error) {
        _emit(snapshot.copyWith(finalizing: false,
          error: error.toString(), phase: VoiceSessionPhase.error));
      }
    }
  }

  String? takePendingTranscript() {
    final value = _pendingTranscript;
    _pendingTranscript = null;
    return value;
  }

  Future<String> stopCapture() async {
    if (!speech.isListening) {
      final buffered = _pendingTranscript ?? snapshot.transcript;
      _pendingTranscript = null;
      _emit(snapshot.copyWith(finalizing: false));
      return buffered;
    }
    setFinalizing(true);
    try {
      final transcript = await speech.stopListening();
      _emit(snapshot.copyWith(
        isListening: false,
        finalizing: false,
        transcript: transcript,
        clearError: true,
      ));
      return transcript;
    } catch (error) {
      _emit(snapshot.copyWith(finalizing: false,
        error: error.toString(), phase: VoiceSessionPhase.error));
      rethrow;
    }
  }

  Future<void> requestFinish() async {
    final callback = _onSpeechEnded;
    if (callback != null) {
      await callback();
      return;
    }
    final transcript = await stopCapture();
    if (transcript.isNotEmpty) _pendingTranscript = transcript;
  }

  Future<void> interruptAndListen() async {
    await output.stop();
    if (!speech.isListening) await startCapture();
    _emit(snapshot.copyWith(phase: VoiceSessionPhase.listening,
      voiceRequestActive: true, bargeInActive: true, bargeInReady: false));
  }

  Future<void> stopSession() async {
    _emit(snapshot.copyWith(finalizing: true));
    try {
      await speech.cancelListening();
      await output.stop();
    } finally {
      try {
        await restoreProviderMode();
      } catch (_) {}
      await _activitySubscription?.cancel();
      _activitySubscription = null;
      _pendingTranscript = null;
      _emit(const VoiceSessionSnapshot());
    }
  }
}
