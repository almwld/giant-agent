import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Local document intake and analysis history.
///
/// This service intentionally handles text/code formats only. Binary office
/// documents and images must go through dedicated parsers rather than being
/// decoded as UTF-8 and misrepresented as successfully analyzed.
class FileUploadService {
  FileUploadService._();
  static final FileUploadService instance = FileUploadService._();

  static const int maxFileBytes = 8 * 1024 * 1024;
  static const int maxStoredContentChars = 100000;
  static const Set<String> supportedExtensions = {
    'txt', 'md', 'json', 'csv', 'log', 'xml', 'yaml', 'yml',
    'html', 'htm', 'css', 'js', 'ts', 'dart', 'py', 'java',
    'kt', 'kts', 'c', 'h', 'cpp', 'hpp', 'sql', 'sh',
    'gradle', 'properties', 'toml', 'ini', 'env',
  };

  Database? _database;
  Future<void>? _opening;

  Future<void> init() async {
    if (_database != null) return;
    _opening ??= _openDatabase();
    try {
      await _opening;
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  Future<void> _openDatabase() async {
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
      allowedExtensions: supportedExtensions.toList()..sort(),
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final selected = result.files.single;
    if (selected.size > maxFileBytes) {
      throw FileSystemException(
        'File exceeds the 8 MB processing limit.',
        selected.name,
      );
    }

    final path = selected.path;
    if (path == null || path.isEmpty) {
      throw FileSystemException(
        'The selected provider did not expose a local file path. '
        'Choose a file from a provider that supports local document access.',
        selected.name,
      );
    }
    return File(path);
  }

  Future<Map<String, dynamic>> processFile(File file) async {
    await init();
    if (!await file.exists()) {
      throw FileSystemException('File does not exist.', file.path);
    }
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
    if (!supportedExtensions.contains(extension)) {
      throw FormatException(
        'Unsupported file type: .${extension.isEmpty ? '(none)' : extension}. '
        'Supported text/code formats: ${supportedExtensions.toList()..sort()}.',
      );
    }

    var content = await file.readAsString(encoding: utf8);
    if (content.startsWith('\uFEFF')) content = content.substring(1);

    final lines = content.isEmpty ? const <String>[] : const LineSplitter().convert(content);
    final analysis = <String, dynamic>{
      'filename': filename,
      'extension': extension,
      'size_bytes': size,
      'characters': content.runes.length,
      'words': content.trim().isEmpty
          ? 0
          : content.trim().split(RegExp(r'\s+')).length,
      'lines': lines.length,
      'processed_at': DateTime.now().toUtc().toIso8601String(),
      'content_truncated': content.length > maxStoredContentChars,
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
      analysis.addAll(_analyzeCsv(lines));
    } else if ({
      'dart', 'py', 'java', 'kt', 'kts', 'c', 'h', 'cpp', 'hpp',
      'js', 'ts', 'html', 'htm', 'css', 'sql', 'sh',
    }.contains(extension)) {
      analysis['file_category'] = 'source_code';
      analysis['non_empty_lines'] =
          lines.where((line) => line.trim().isNotEmpty).length;
    } else {
      analysis['file_category'] = 'text_document';
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
    return {
      ...analysis,
      'id': id,
      'stored_characters': stored.length,
    };
  }

  Map<String, dynamic> _analyzeCsv(List<String> rows) {
    if (rows.isEmpty) {
      return {'file_category': 'tabular_data', 'rows': 0, 'columns': 0};
    }
    final columns = _countCsvColumns(rows.first);
    return {
      'file_category': 'tabular_data',
      'rows': rows.length,
      'columns': columns,
      'has_header': true,
      'header': _parseCsvRow(rows.first),
    };
  }

  List<String> _parseCsvRow(String row) {
    final values = <String>[];
    final field = StringBuffer();
    var quoted = false;
    for (var i = 0; i < row.length; i++) {
      final char = row[i];
      if (char == '"') {
        if (quoted && i + 1 < row.length && row[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (char == ',' && !quoted) {
        values.add(field.toString());
        field.clear();
      } else {
        field.write(char);
      }
    }
    values.add(field.toString());
    return values;
  }

  int _countCsvColumns(String row) => _parseCsvRow(row).length;

  Future<List<Map<String, dynamic>>> getHistory({int limit = 100}) async {
    await init();
    return _database!.query(
      'processed_files',
      columns: const [
        'id', 'filename', 'extension', 'size_bytes',
        'analysis_json', 'created_at',
      ],
      orderBy: 'created_at DESC',
      limit: limit.clamp(1, 500).toInt(),
    );
  }

  Future<Map<String, dynamic>?> getProcessedFile(int id) async {
    await init();
    final rows = await _database!.query(
      'processed_files',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return {
      ...row,
      'analysis': jsonDecode(row['analysis_json'] as String),
    };
  }

  Future<int> deleteProcessedFile(int id) async {
    await init();
    return _database!.delete(
      'processed_files',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearHistory() async {
    await init();
    await _database!.delete('processed_files');
  }

  Future<void> dispose() async {
    await _database?.close();
    _database = null;
    _opening = null;
  }
}
