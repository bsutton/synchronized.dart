// Copyright (c) 2016, Alexandre Roux Tekartik. All rights reserved. Use of this source code

// is governed by a BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:pedantic/pedantic.dart';
import 'package:synchronized/src/basic_lock.dart';
import 'package:synchronized/src/utils.dart';
import 'package:synchronized/synchronized.dart';
import 'package:test/test.dart';

import 'lock_factory.dart';

void main() {
  lockMain(BasicLockFactory());
}

void lockMain(LockFactory lockFactory) {
  Lock newLock() => lockFactory.newLock();

  group('synchronized', () {
    test('two_locks', () async {
      var lock1 = newLock();
      var lock2 = newLock();

      bool ok;
      await lock1.synchronized(() async {
        await lock2.synchronized(() async {
          expect(lock2.locked, isTrue);
          ok = true;
        });
      });
      expect(ok, isTrue);
    });

    test('order', () async {
      Lock lock = newLock();
      List<int> list = [];
      Future future1 = lock.synchronized(() async {
        list.add(1);
      });
      Future<String> future2 = lock.synchronized(() async {
        await sleep(10);
        list.add(2);
        return "text";
      });
      Future<int> future3 = lock.synchronized(() {
        list.add(3);
        return 1234;
      });
      expect(list, [1]);
      await Future.wait([future1, future2, future3]);
      expect(await future1, isNull);
      expect(await future2, "text");
      expect(await future3, 1234);
      expect(list, [1, 2, 3]);
    });

    test('queued_value', () async {
      Lock lock = newLock();
      Future<String> value1 = lock.synchronized(() async {
        await sleep(1);
        return "value1";
      });
      expect(await lock.synchronized(() => "value2"), "value2");
      expect(await value1, "value1");
    });

    group('perf', () {
      int operationCount = 10000;

      test('$operationCount operations', () async {
        int count = operationCount;
        int j;

        Stopwatch sw = Stopwatch();
        j = 0;
        sw.start();
        for (int i = 0; i < count; i++) {
          j += i;
        }
        print(" none ${sw.elapsed}");
        expect(j, count * (count - 1) / 2);

        sw = Stopwatch();
        j = 0;
        sw.start();
        for (int i = 0; i < count; i++) {
          await () async {
            j += i;
          }();
        }
        print("await ${sw.elapsed}");
        expect(j, count * (count - 1) / 2);

        var lock = newLock();
        sw = Stopwatch();
        j = 0;
        sw.start();
        for (int i = 0; i < count; i++) {
          // ignore: unawaited_futures
          lock.synchronized(() {
            j += i;
          });
        }
        // final wait
        await lock.synchronized(() => {});
        print("syncd ${sw.elapsed}");
        expect(j, count * (count - 1) / 2);
      });
    });

    group('timeout', () {
      test('1_ms', () async {
        Lock lock = newLock();
        Completer completer = Completer();
        Future future = lock.synchronized(() async {
          await completer.future;
        });
        try {
          await lock.synchronized(null, timeout: Duration(milliseconds: 1));
          fail('should fail');
        } on TimeoutException catch (_) {}
        completer.complete();
        await future;
      });

      test('100_ms', () async {
        // var isNewTiming = await isDart2AsyncTiming();
        // hoping timint is ok...
        Lock lock = newLock();

        bool ran1 = false;
        bool ran2 = false;
        bool ran3 = false;
        bool ran4 = false;
        // hold for 5ms
        // ignore: unawaited_futures
        lock.synchronized(() async {
          await sleep(500);
        });

        try {
          await lock.synchronized(() {
            ran1 = true;
          }, timeout: Duration(milliseconds: 1));
        } on TimeoutException catch (_) {}

        try {
          await lock.synchronized(() async {
            await sleep(5000);
            ran2 = true;
          }, timeout: Duration(milliseconds: 1));
          // fail('should fail');
        } on TimeoutException catch (_) {}

        try {
          // ignore: unawaited_futures
          lock.synchronized(() {
            ran4 = true;
          }, timeout: Duration(milliseconds: 1000));
        } on TimeoutException catch (_) {}

        // waiting long enough
        await lock.synchronized(() {
          ran3 = true;
        }, timeout: Duration(milliseconds: 1000));

        expect(ran1, isFalse, reason: "ran1 should be false");
        expect(ran2, isFalse, reason: "ran2 should be false");
        expect(ran3, isTrue, reason: "ran3 should be true");
        expect(ran4, isTrue, reason: "ran4 should be true");
      });

      test('1_ms_with_error', () async {
        bool ok = false;
        bool okTimeout = false;
        try {
          Lock lock = newLock();
          Completer completer = Completer();
          unawaited(lock.synchronized(() async {
            await completer.future;
          }).catchError((e) {}));
          try {
            await lock.synchronized(null, timeout: Duration(milliseconds: 1));
            fail('should fail');
          } on TimeoutException catch (_) {}
          completer.completeError('error');
          // await future;
          // await lock.synchronized(null, timeout: Duration(milliseconds: 1000));

          // Make sure these block ran
          await lock.synchronized(() {
            ok = true;
          });
          await lock.synchronized(() {
            okTimeout = true;
          }, timeout: Duration(milliseconds: 1000));
        } catch (_) {}
        expect(ok, isTrue);
        expect(okTimeout, isTrue);
      });
    });

    group('error', () {
      test('throw', () async {
        Lock lock = newLock();
        try {
          await lock.synchronized(() {
            throw "throwing";
          });
          fail("should throw");
        } catch (e) {
          expect(e is TestFailure, isFalse);
        }

        bool ok = false;
        await lock.synchronized(() {
          ok = true;
        });
        expect(ok, isTrue);
      });

      test('queued_throw', () async {
        Lock lock = newLock();

        // delay so that it is queued
        // ignore: unawaited_futures
        lock.synchronized(() {
          return sleep(1);
        });
        try {
          await lock.synchronized(() async {
            throw "throwing";
          });
          fail("should throw");
        } catch (e) {
          expect(e is TestFailure, isFalse);
        }

        bool ok = false;
        await lock.synchronized(() {
          ok = true;
        });
        expect(ok, isTrue);
      });

      test('throw_async', () async {
        Lock lock = newLock();
        try {
          await lock.synchronized(() async {
            throw "throwing";
          });
          fail("should throw");
        } catch (e) {
          expect(e is TestFailure, isFalse);
        }
      });
    });

    group('locked_in_lock', () {
      test('two', () async {
        var lock = newLock();

        expect(lock.locked, isFalse);
        expect(lock.inLock, isFalse);
        await lock.synchronized(() async {
          expect(lock.locked, isTrue);
          expect(lock.inLock, isTrue);
        });
        expect(lock.locked, isFalse);
        expect(lock.inLock, isFalse);

        unawaited(lock.synchronized(() async {
          await sleep(1);
          expect(lock.locked, isTrue);
          expect(lock.inLock, isTrue);
        }));

        await lock.synchronized(() async {
          await sleep(1);
          expect(lock.locked, isTrue);
          expect(lock.inLock, isTrue);
        });
        expect(lock.locked, isFalse);
        expect(lock.inLock, isFalse);
      });

      test('simple', () async {
        var lock = newLock();

        expect(lock.locked, isFalse);
        expect(lock.inLock, isFalse);
        await lock.synchronized(() async {
          expect(lock.locked, isTrue);
          expect(lock.inLock, isTrue);
        });
        expect(lock.locked, isFalse);
        expect(lock.inLock, isFalse);
      });

      test('locked', () async {
        Lock lock = newLock();
        Completer completer = Completer();
        expect(lock.locked, isFalse);
        expect(lock.inLock, isFalse);
        Future future = lock.synchronized(() async {
          await completer.future;
        });
        expect(lock.locked, isTrue);
        if (lock is BasicLock) {
          expect(lock.inLock, (lock is BasicLock) ? isTrue : isFalse);
        }
        completer.complete();
        await future;
        expect(lock.locked, isFalse);
        expect(lock.inLock, isFalse);
      });

      test('locked_with_timeout', () async {
        Lock lock = newLock();
        Completer completer = Completer();
        Future future = lock.synchronized(() async {
          await completer.future;
        });
        expect(lock.locked, isTrue);

        try {
          await lock.synchronized(null, timeout: Duration(milliseconds: 100));
          fail('should fail');
        } on TimeoutException catch (_) {}
        expect(lock.locked, isTrue);
        completer.complete();
        await future;
        expect(lock.locked, isFalse);
      });
    });
  });
}
