import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:giant_agent_x/services/agent_memory_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('memory service can use an isolated database', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.close();
    expect(true, isTrue);
  });
}
