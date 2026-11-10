import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../services/agent_service.dart';
import '../services/app_preferences.dart';
import '../services/model_service.dart';

/// Voice interaction states shown by the assistant UI.
enum AgentState {
  idle,
  listening,
  thinking,
  speaking,
  error,
}

/// Controller for the voice assistant.
///
/// All requests are sent through AgentService.instance, which delegates to the
/// existing shared AgentKernel/ModelService runtime. This screen deliberately
/// does not create or load a second LlamaService or model instance.
class AgentController extends ChangeNotifier {
  AgentController({
    stt.SpeechToText? speech,
    FlutterTts? textToSpeech,
    AgentService? agentService,
  })  : _speech = speech ?? stt.SpeechToText(),
        _tts = textToSpeech ?? FlutterTts(),
        _agent = agentService ?? AgentService.instance;

  final stt.SpeechToText _speech;
  final FlutterTts _tts;
  final AgentService _agent;

  AgentState _state = AgentState.idle;
  String _transcription = '';
  String _response = '';
  String _statusMessage = '';
  bool _speechAvailable = false;
  bool _speechEnabled = true;
  bool _disposed = false;
  StreamSubscription<dynamic>? _eventSubscription;

  AgentState get state => _state;
  String get transcription => _transcription;
  String get response => _response;
  String get statusMessage => _statusMessage;
  bool get speechAvailable => _speechAvailable;
  bool get speechEnabled => _speechEnabled;
  bool get isBusy =>
      _state == AgentState.listening ||
      _state == AgentState.thinking ||
      _state == AgentState.speaking;

  void _setState(AgentState value, {String? message}) {
    if (_disposed) return;
    _state = value;
    if (message != null) _statusMessage = message;
    notifyListeners();
  }

  Future<void> initialize() async {
    try {
      await _tts.setSpeechRate(0.48);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(true);
    } catch (_) {
      // TTS availability varies by Android device and installed voice packs.
    }

    try {
      _speechAvailable = await _speech.initialize(
        onStatus: (status) {
          if (_disposed) return;
          if (status == 'notListening' && _state == AgentState.listening) {
            _setState(AgentState.idle, message: 'انتهى الاستماع.');
          }
        },
        onError: (error) {
          if (_disposed) return;
          _setState(
            AgentState.error,
            message: 'تعذر تشغيل التعرف على الصوت: ${error.errorMsg}',
          );
        },
        debugLogging: false,
      );
    } catch (error) {
      _speechAvailable = false;
      _setState(
        AgentState.error,
        message: 'خدمة التعرف على الصوت غير متاحة: $error',
      );
    }

    _eventSubscription ??= _agent.events.listen(
      (event) {
        if (_disposed || !isBusy) return;
        // Timeline events are progress metadata only; private model reasoning
        // is never read or displayed by this screen.
        final title = event.title.toString().trim();
        if (title.isNotEmpty && _state == AgentState.thinking) {
          _statusMessage = title;
          notifyListeners();
        }
      },
      onError: (_) {},
    );

    if (_state != AgentState.error) {
      _setState(
        AgentState.idle,
        message: _speechAvailable
            ? 'جاهز للاستماع أو استقبال رسالتك.'
            : 'يمكنك الكتابة؛ التعرف على الصوت غير متاح حالياً.',
      );
    }
  }

  Future<void> startListening() async {
    if (_disposed || isBusy) return;
    if (!_speechAvailable) {
      await initialize();
      if (!_speechAvailable) {
        _setState(
          AgentState.error,
          message: 'لم يتم العثور على خدمة للتعرف على الصوت. تحقق من أذونات الميكروفون وخدمة Google Speech.',
        );
        return;
      }
    }

    try {
      await _tts.stop();
      _transcription = '';
      _setState(AgentState.listening, message: 'أستمع إليك الآن...');
      final localeCode = AppPreferences.instance.locale.languageCode;
      final locales = await _speech.locales();
      final matching = locales.where(
        (locale) => locale.localeId.toLowerCase().startsWith(localeCode),
      );
      final selectedLocale = matching.isNotEmpty ? matching.first.localeId : null;

      await _speech.listen(
        onResult: (result) {
          if (_disposed) return;
          _transcription = result.recognizedWords;
          notifyListeners();
          if (result.finalResult) {
            _setState(AgentState.idle, message: 'تم التقاط كلامك.');
          }
        },
        localeId: selectedLocale,
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
          cancelOnError: true,
        ),
      );
    } catch (error) {
      _setState(AgentState.error, message: 'تعذر بدء الاستماع: $error');
    }
  }

  Future<void> stopListening() async {
    try {
      await _speech.stop();
    } catch (_) {}
    if (!_disposed && _state == AgentState.listening) {
      _setState(AgentState.idle, message: 'تم إيقاف الاستماع.');
    }
  }

  Future<void> submitRequest(String request) async {
    final prompt = request.trim();
    if (_disposed || prompt.isEmpty || _state == AgentState.thinking) return;

    try {
      await _speech.stop();
      await _tts.stop();
      _response = '';
      _transcription = prompt;
      _setState(AgentState.thinking, message: 'أرسل طلبك إلى محرك Giant Agent...');

      // AgentService uses the existing singleton kernel/runtime. It does not
      // instantiate another model or bypass the normal agent orchestration.
      final output = await _agent.runTask(
        prompt,
        conversationId: 'voice-assistant',
      );

      if (_disposed) return;
      _response = output.trim().isEmpty
          ? 'اكتمل الطلب دون إرجاع نص.'
          : output.trim();

      if (_speechEnabled && _response.isNotEmpty) {
        _setState(AgentState.speaking, message: 'أقرأ الإجابة بصوت مسموع...');
        try {
          await _tts.setLanguage(
            AppPreferences.instance.locale.languageCode == 'ar'
                ? 'ar'
                : 'en-US',
          );
          await _tts.speak(_response);
        } catch (error) {
          // A missing TTS voice must not turn a successful model response into
          // a failed agent request.
          _statusMessage = 'اكتملت الإجابة؛ تعذر تشغيل الصوت على هذا الجهاز.';
        }
      }

      _setState(AgentState.idle, message: 'اكتملت الإجابة.');
    } catch (error) {
      if (_disposed) return;
      _response = 'تعذر إكمال الطلب: $error';
      _setState(AgentState.error, message: 'حدث خطأ أثناء تنفيذ الطلب.');
    }
  }

  Future<void> toggleSpeech() async {
    _speechEnabled = !_speechEnabled;
    if (!_speechEnabled) {
      try {
        await _tts.stop();
      } catch (_) {}
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> stopSpeaking() async {
    try {
      await _tts.stop();
    } catch (_) {}
    if (!_disposed && _state == AgentState.speaking) {
      _setState(AgentState.idle, message: 'تم إيقاف القراءة الصوتية.');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _eventSubscription?.cancel();
    _speech.stop();
    _tts.stop();
    super.dispose();
  }
}

/// Animated visual indicator for the voice assistant state.
/// The approved glass-sphere Lottie is the single visualizer for all voice states.
class GlowingOrb extends StatefulWidget {
  const GlowingOrb({super.key, required this.state, this.size = 230});
  final AgentState state;
  final double size;

  @override
  State<GlowingOrb> createState() => _GlowingOrbState();
}

class _GlowingOrbState extends State<GlowingOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this);

  Duration get _period {
    switch (widget.state) {
      case AgentState.idle:
        return const Duration(seconds: 12);
      case AgentState.listening:
        return const Duration(seconds: 7);
      case AgentState.thinking:
        return const Duration(milliseconds: 4500);
      case AgentState.speaking:
        return const Duration(seconds: 3);
      case AgentState.error:
        return const Duration(seconds: 2);
    }
  }

  String get _semanticLabel {
    switch (widget.state) {
      case AgentState.idle: return 'المساعد الصوتي جاهز';
      case AgentState.listening: return 'المساعد يستمع';
      case AgentState.thinking: return 'المساعد يعالج طلبك';
      case AgentState.speaking: return 'المساعد يتحدث';
      case AgentState.error: return 'حالة خطأ في المساعد';
    }
  }

  void _syncToVoiceState() {
    if (!_controller.isAnimating) {
      _controller.repeat(period: _period, reverse: widget.state == AgentState.error);
    } else {
      _controller.stop();
      _controller.repeat(period: _period, reverse: widget.state == AgentState.error);
    }
  }

  @override
  void didUpdateWidget(covariant GlowingOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) _syncToVoiceState();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: _semanticLabel,
    child: SizedBox(
      width: widget.size,
      height: widget.size,
      child: Lottie.asset(
        'assets/animations/voice_orb.json',
        controller: _controller,
        fit: BoxFit.contain,
        repeat: true,
        animate: true,
        frameRate: FrameRate.max,
        onLoaded: (_) => _syncToVoiceState(),
        errorBuilder: (context, error, stackTrace) => const Center(
          child: Icon(Icons.graphic_eq_rounded, color: Colors.white70, size: 54),
        ),
      ),
    ),
  );
}

/// Full-screen voice interface backed by the app's existing agent runtime.
class AiVoiceAssistantScreen extends StatefulWidget {
  const AiVoiceAssistantScreen({super.key});

  @override
  State<AiVoiceAssistantScreen> createState() =>
      _AiVoiceAssistantScreenState();
}

class _AiVoiceAssistantScreenState extends State<AiVoiceAssistantScreen> {
  late final AgentController _agentController;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ModelService _modelService = ModelService();

  bool get _isArabic =>
      AppPreferences.instance.locale.languageCode == 'ar';

  @override
  void initState() {
    super.initState();
    _agentController = AgentController();
    _agentController.initialize();
  }

  @override
  void dispose() {
    _agentController.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _textController.text.trim().isNotEmpty
        ? _textController.text.trim()
        : _agentController.transcription.trim();
    if (text.isEmpty || _agentController.isBusy) return;
    _textController.clear();
    await _agentController.submitRequest(text);
    if (mounted && _scrollController.hasClients) {
      await _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _showModelPicker() async {
    if (_agentController.isBusy) return;
    final models = _modelService.getModels();
    if (models.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isArabic
                ? 'لم يتم العثور على نماذج GGUF. استورد نموذجاً من الشاشة الرئيسية أولاً.'
                : 'No GGUF models found. Import a model from the main screen first.',
          ),
        ),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(
                _isArabic ? 'اختر النموذج المحلي' : 'Choose local model',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final model in models)
              ListTile(
                leading: Icon(
                  model['id'] == _modelService.getActiveModel()['id']
                      ? Icons.check_circle_rounded
                      : Icons.memory_rounded,
                  color: model['id'] == _modelService.getActiveModel()['id']
                      ? const Color(0xFF34D399)
                      : const Color(0xFF64748B),
                ),
                title: Text(model['name']?.toString() ?? 'GGUF'),
                subtitle: Text(
                  '${model['size'] ?? ''} • ${model['type'] ?? 'GGUF'}',
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final ok = await _modelService.switchModel(
                    model['id'].toString(),
                  );
                  if (!mounted) return;
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        ok
                            ? (_isArabic
                                ? 'تم تفعيل ${model['name']}'
                                : '${model['name']} is now active')
                            : (_isArabic
                                ? 'تعذر تحميل النموذج المحدد'
                                : 'Could not load the selected model'),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  String _stateLabel(AgentState state) {
    if (_isArabic) {
      switch (state) {
        case AgentState.idle:
          return 'جاهز لمساعدتك';
        case AgentState.listening:
          return 'أستمع إليك';
        case AgentState.thinking:
          return 'أعمل على طلبك';
        case AgentState.speaking:
          return 'أتحدث إليك';
        case AgentState.error:
          return 'تعذر إكمال العملية';
      }
    }
    switch (state) {
      case AgentState.idle:
        return 'Ready when you are';
      case AgentState.listening:
        return 'Listening';
      case AgentState.thinking:
        return 'Working on your request';
      case AgentState.speaking:
        return 'Speaking';
      case AgentState.error:
        return 'Something went wrong';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: _agentController,
      builder: (context, _) {
        final state = _agentController.state;
        final busy = _agentController.isBusy;
        final foreground = isDark ? Colors.white : const Color(0xFF171923);
        final muted = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF687080);
        return Scaffold(
          backgroundColor: isDark
              ? const Color(0xFF10131B)
              : const Color(0xFFF5F6FA),
          appBar: AppBar(
            leading: IconButton(
              tooltip: _isArabic ? 'رجوع' : 'Back',
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isArabic ? 'المساعد الصوتي' : 'Voice Assistant',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  _modelService.getActiveModelName(),
                  style: TextStyle(fontSize: 10, color: muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: _isArabic ? 'اختيار النموذج' : 'Select model',
                onPressed: _showModelPicker,
                icon: const Icon(Icons.memory_rounded),
              ),
              IconButton(
                tooltip: _agentController.speechEnabled
                    ? (_isArabic ? 'إيقاف النطق' : 'Mute speech')
                    : (_isArabic ? 'تفعيل النطق' : 'Enable speech'),
                onPressed: _agentController.toggleSpeech,
                icon: Icon(
                  _agentController.speechEnabled
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded,
                ),
              ),
              const SizedBox(width: 6),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(22, 12, 22, 20),
                    children: [
                      const SizedBox(height: 12),
                      Center(
                        child: GlowingOrb(
                          state: state,
                          size: math.min(
                            MediaQuery.of(context).size.width * 0.68,
                            260,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Center(
                        child: Text(
                          _stateLabel(state),
                          style: TextStyle(
                            color: foreground,
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          _agentController.statusMessage,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                      ),
                      if (_agentController.transcription.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        _contentCard(
                          title: _isArabic ? 'ما سمعته' : 'What I heard',
                          text: _agentController.transcription,
                          foreground: foreground,
                          muted: muted,
                        ),
                      ],
                      if (_agentController.response.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _contentCard(
                          title: _isArabic ? 'الإجابة' : 'Response',
                          text: _agentController.response,
                          foreground: foreground,
                          muted: muted,
                        ),
                      ],
                      if (state == AgentState.error) ...[
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: _agentController.initialize,
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(_isArabic ? 'إعادة المحاولة' : 'Try again'),
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _textController,
                              minLines: 1,
                              maxLines: 4,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _submit(),
                              decoration: InputDecoration(
                                hintText: _isArabic
                                    ? 'اكتب ما تريد قوله...'
                                    : 'Type your message...',
                                filled: true,
                                fillColor: isDark
                                    ? const Color(0xFF1B202C)
                                    : Colors.white,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 13,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(18),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 9),
                          IconButton.filled(
                            onPressed: busy ? null : _submit,
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                              fixedSize: const Size(52, 52),
                            ),
                            icon: const Icon(Icons.send_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 13),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (busy) ...[
                            OutlinedButton.icon(
                              onPressed: state == AgentState.listening
                                  ? _agentController.stopListening
                                  : state == AgentState.speaking
                                      ? _agentController.stopSpeaking
                                      : null,
                              icon: const Icon(Icons.stop_rounded, size: 18),
                              label: Text(_isArabic ? 'إيقاف' : 'Stop'),
                            ),
                          ] else
                            GestureDetector(
                              onTap: _agentController.startListening,
                              child: Container(
                                width: 66,
                                height: 66,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFF2563EB),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF2563EB)
                                          .withOpacity(0.24),
                                      blurRadius: 22,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.mic_rounded,
                                  color: Colors.white,
                                  size: 29,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Text(
                        _isArabic
                            ? 'اضغط على الميكروفون للتحدث أو اكتب رسالتك'
                            : 'Tap the microphone or type a message',
                        style: TextStyle(color: muted, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _contentCard({
    required String title,
    required String text,
    required Color foreground,
    required Color muted,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B202C) : Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: isDark ? const Color(0xFF2A3342) : const Color(0xFFE5E7EB),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: muted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            text,
            style: TextStyle(
              color: foreground,
              fontSize: 14,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}
