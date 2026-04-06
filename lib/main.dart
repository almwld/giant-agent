import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screens/nuclear_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await [Permission.storage].request();
  runApp(const NuclearApp());
}

class NuclearApp extends StatelessWidget {
  const NuclearApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nuclear Giant Agent',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: Colors.red.shade900,
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.red.shade900,
          elevation: 0,
          centerTitle: true,
        ),
      ),
      home: const NuclearScreen(),
    );
  }
}
