import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/browser_session_service.dart';

class AgentBrowserDialog extends StatefulWidget {
  const AgentBrowserDialog({super.key});

  @override
  State<AgentBrowserDialog> createState() => _AgentBrowserDialogState();
}

class _AgentBrowserDialogState extends State<AgentBrowserDialog> {
  final BrowserSessionService _browser = BrowserSessionService.instance;
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) => _browser.allowsNavigation(request.url)
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
          onPageStarted: (_) => _browser.markPageStarted(),
          onPageFinished: _browser.markPageFinished,
          onWebResourceError: (error) {
            if (error.isForMainFrame == true) {
              _browser.markPageError(error.description);
            }
          },
        ),
      );
    _browser.attach(_controller);
  }

  @override
  void dispose() {
    _browser.detach(_controller);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: SizedBox(
        width: size.width > 1000 ? 1000 : size.width - 24,
        height: size.height > 760 ? 720 : size.height - 48,
        child: Column(
          children: [
            Container(
              height: 54,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(
                color: Color(0xFF111827),
                borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.public, color: Color(0xFF5EEAD4)),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'متصفح الوكيل — جلسة مرئية',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    tooltip: 'إغلاق المتصفح',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(child: WebViewWidget(controller: _controller)),
          ],
        ),
      ),
    );
  }
}
