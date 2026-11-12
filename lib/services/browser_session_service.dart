import 'dart:async';
import 'dart:convert';

import 'package:webview_flutter/webview_flutter.dart';

/// One user-visible WebView session shared by browser tools in the current app.
/// This is deliberately not a hidden remote browser or a screenshot service.
class BrowserSessionService {
  BrowserSessionService._();
  static final BrowserSessionService instance = BrowserSessionService._();

  WebViewController? _controller;
  Completer<void> _ready = Completer<void>();
  Completer<void> _pageLoaded = Completer<void>();
  String? _pageError;

  bool get isAttached => _controller != null;

  void _checkCancelled(bool Function()? isCancelled) {
    if (isCancelled?.call() == true) {
      throw StateError('Browser tool call cancelled.');
    }
  }

  Future<T> _awaitCancellable<T>(
    Future<T> operation,
    bool Function()? isCancelled,
  ) async {
    if (isCancelled == null) return operation;
    _checkCancelled(isCancelled);
    final result = Completer<T>();
    final poll = Timer.periodic(const Duration(milliseconds: 75), (_) {
      if (!result.isCompleted && isCancelled()) {
        result.completeError(StateError('Browser tool call cancelled.'));
      }
    });
    operation.then(
      (value) {
        if (!result.isCompleted) result.complete(value);
      },
      onError: (Object error, StackTrace stack) {
        if (!result.isCompleted) result.completeError(error, stack);
      },
    );
    try {
      return await result.future;
    } finally {
      poll.cancel();
    }
  }

  void attach(WebViewController controller) {
    _controller = controller;
    if (!_ready.isCompleted) _ready.complete();
  }

  void detach(WebViewController controller) {
    if (!identical(_controller, controller)) return;
    if (!_pageLoaded.isCompleted) _pageLoaded.complete();
    _controller = null;
    _ready = Completer<void>();
    _pageLoaded = Completer<void>();
    _pageError = null;
  }

  Future<void> waitUntilReady({Duration timeout = const Duration(seconds: 15), bool Function()? isCancelled}) async {
    if (_controller != null) return;
    await _awaitCancellable(_ready.future.timeout(timeout), isCancelled);
    if (_controller == null) throw StateError('Browser session was closed.');
  }

  void markPageStarted() {
    _pageLoaded = Completer<void>();
    _pageError = null;
  }

  void markPageFinished(String url) {
    if (!_pageLoaded.isCompleted) _pageLoaded.complete();
  }

  void markPageError(String description) {
    _pageError = description;
    if (!_pageLoaded.isCompleted) _pageLoaded.complete();
  }

  Uri _validateUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.hasAuthority ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw ArgumentError.value(value, 'url', 'Browser URL must be an absolute HTTP(S) URL without credentials.');
    }
    final host = uri.host.toLowerCase();
    if (host == 'localhost' || host.endsWith('.local') ||
        host == '127.0.0.1' || host == '::1' ||
        host.startsWith('10.') || host.startsWith('192.168.') ||
        host.startsWith('169.254.') ||
        RegExp(r'^172\.(1[6-9]|2[0-9]|3[0-1])\.').hasMatch(host)) {
      throw ArgumentError.value(value, 'url', 'Private and loopback destinations are blocked in the agent browser.');
    }
    return uri;
  }

  bool allowsNavigation(String url) {
    try {
      _validateUrl(url);
      return true;
    } catch (_) {
      return false;
    }
  }

  WebViewController _requireController() {
    final controller = _controller;
    if (controller == null) throw StateError('Open the visible agent browser before using browser tools.');
    return controller;
  }

  Future<Map<String, dynamic>> visit(String url, {bool Function()? isCancelled}) async {
    _checkCancelled(isCancelled);
    final uri = _validateUrl(url);
    final controller = _requireController();
    markPageStarted();
    await _awaitCancellable(controller.loadRequest(uri), isCancelled);
    _checkCancelled(isCancelled);
    try {
      await _awaitCancellable(_pageLoaded.future.timeout(const Duration(seconds: 30)), isCancelled);
    } on TimeoutException {
      return <String, dynamic>{
        'ok': false,
        'url': uri.toString(),
        'error': 'Page load timed out after 30 seconds.',
      };
    }
    if (_pageError != null) {
      return <String, dynamic>{
        'ok': false,
        'url': uri.toString(),
        'error': _pageError,
      };
    }
    _checkCancelled(isCancelled);
    return state(isCancelled: isCancelled);
  }

  Future<Map<String, dynamic>> state({bool Function()? isCancelled}) async {
    final controller = _requireController();
    _checkCancelled(isCancelled);
    final raw = await _awaitCancellable(controller.runJavaScriptReturningResult(
      'JSON.stringify({url:location.href,title:document.title,text:(document.body?document.body.innerText:" ").slice(0,10000)})',
    ), isCancelled);
    _checkCancelled(isCancelled);
    final decoded = _decode(raw);
    if (decoded is! Map) throw const FormatException('Browser state returned an invalid payload.');
    return <String, dynamic>{
      'ok': true,
      'url': decoded['url']?.toString() ?? '',
      'title': decoded['title']?.toString() ?? '',
      'text': decoded['text']?.toString() ?? '',
    };
  }

  Future<Map<String, dynamic>> find(String query, {bool Function()? isCancelled}) async {
    final value = query.trim();
    if (value.isEmpty || value.length > 300) throw ArgumentError('Browser find query must contain 1–300 characters.');
    _checkCancelled(isCancelled);
    final controller = _requireController();
    final encoded = jsonEncode(value);
    final raw = await _awaitCancellable(controller.runJavaScriptReturningResult('''(() => {
      const q=$encoded;
      const text=(document.body?.innerText||'');
      const index=text.toLocaleLowerCase().indexOf(q.toLocaleLowerCase());
      return JSON.stringify({ok:true,query:q,found:index>=0,index,snippet:index<0?'':text.slice(Math.max(0,index-180),Math.min(text.length,index+q.length+300))});
    })()'''), isCancelled);
    _checkCancelled(isCancelled);
    final decoded = _decode(raw);
    if (decoded is! Map) throw const FormatException('Browser find returned an invalid payload.');
    return Map<String, dynamic>.from(decoded);
  }

  Future<Map<String, dynamic>> click(
    String visibleText, {
    bool allowSensitive = false,
    bool Function()? isCancelled,
  }) async {
    final value = visibleText.trim();
    if (value.isEmpty || value.length > 200) throw ArgumentError('Click target must contain 1–200 characters.');
    _checkCancelled(isCancelled);
    final controller = _requireController();
    final encoded = jsonEncode(value);
    final approval = allowSensitive ? 'true' : 'false';
    final raw = await _awaitCancellable(controller.runJavaScriptReturningResult('''(() => {
      const target=$encoded, allowSensitive=$approval;
      const norm=s=>(s||'').replace(/\\s+/g,' ').trim().toLocaleLowerCase();
      const nodes=[...document.querySelectorAll('a,button,[role="button"],input[type="submit"]')];
      const node=nodes.find(e=>norm(e.innerText||e.value||e.getAttribute('aria-label')||e.title)===norm(target))
        || nodes.find(e=>norm(e.innerText||e.value||e.getAttribute('aria-label')||e.title).includes(norm(target)));
      if(!node)return JSON.stringify({ok:false,error:'No visible link or button matched the requested text.'});
      const label=norm(node.innerText||node.value||node.getAttribute('aria-label')||node.title);
      const risky=/\\b(pay|purchase|buy|delete|remove|transfer|submit|confirm|order|checkout|sign out|unsubscribe)\\b/.test(label);
      const mutating=node.tagName!=='A' || node.type==='submit' || node.getAttribute('role')==='button';
      if((risky||mutating)&&!allowSensitive)
        return JSON.stringify({ok:false,requires_confirmation:true,clicked:target,tag:node.tagName});
      node.click();
      return JSON.stringify({ok:true,clicked:target,tag:node.tagName});
    })()'''), isCancelled);
    _checkCancelled(isCancelled);
    final decoded = _decode(raw);
    if (decoded is! Map) throw const FormatException('Browser click returned an invalid payload.');
    return Map<String, dynamic>.from(decoded);
  }

  Future<Map<String, dynamic>> input(
    String selector,
    String value, {
    bool allowSensitive = false,
    bool Function()? isCancelled,
  }) async {
    final cleanSelector = selector.trim();
    if (cleanSelector.isEmpty || cleanSelector.length > 300 || value.length > 4000) {
      throw ArgumentError('Input requires a CSS selector (1–300 chars) and value (max 4000 chars).');
    }
    _checkCancelled(isCancelled);
    final controller = _requireController();
    final selectorJson = jsonEncode(cleanSelector);
    final valueJson = jsonEncode(value);
    final approval = allowSensitive ? 'true' : 'false';
    final raw = await _awaitCancellable(controller.runJavaScriptReturningResult('''(() => {
      const selector=$selectorJson, value=$valueJson, allowSensitive=$approval;
      let element;
      try { element=document.querySelector(selector); } catch(e) {
        return JSON.stringify({ok:false,error:'Invalid CSS selector.'});
      }
      if(!element)return JSON.stringify({ok:false,error:'No element matched the CSS selector.'});
      if(!('value' in element))return JSON.stringify({ok:false,error:'Matched element is not an input control.'});
      const metadata=(selector+' '+(element.name||'')+' '+(element.autocomplete||'')+' '+(element.type||'')).toLowerCase();
      const sensitive=element.type==='password'||/password|card|cvv|cvc|security.?code|bank|account|token|secret/.test(metadata);
      if(sensitive&&!allowSensitive)
        return JSON.stringify({ok:false,requires_confirmation:true,selector,tag:element.tagName,type:element.type||''});
      element.focus(); element.value=value;
      element.dispatchEvent(new Event('input',{bubbles:true}));
      element.dispatchEvent(new Event('change',{bubbles:true}));
      return JSON.stringify({ok:true,selector,tag:element.tagName,type:element.type||''});
    })()'''), isCancelled);
    _checkCancelled(isCancelled);
    final decoded = _decode(raw);
    if (decoded is! Map) throw const FormatException('Browser input returned an invalid payload.');
    return Map<String, dynamic>.from(decoded);
  }

  Future<Map<String, dynamic>> scroll({required bool down, bool Function()? isCancelled}) async {
    _checkCancelled(isCancelled);
    final controller = _requireController();
    final offset = down ? '0.8' : '-0.8';
    await _awaitCancellable(controller.runJavaScript(
      'window.scrollBy({top:window.innerHeight*$offset,behavior:"smooth"})',
    ), isCancelled);
    _checkCancelled(isCancelled);
    return <String, dynamic>{'ok': true, 'direction': down ? 'down' : 'up'};
  }

  Future<List<Map<String, dynamic>>> fetchUrls(List<String> urls, {bool Function()? isCancelled}) async {
    if (urls.isEmpty || urls.length > 5) {
      throw ArgumentError('fetch_urls accepts 1–5 URLs per call.');
    }
    final results = <Map<String, dynamic>>[];
    for (final url in urls) {
      _checkCancelled(isCancelled);
      final result = await visit(url, isCancelled: isCancelled);
      results.add(result);
      if (result['ok'] != true) break;
    }
    return results;
  }

  dynamic _decode(dynamic raw) {
    if (raw is Map) return raw;
    final text = raw?.toString() ?? '';
    final decoded = jsonDecode(text);
    if (decoded is String) return jsonDecode(decoded);
    return decoded;
  }
}
