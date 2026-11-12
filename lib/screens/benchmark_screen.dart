import 'package:flutter/material.dart';
import '../services/model_service.dart';

class BenchmarkScreen extends StatefulWidget {
  const BenchmarkScreen({super.key});

  @override
  State<BenchmarkScreen> createState() => _BenchmarkScreenState();
}

class _BenchmarkScreenState extends State<BenchmarkScreen> {
  final ModelService _modelService = ModelService();
  bool _isRunning = false;
  String _result = '';

  Future<void> _runBenchmark() async {
    if (_isRunning) return;
    setState(() {
      _isRunning = true;
      _result = '';
    });

    final stopwatch = Stopwatch()..start();
    String result;
    try {
      if (!_modelService.hasActiveModel() || !await _modelService.isModelLoaded()) {
        result = 'لا يمكن إجراء القياس: لم يتم تحميل نموذج GGUF محلي.';
      } else {
        result = await _modelService.processInput(
          'أجب بكلمة واحدة: جاهز',
          conversationId: 'benchmark',
        );
        stopwatch.stop();
        result = 'زمن الاستجابة: ${stopwatch.elapsedMilliseconds} ms\n'
            'النموذج: ${_modelService.getActiveModelName()}\n\n'
            'استجابة الاختبار:\n$result';
      }
    } catch (error) {
      result = 'فشل اختبار الأداء: $error';
    } finally {
      stopwatch.stop();
    }

    if (!mounted) return;
    setState(() {
      _result = result;
      _isRunning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('اختبار الأداء'), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isRunning ? null : _runBenchmark,
                icon: const Icon(Icons.speed),
                label: Text(_isRunning ? 'جارٍ القياس...' : 'بدء اختبار النموذج المحلي'),
              ),
            ),
            const SizedBox(height: 16),
            if (_isRunning) const LinearProgressIndicator(),
            if (_result.isNotEmpty)
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(_result),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
