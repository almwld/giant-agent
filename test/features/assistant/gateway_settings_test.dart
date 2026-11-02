import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/features/assistant/application/gateway_settings.dart';

void main() {
  String tokenWithPayload(Map<String, Object?> payload) {
    final header = base64Url.encode(utf8.encode('{"alg":"HS256","typ":"JWT"}')).replaceAll('=', '');
    final body = base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '');
    return '$header.$body.signature';
  }

  group('GatewaySettings.tokenExpiry', () {
    test('reads the numeric JWT exp claim as UTC', () {
      final expiry = GatewaySettings.tokenExpiry(tokenWithPayload({'exp': 1_900_000_000}));
      expect(expiry, DateTime.fromMillisecondsSinceEpoch(1_900_000_000_000, isUtc: true));
    });

    test('returns null for non-JWT and malformed tokens', () {
      expect(GatewaySettings.tokenExpiry('development-token'), isNull);
      expect(GatewaySettings.tokenExpiry('a.!.c'), isNull);
    });

    test('returns null when the expiry claim is missing or invalid', () {
      expect(GatewaySettings.tokenExpiry(tokenWithPayload({'sub': 'user'})), isNull);
      expect(GatewaySettings.tokenExpiry(tokenWithPayload({'exp': 'tomorrow'})), isNull);
    });
  });
}
