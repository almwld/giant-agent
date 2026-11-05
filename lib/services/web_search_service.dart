import 'dart:convert';
import 'package:http/http.dart' as http;

/// Lightweight interactive web search using DuckDuckGo's HTML results page.
class WebSearchService {
  WebSearchService._();
  static final WebSearchService instance = WebSearchService._();

  String _clean(String value) {
    var text = value.replaceAll(RegExp(r'<[^>]*>'), ' ');
    text = text
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'&#(\d+);'), (m) =>
            String.fromCharCode(int.tryParse(m.group(1) ?? '') ?? 32))
        .replaceAll(RegExp(r'&#x([0-9a-fA-F]+);'), (m) =>
            String.fromCharCode(int.tryParse(m.group(1) ?? '', radix: 16) ?? 32));
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Future<List<Map<String, String>>> search(String query, {int limit = 5}) async {
    final value = query.trim();
    if (value.isEmpty) return const [];
    final uri = Uri.https('html.duckduckgo.com', '/html/', {'q': value});
    final response = await http.get(uri, headers: {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36',
      'Accept': 'text/html',
    }).timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw StateError('تعذر البحث على الويب (' + response.statusCode.toString() + ').');
    }
    final html = utf8.decode(response.bodyBytes, allowMalformed: true);
    final anchors = RegExp(r'<a\b[^>]*>.*?</a>', caseSensitive: false, dotAll: true)
        .allMatches(html);
    final results = <Map<String, String>>[];
    for (final match in anchors) {
      final tag = match.group(0) ?? '';
      if (!tag.contains('result__a')) continue;
      final hrefMatch = RegExp(r'href="([^"]+)"', caseSensitive: false).firstMatch(tag);
      final titleMatch = RegExp(r'>(.*?)</a>', caseSensitive: false, dotAll: true).firstMatch(tag);
      if (hrefMatch == null || titleMatch == null) continue;
      var url = hrefMatch.group(1)!.replaceAll('&amp;', '&');
      final parsed = Uri.tryParse(url);
      if (parsed != null && parsed.host.contains('duckduckgo.com') &&
          parsed.queryParameters.containsKey('uddg')) {
        url = parsed.queryParameters['uddg'] ?? url;
      }
      final target = Uri.tryParse(url);
      if (target == null || !{'http', 'https'}.contains(target.scheme) ||
          target.host.isEmpty || target.host.contains('duckduckgo.com')) continue;
      final before = html.substring((match.start - 100).clamp(0, html.length), match.start);
      final after = html.substring(match.end, (match.end + 1300).clamp(0, html.length));
      final snippetMatch = RegExp(
        r'class="[^"]*result__snippet[^"]*"[^>]*>(.*?)</',
        caseSensitive: false,
        dotAll: true,
      ).firstMatch(before + tag + after);
      final title = _clean(titleMatch.group(1) ?? '');
      final snippet = _clean(snippetMatch?.group(1) ?? '');
      if (title.isEmpty || results.any((item) => item['url'] == target.toString())) continue;
      results.add({'title': title, 'url': target.toString(), 'snippet': snippet});
      if (results.length >= limit.clamp(1, 8)) break;
    }
    return results;
  }

  String formatForPrompt(List<Map<String, String>> results) {
    if (results.isEmpty) return 'لم يُعثر على نتائج ويب قابلة للاستخدام.';
    return results.asMap().entries.map((entry) {
      final item = entry.value;
      return (entry.key + 1).toString() + '. ' + (item['title'] ?? '') +
          '\nURL: ' + (item['url'] ?? '') +
          '\nSnippet: ' + (item['snippet'] ?? '');
    }).join('\n\n');
  }
}
