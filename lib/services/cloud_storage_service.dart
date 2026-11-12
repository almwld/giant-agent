import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Nextcloud and other WebDAV-compatible cloud storage.
class CloudStorageService {
  CloudStorageService._();
  static final CloudStorageService instance = CloudStorageService._();
  static const _storage = FlutterSecureStorage();
  static const _serverKey = 'giant_cloud_server';
  static const _userKey = 'giant_cloud_username';
  static const _passwordKey = 'giant_cloud_app_password';

  Future<Map<String, String>> getConfiguration() async => {
    'server': await _storage.read(key: _serverKey) ?? '',
    'username': await _storage.read(key: _userKey) ?? '',
    'password': await _storage.read(key: _passwordKey) ?? '',
  };

  Future<void> configure({
    required String server,
    required String username,
    required String appPassword,
  }) async {
    final parsed = Uri.tryParse(server.trim());
    if (parsed == null || !parsed.hasAuthority ||
        !{'https', 'http'}.contains(parsed.scheme) || parsed.host.isEmpty) {
      throw const FormatException('أدخل عنوان خادم سحابي صحيحاً.');
    }
    if (parsed.scheme != 'https' && parsed.host != '10.0.2.2' &&
        parsed.host != 'localhost' && !parsed.host.startsWith('192.168.')) {
      throw const FormatException('استخدم HTTPS لحماية بيانات الدخول.');
    }
    if (username.trim().isEmpty || appPassword.isEmpty) {
      throw const FormatException('اسم المستخدم وكلمة مرور التطبيق مطلوبان.');
    }
    final normalized = parsed.toString().replaceFirst(RegExp(r'/$'), '');
    await _storage.write(key: _serverKey, value: normalized);
    await _storage.write(key: _userKey, value: username.trim());
    await _storage.write(key: _passwordKey, value: appPassword);
  }

  Future<void> disconnect() async {
    await _storage.delete(key: _serverKey);
    await _storage.delete(key: _userKey);
    await _storage.delete(key: _passwordKey);
  }

  Future<Uri> uploadWorkspace(File file) async {
    final config = await getConfiguration();
    final server = config['server'] ?? '';
    final username = config['username'] ?? '';
    final password = config['password'] ?? '';
    if (server.isEmpty || username.isEmpty || password.isEmpty) {
      throw StateError('أكمل إعداد اتصال السحابة أولاً.');
    }
    if (!await file.exists()) throw FileSystemException('ملف مساحة العمل غير موجود.', file.path);
    final auth = base64.encode(utf8.encode(username + ':' + password));
    final root = Uri.parse(server);
    final encodedUser = Uri.encodeComponent(username);
    final folder = root.replace(
      path: root.path.replaceFirst(RegExp(r'/$'), '') +
          '/remote.php/dav/files/' + encodedUser + '/GiantAgent',
      query: null,
      fragment: null,
    );
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 25);
    try {
      final mkcol = await client.openUrl('MKCOL', folder);
      mkcol.headers.set(HttpHeaders.authorizationHeader, 'Basic ' + auth);
      final folderResponse = await mkcol.close();
      await folderResponse.drain<void>();
      if (folderResponse.statusCode >= 400 &&
          folderResponse.statusCode != HttpStatus.methodNotAllowed &&
          folderResponse.statusCode != HttpStatus.conflict) {
        throw HttpException('تعذر إنشاء مجلد GiantAgent في السحابة (' +
            folderResponse.statusCode.toString() + ').');
      }
      final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
      final target = folder.replace(path: folder.path + '/workspace_' + stamp + '.zip');
      final request = await client.openUrl('PUT', target);
      request.headers.set(HttpHeaders.authorizationHeader, 'Basic ' + auth);
      request.headers.contentType = ContentType('application', 'zip');
      request.contentLength = await file.length();
      await request.addStream(file.openRead());
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('فشل رفع الملف إلى السحابة (' + response.statusCode.toString() + ').');
      }
      return target;
    } finally {
      client.close(force: true);
    }
  }
}
