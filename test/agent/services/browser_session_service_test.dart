import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/services/browser_session_service.dart';

void main() {
  final browser = BrowserSessionService.instance;

  test('browser navigation accepts public HTTP(S) destinations only', () {
    expect(browser.allowsNavigation('https://example.com/path'), isTrue);
    expect(browser.allowsNavigation('http://docs.example.org'), isTrue);
    expect(browser.allowsNavigation('file:///etc/passwd'), isFalse);
    expect(browser.allowsNavigation('javascript:alert(1)'), isFalse);
    expect(browser.allowsNavigation('https://user:password@example.com'), isFalse);
    expect(browser.allowsNavigation('http://localhost:8080'), isFalse);
    expect(browser.allowsNavigation('http://127.0.0.1'), isFalse);
    expect(browser.allowsNavigation('http://192.168.1.10'), isFalse);
    expect(browser.allowsNavigation('http://172.20.0.1'), isFalse);
    expect(browser.allowsNavigation('http://169.254.10.2'), isFalse);
  });
}
