import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Read-only GitHub repository connection for repository-aware chat context.
class GitHubRepositoryService {
  GitHubRepositoryService._();
  static final GitHubRepositoryService instance = GitHubRepositoryService._();
  static const _storage = FlutterSecureStorage();
  static const _repoKey = 'giant_github_repository';
  static const _tokenKey = 'giant_github_token';

  Future<String?> getRepository() => _storage.read(key: _repoKey);
  Future<bool> isConnected() async => (await getRepository())?.isNotEmpty == true;

  String _normalizeRepository(String input) {
    final value = input.trim().replaceFirst(RegExp(r'\.git$'), '');
    final match = RegExp(
      r'^(?:https?://)?(?:www\.)?github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)/?$',
      caseSensitive: false,
    ).firstMatch(value);
    if (match == null) {
      throw const FormatException('أدخل رابط مستودع GitHub بصيغة https://github.com/owner/repository');
    }
    return match.group(1)! + '/' + match.group(2)!;
  }

  Future<Map<String, dynamic>> connect({required String repositoryUrl, String token = ''}) async {
    final repository = _normalizeRepository(repositoryUrl);
    final cleanToken = token.trim();
    final previousToken = await _storage.read(key: _tokenKey) ?? '';
    final effectiveToken = cleanToken.isNotEmpty ? cleanToken : previousToken;
    final headers = <String, String>{
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'Giant-Agent-Mobile',
      if (effectiveToken.isNotEmpty) 'Authorization': 'Bearer ' + effectiveToken,
    };
    final response = await http.get(
      Uri.parse('https://api.github.com/repos/' + repository),
      headers: headers,
    ).timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw StateError(response.statusCode == 404
          ? 'لم يُعثر على المستودع أو لا يملك المفتاح صلاحية قراءته.'
          : 'تعذر الاتصال بـ GitHub (' + response.statusCode.toString() + ').');
    }
    final metadata = jsonDecode(response.body) as Map<String, dynamic>;
    await _storage.write(key: _repoKey, value: repository);
    if (effectiveToken.isNotEmpty) {
      await _storage.write(key: _tokenKey, value: effectiveToken);
    }
    return metadata;
  }

  Future<void> disconnect() async {
    await _storage.delete(key: _repoKey);
    await _storage.delete(key: _tokenKey);
  }

  Future<Map<String, String>> _headers() async {
    final token = await _storage.read(key: _tokenKey);
    return {
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'Giant-Agent-Mobile',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer ' + token,
    };
  }

  /// Repository metadata, bounded file tree and README. This is read-only;
  /// it does not push commits or modify repository files.
  Future<String> buildContext() async {
    final repository = await getRepository();
    if (repository == null || repository.isEmpty) throw StateError('لم يتم ربط مستودع GitHub.');
    final headers = await _headers();
    final repoResponse = await http.get(
      Uri.parse('https://api.github.com/repos/' + repository),
      headers: headers,
    ).timeout(const Duration(seconds: 25));
    if (repoResponse.statusCode != 200) {
      throw StateError('تعذر قراءة المستودع من GitHub (' + repoResponse.statusCode.toString() + ').');
    }
    final metadata = jsonDecode(repoResponse.body) as Map<String, dynamic>;
    final branch = metadata['default_branch']?.toString() ?? 'main';
    final treeResponse = await http.get(
      Uri.parse('https://api.github.com/repos/' + repository +
          '/git/trees/' + Uri.encodeComponent(branch) + '?recursive=1'),
      headers: headers,
    ).timeout(const Duration(seconds: 25));
    final paths = <String>[];
    if (treeResponse.statusCode == 200) {
      final tree = (jsonDecode(treeResponse.body) as Map<String, dynamic>)['tree'] as List<dynamic>? ?? const [];
      for (final item in tree) {
        if (item is Map && item['type'] == 'blob') {
          paths.add(item['path']?.toString() ?? '');
          if (paths.length >= 100) break;
        }
      }
    }
    var readme = '';
    final readmeResponse = await http.get(
      Uri.parse('https://api.github.com/repos/' + repository + '/readme'),
      headers: headers,
    ).timeout(const Duration(seconds: 25));
    if (readmeResponse.statusCode == 200) {
      final data = jsonDecode(readmeResponse.body) as Map<String, dynamic>;
      final encoded = (data['content']?.toString() ?? '').replaceAll('\n', '');
      try {
        readme = utf8.decode(base64.decode(base64.normalize(encoded)));
      } catch (_) {}
    }
    if (readme.length > 10000) readme = readme.substring(0, 10000) + '\n[README truncated]';
    return 'GitHub repository context (read-only):\n'
        'Repository: ' + repository + '\n'
        'Description: ' + (metadata['description']?.toString() ?? 'غير محدد') + '\n'
        'Default branch: ' + branch + '\n'
        'Language: ' + (metadata['language']?.toString() ?? 'غير محدد') + '\n'
        'Visibility: ' + (metadata['private'] == true ? 'private' : 'public') + '\n'
        'Files (first ' + paths.length.toString() + ' paths):\n' +
        paths.join('\n') + '\nREADME:\n' + readme +
        '\nUse this as repository evidence. Do not claim to edit, commit, or push files; this connection is read-only.';
  }
}
