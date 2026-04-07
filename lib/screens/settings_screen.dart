import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الإعدادات'),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.share),
            title: const Text('مشاركة التطبيق'),
            onTap: () {
              Share.share('جرب تطبيق Giant Agent X - أقوى وكيل ذكاء اصطناعي!');
            },
          ),
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text('عن التطبيق'),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: 'Giant Agent X',
                applicationVersion: '5.0.0',
                applicationIcon: const Icon(Icons.bolt, size: 30),
                children: [
                  const Text('الوكيل العملاق للذكاء الاصطناعي'),
                  const SizedBox(height: 8),
                  const Text('• تشغيل نماذج TFLite'),
                  const Text('• رفع ملفات وصور'),
                  const Text('• محادثة ذكية'),
                  const Text('• حفظ المحادثات'),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
