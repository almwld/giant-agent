import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Local document intake and analysis history.
///
/// Supported text formats are TXT, MD, JSON and CSV. Binary formats are not
/// decoded as text; callers receive an explicit unsupported-format error.
class FileUploadService {
  FileUploadService._();
  static final FileUploadService instance = FileUploadService._();

  static const int maxFileBytes = 8 * 1024 * 1024;
  static const int maxStoredContentChars = 100000;
  Database? _database;

  Future<void> init() async {
    if (_database != null) return;
    final directory = await getApplicationDocumentsDirectory();
    _database = await openDatabase(
      '${directory.path}/giant_processed_files.db',
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE processed_files (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            filename TEXT NOT NULL,
            extension TEXT NOT NULL,
            size_bytes INTEGER NOT NULL,
            content TEXT NOT NULL,
            analysis_json TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX processed_files_created_at ON processed_files(created_at DESC)',
        );
      },
    );
  }

  Future<File?> pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'md', 'json', 'csv'],
      allowMultiple: false,
      withData: false,
    );
    final path = result?.files.single.path;
    return path == null ? null : File(path);
  }

  Future<Map<String, dynamic>> processFile(File file) async {
    await init();
    if (!await file.exists()) throw FileSystemException('File does not exist.', file.path);
    final size = await file.length();
    if (size > maxFileBytes) {
      throw FileSystemException('File exceeds the 8 MB processing limit.', file.path);
    }

    final filename = file.uri.pathSegments.isEmpty
        ? 'document'
        : file.uri.pathSegments.last;
    final extension = filename.contains('.')
        ? filename.split('.').last.toLowerCase()
        : '';
    if (!const {'txt', 'md', 'json', 'csv'}.contains(extension)) {
      throw FormatException('Unsupported file type: .$extension');
    }

    final content = await file.readAsString(encoding: utf8);
    final analysis = <String, dynamic>{
      'filename': filename,
      'extension': extension,
      'size_bytes': size,
      'characters': content.runes.length,
      'words': content.trim().isEmpty
          ? 0
          : content.trim().split(RegExp(r'\s+')).length,
      'lines': content.isEmpty ? 0 : '\n'.allMatches(content).length + 1,
      'processed_at': DateTime.now().toUtc().toIso8601String(),
    };

    if (extension == 'json') {
      final decoded = jsonDecode(content);
      analysis['json_type'] = decoded is Map
          ? 'object'
          : decoded is List
              ? 'array'
              : 'scalar';
      analysis['top_level_items'] =
          decoded is Map ? decoded.length : decoded is List ? decoded.length : 1;
    } else if (extension == 'csv') {
      final rows = const LineSplitter().convert(content);
      analysis['rows'] = rows.length;
      analysis['columns'] = rows.isEmpty ? 0 : _countCsvColumns(rows.first);
      analysis['has_header'] = rows.isNotEmpty;
    }

    final stored = content.length > maxStoredContentChars
        ? content.substring(0, maxStoredContentChars)
        : content;
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await _database!.insert('processed_files', {
      'filename': filename,
      'extension': extension,
      'size_bytes': size,
      'content': stored,
      'analysis_json': jsonEncode(analysis),
      'created_at': now,
    });
    return {...analysis, 'id': id, 'content_truncated': stored.length != content.length};
  }

  int _countCsvColumns(String row) {
    var columns = 1;
    var quoted = false;
    for (var i = 0; i < row.length; i++) {
      final char = row[i];
      if (char == '"') {
        if (quoted && i + 1 < row.length && row[i + 1] == '"') {
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (char == ',' && !quoted) {
        columns++;
      }
    }
    return columns;
  }

  Future<List<Map<String, dynamic>>> getHistory({int limit = 100}) async {
    await init();
    return _database!.query(
      'processed_files',
      orderBy: 'created_at DESC',
      limit: limit.clamp(1, 500),
    );
  }

  Future<void> clearHistory() async {
    await init();
    await _database!.delete('processed_files');
  }

  Future<void> dispose() async {
    await _database?.close();
    _database = null;
  }
}
