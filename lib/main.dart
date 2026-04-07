import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screens/welcome_screen.dart';
import 'screens/chat_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await [
    Permission.storage,
    Permission.photos,
    Permission.camera,
    Permission.microphone,
  ].request();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Giant Agent X',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF6C63FF),
        scaffoldBackgroundColor: Colors.white,
        useMaterial3: true,
        fontFamily: 'Cairo',
      ),
      home: const WelcomeScreen(),
    );
  }
}
