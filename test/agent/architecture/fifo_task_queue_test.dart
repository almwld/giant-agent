import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:giant_agent_x/agent/architecture/fifo_task_queue.dart';

void main() {
  group('FifoTaskQueue', () {
    test('runs three rapidly enqueued operations in FIFO order', () async {
      final queue = FifoTaskQueue();
      final order = <String>[];
      final releaseFirst = Completer<void>();

      final first = queue.enqueue(() async {
        order.add('first:start');
        await releaseFirst.future;
        order.add('first:end');
        return 'one';
      });
      final second = queue.enqueue(() async {
        order.add('second');
        return 'two';
      });
      final third = queue.enqueue(() async {
        order.add('third');
        return 'three';
      });

      expect(order, ['first:start']);
      expect(queue.pendingCount, 2);
      releaseFirst.complete();

      expect(await Future.wait([first, second, third]), ['one', 'two', 'three']);
      expect(order, ['first:start', 'first:end', 'second', 'third']);
      expect(queue.isRunning, isFalse);
      expect(queue.pendingCount, 0);
    });

    test('a failed operation does not block later queued work', () async {
      final queue = FifoTaskQueue();
      final order = <String>[];
      final failed = queue.enqueue<String>(() async {
        order.add('failed');
        throw StateError('expected test failure');
      });
      final next = queue.enqueue(() async {
        order.add('next');
        return 'continued';
      });

      await expectLater(failed, throwsA(isA<StateError>()));
      expect(await next, 'continued');
      expect(order, ['failed', 'next']);
    });
  });
}
