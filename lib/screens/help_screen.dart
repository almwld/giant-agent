import 'package:flutter/material.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('المساعدة'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection('🚀 البدء السريع', [
            _buildStep('1', 'افتح القائمة الجانبية ☰'),
            _buildStep('2', 'اضغط "استيراد نموذج"'),
            _buildStep('3', 'اختر ملف .tflite من هاتفك'),
            _buildStep('4', 'ابدأ المحادثة!'),
          ]),
          _buildSection('📁 أنواع الملفات المدعومة', [
            _buildBullet('TFLite (.tflite) - نماذج TensorFlow'),
            _buildBullet('ONNX (.onnx) - نماذج مفتوحة المصدر'),
            _buildBullet('GGUF (.gguf) - نماذج Llama.cpp'),
          ]),
          _buildSection('💬 الأوامر المفيدة', [
            _buildBullet('مرحبا - تحية'),
            _buildBullet('كيف حالك - السؤال عن الحال'),
            _buildBullet('اكتب كود - توليد كود برمجي'),
            _buildBullet('أنشئ موقعاً - إنشاء HTML'),
            _buildBullet('5+3 - عمليات حسابية'),
          ]),
          _buildSection('🔧 حل المشكلات', [
            _buildBullet('النموذج لا يظهر؟ اضغط "تحديث"'),
            _buildBullet('خطأ في التحميل؟ تأكد من صلاحيات التخزين'),
            _buildBullet('بطء في الاستجابة؟ استخدم نموذجاً أصغر'),
          ]),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                const Icon(Icons.support_agent, size: 40, color: Colors.blue),
                const SizedBox(height: 8),
                const Text(
                  'تحتاج مساعدة؟',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'تواصل معنا عبر البريد الإلكتروني',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSection(String title, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
  
  Widget _buildStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.deepPurple,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
  
  Widget _buildBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Text('• ', style: TextStyle(fontSize: 16)),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
