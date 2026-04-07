import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();
  
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  
  // تسجيل الدخول بدون بيانات
  Future<bool> guestLogin() async {
    await _storage.write(key: 'is_logged_in', value: 'true');
    await _storage.write(key: 'user_type', value: 'guest');
    await _storage.write(key: 'user_name', value: 'Guest User');
    return true;
  }
  
  // تسجيل الدخول السريع
  Future<bool> quickLogin() async {
    await _storage.write(key: 'is_logged_in', value: 'true');
    await _storage.write(key: 'user_type', value: 'quick');
    await _storage.write(key: 'user_name', value: 'User');
    return true;
  }
  
  // تسجيل الخروج
  Future<void> logout() async {
    await _storage.write(key: 'is_logged_in', value: 'false');
  }
  
  // التحقق من حالة الدخول
  Future<bool> isLoggedIn() async {
    return await _storage.read(key: 'is_logged_in') == 'true';
  }
  
  // الحصول على اسم المستخدم
  Future<String?> getUserName() async {
    return await _storage.read(key: 'user_name');
  }
  
  // الحصول على نوع المستخدم
  Future<String?> getUserType() async {
    return await _storage.read(key: 'user_type');
  }
}
