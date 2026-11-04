import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Reads the latest published GitHub release for this application.
/// Download/install is deliberately left to the platform package installer;
/// this service never claims an update was installed.
class AutoUpdater {
  AutoUpdater._internal();
  static final AutoUpdater _instance = AutoUpdater._internal();
  factory AutoUpdater() => _instance;

  static const String repository = 'almwld/giant-agent';
  static const String currentVersion = '6.0.0';
  String _latestReleaseBody = '';

  Future<Map<String, dynamic>> checkForUpdates() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.getUrl(Uri.https(
        'api.github.com',
        '/repos/$repository/releases/latest',
      ));
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(HttpHeaders.userAgentHeader, 'Giant-Agent-Updater');
      final response = await request.close().timeout(const Duration(seconds: 15));
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode == HttpStatus.notFound) {
        return {
          'has_update': false,
          'version': currentVersion,
          'latest_version': currentVersion,
          'message': 'لا يوجد إصدار منشور في GitHub Releases حالياً.',
          'available': false,
        };
      }
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('GitHub API returned HTTP ${response.statusCode}.');
      }
      final release = jsonDecode(body) as Map<String, dynamic>;
      final tag = (release['tag_name'] ?? '').toString().replaceFirst(RegExp(r'^v'), '');
      if (tag.isEmpty) throw const FormatException('Release tag is missing.');
      _latestReleaseBody = (release['body'] ?? '').toString();
      final assets = (release['assets'] as List? ?? const [])
          .whereType<Map>()
          .map((asset) => {
                'name': asset['name']?.toString() ?? '',
                'download_url': asset['browser_download_url']?.toString() ?? '',
                'size': asset['size'] ?? 0,
              })
          .toList(growable: false);
      final comparison = _compareVersions(tag, currentVersion);
      return {
        'has_update': comparison > 0,
        'version': currentVersion,
        'latest_version': tag,
        'message': comparison > 0 ? 'يتوفر إصدار أحدث.' : 'التطبيق على أحدث إصدار منشور.',
        'available': true,
        'release_name': release['name']?.toString() ?? tag,
        'release_url': release['html_url']?.toString() ?? '',
        'published_at': release['published_at']?.toString() ?? '',
        'changelog': _latestReleaseBody,
        'assets': assets,
      };
    } on TimeoutException {
      return {'has_update': false, 'version': currentVersion, 'latest_version': null,
        'available': false, 'message': 'انتهت مهلة الاتصال بخدمة التحديثات.'};
    } catch (error) {
      return {'has_update': false, 'version': currentVersion, 'latest_version': null,
        'available': false, 'message': 'تعذر التحقق من التحديثات: $error'};
    } finally {
      client.close(force: true);
    }
  }

  Future<String> getChangelog() async => _latestReleaseBody;

  int _compareVersions(String left, String right) {
    List<int> parts(String value) => value
        .split('+').first.split('-').first.split('.')
        .map((part) => int.tryParse(part) ?? 0).toList();
    final a = parts(left), b = parts(right);
    for (var i = 0; i < (a.length > b.length ? a.length : b.length); i++) {
      final av = i < a.length ? a[i] : 0;
      final bv = i < b.length ? b[i] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }
}
