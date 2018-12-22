// Copyright (c) 2016, Alexandre Roux Tekartik. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

/// This simulates the synchronized feature of Java in an async way
///
/// Create a shared [Lock] object and use it using the [Lock.synchronized]
/// method to prevent concurrent access to a shared resource.
///
/// ```dart
/// class MyClass {
///  final _lock = new Lock();
//
///  Future<void> myMethod() async {
///    await _lock.synchronized(() async {
///      step1();
///      step2();
///      step3();
///    });
///  }
/// ```
//}
library synchronized;

import 'dart:async';

import 'package:synchronized/src/synchronized_impl.dart' as impl;

export 'compat/synchronized_compat.dart';
// ignore: deprecated_member_use

/// Object providing the implicit lock.
///
/// A [Lock] can be reentrant (in this case it will use a [Zone])
///
/// non-reentrant lock is used like an aync executor with a capacity of 1
///
/// if [timeout] is not null, it will timeout after the specified duration
abstract class Lock {
  /// Creates a [Lock] object.
  ///
  /// if [reentrant], it uses [Zone] to allow inner [synchronized] calls.
  factory Lock({bool reentrant = false}) {
    if (reentrant == true) {
      return impl.ReentrantLock();
    } else {
      return impl.Lock();
    }
  }

  /// Executes [computation] when lock is available.
  ///
  /// Only one asynchronous block can run while the lock is retained.
  Future<T> synchronized<T>(FutureOr<T> computation(), {Duration timeout});

  /// returns true if the lock is currently locked.
  bool get locked;

  /// for reentrant, test whether we are currently in the synchronized section
  /// for non reentrant, it returns the [locked] status
  bool get inLock;
}
