import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();
  
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  
  Future<bool> signUp(String email, String password) async {
    await _storage.write(key: 'user_email', value: email);
    await _storage.write(key: 'user_password', value: password);
    await _storage.write(key: 'is_logged_in', value: 'true');
    return true;
  }
  
  Future<bool> signIn(String email, String password) async {
    final storedEmail = await _storage.read(key: 'user_email');
    final storedPassword = await _storage.read(key: 'user_password');
    
    if (storedEmail == email && storedPassword == password) {
      await _storage.write(key: 'is_logged_in', value: 'true');
      return true;
    }
    return false;
  }
  
  Future<void> signOut() async {
    await _storage.write(key: 'is_logged_in', value: 'false');
  }
  
  Future<bool> isLoggedIn() async {
    return await _storage.read(key: 'is_logged_in') == 'true';
  }
  
  Future<String?> getCurrentUser() async {
    return await _storage.read(key: 'user_email');
  }
}
