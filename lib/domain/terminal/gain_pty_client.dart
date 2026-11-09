import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

/// Dart side of GainPtyBridge. One client owns one persistent native PTY
/// session; detaching a UI listener never stops that native session.
class GainPtyClient {
  GainPtyClient({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
    Stream<dynamic>? eventStream,
  })  : _methodChannel =
            methodChannel ?? const MethodChannel('giant_agent/pty'),
        _eventChannel =
            eventChannel ?? const EventChannel('giant_agent/pty/events'),
        _eventStream = eventStream {
    _decoderSubscription = _rawBytes.stream
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(_output.add, onError: _output.addError);
  }

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  final Stream<dynamic>? _eventStream;
  final StreamController<List<int>> _rawBytes =
      StreamController<List<int>>.broadcast();
  final StreamController<String> _output =
      StreamController<String>.broadcast();
  final StreamController<void> _closed =
      StreamController<void>.broadcast();

  StreamSubscription<dynamic>? _eventSubscription;
  StreamSubscription<String>? _decoderSubscription;
  final List<Map<dynamic, dynamic>> _pendingEvents = [];
  int? _handle;
  bool _starting = false;
  bool _running = false;
  bool _disposed = false;

  Stream<String> get output => _output.stream;
  Stream<void> get onSessionClosed => _closed.stream;
  bool get isRunning => _running;
  int? get sessionHandle => _handle;

  Future<bool> isAvailable() async {
    try {
      return await _methodChannel.invokeMethod<bool>('available') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> start({
    int rows = 24,
    int cols = 100,
    String shell = '/system/bin/sh',
  }) async {
    if (_disposed) throw StateError('GainPtyClient has been disposed.');
    if (shell.trim().startsWith('root:')) {
      throw ArgumentError.value(shell, 'shell', 'Gain root mode is disabled until an explicit approval flow exists.');
    }
    if (_running) return true;
    if (_starting) return false;
    _starting = true;
    _pendingEvents.clear();

    // Listen before native start: the shell may emit bytes before MethodChannel
    // returns the session handle.
    _eventSubscription ??= (_eventStream ?? _eventChannel.receiveBroadcastStream()).listen(
      (dynamic value) {
        if (value is! Map) return;
        final event = Map<dynamic, dynamic>.from(value);
        if (_starting) {
          if (_pendingEvents.length < 128) _pendingEvents.add(event);
        } else {
          _handleEvent(event);
        }
      },
      onError: (Object error, StackTrace stack) {
        _output.addError(error, stack);
      },
    );

    try {
      if (!await isAvailable()) {
        _starting = false;
        _pendingEvents.clear();
        return false;
      }
      final handle = await _methodChannel.invokeMethod<int>(
        'start',
        <String, Object>{
          'rows': rows.clamp(8, 100),
          'cols': cols.clamp(20, 240),
          'shell': shell,
        },
      );
      if (handle == null || handle <= 0) {
        _starting = false;
        _pendingEvents.clear();
        return false;
      }
      _handle = handle;
      _running = true;
      _starting = false;
      final early = List<Map<dynamic, dynamic>>.from(_pendingEvents);
      _pendingEvents.clear();
      for (final event in early) {
        _handleEvent(event);
      }
      return _running;
    } catch (_) {
      _starting = false;
      _pendingEvents.clear();
      _handle = null;
      _running = false;
      return false;
    }
  }

  void _handleEvent(Map<dynamic, dynamic> event) {
    if (event['sessionId'] != _handle) return;
    if (event['closed'] == true) {
      _running = false;
      _handle = null;
      _closed.add(null);
      return;
    }
    final data = event['data'];
    if (data is Uint8List) {
      _rawBytes.add(data);
    } else if (data is List<int>) {
      _rawBytes.add(data);
    }
  }

  Future<void> write(String value) =>
      writeBytes(Uint8List.fromList(utf8.encode(value)));

  Future<void> writeBytes(Uint8List bytes) async {
    final handle = _handle;
    if (!_running || handle == null) {
      throw StateError('Gain PTY session is not running.');
    }
    if (bytes.isEmpty) return;
    var offset = 0;
    var attempts = 0;
    while (offset < bytes.length) {
      final remaining = Uint8List.sublistView(bytes, offset);
      final written = await _methodChannel.invokeMethod<int>(
        'write',
        <String, Object>{'handle': handle, 'input': remaining},
      );
      if (written == null || written <= 0 || written > remaining.length) {
        throw StateError(
          'PTY accepted $offset/${bytes.length} bytes; the remaining input was not sent.',
        );
      }
      // Retry only the unsent suffix. Never resend bytes already accepted by
      // the PTY, because that could duplicate a command or keystroke.
      offset += written;
      attempts++;
      if (offset < bytes.length && attempts >= 3) {
        throw StateError(
          'PTY accepted $offset/${bytes.length} bytes after $attempts writes.',
        );
      }
    }
  }

  Future<void> interrupt() async {
    if (_running) await writeBytes(Uint8List.fromList([3]));
  }

  Future<bool> resize({required int rows, required int cols}) async {
    final handle = _handle;
    if (!_running || handle == null) return false;
    return await _methodChannel.invokeMethod<bool>(
          'resize',
          <String, Object>{
            'handle': handle,
            'rows': rows.clamp(8, 100),
            'cols': cols.clamp(20, 240),
          },
        ) ??
        false;
  }

  /// Explicitly stops the shell. UI stream cancellation does not call this.
  Future<void> stop() async {
    final handle = _handle;
    _handle = null;
    _running = false;
    if (handle != null) {
      try {
        await _methodChannel.invokeMethod<void>(
          'stop',
          <String, Object>{'handle': handle},
        );
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    await _decoderSubscription?.cancel();
    _decoderSubscription = null;
    await _rawBytes.close();
    await _output.close();
    await _closed.close();
    _disposed = true;
  }
}
