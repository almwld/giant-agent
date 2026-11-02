import 'dart:convert';
import 'dart:io';

class ChatAttachment {
  const ChatAttachment({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  final String name;
  final String mimeType;
  final List<int> bytes;

  int get sizeInBytes => bytes.length;

  Map<String, Object?> toGatewayMap() => {
    'name': name,
    'mime_type': mimeType,
    'size': sizeInBytes,
    'data_base64': base64Encode(bytes),
  };

  static Future<ChatAttachment> fromFile(
    File file, {
    required String mimeType,
    int maxBytes = 20 * 1024 * 1024,
  }) async {
    final size = await file.length();
    if (size > maxBytes) {
      throw FileSystemException('Attachment exceeds the 20 MB limit', file.path);
    }
    return ChatAttachment(
      name: file.uri.pathSegments.isEmpty ? 'attachment' : file.uri.pathSegments.last,
      mimeType: mimeType,
      bytes: await file.readAsBytes(),
    );
  }
}
