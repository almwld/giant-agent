import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screens/nuclear_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await [Permission.storage].request();
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
        brightness: Brightness.dark,
        primaryColor: Colors.deepPurple,
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const NuclearScreen(),
    );
  }
}
