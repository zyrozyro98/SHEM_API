import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

enum AppErrorKind {
  network,
  timeout,
  access,
  server,
  storage,
  invalidData,
  unexpected,
}

class AppException implements Exception {
  const AppException(
    this.message, {
    required this.kind,
    this.statusCode,
  });

  final String message;
  final AppErrorKind kind;
  final int? statusCode;

  @override
  String toString() => message;
}

class AppErrorMessage {
  static const network = 'تعذر تحميل البيانات حاليًا. يرجى المحاولة مرة أخرى.';
  static const timeout = 'استغرق الاتصال وقتًا طويلًا. حاول مرة أخرى.';
  static const access = 'ليس لديك صلاحية لتنفيذ هذه العملية.';
  static const server = 'الخدمة غير متاحة مؤقتًا. حاول مرة أخرى لاحقًا.';
  static const storage = 'تعذر حفظ البيانات على هذا الجهاز.';
  static const invalidData =
      'تعذر قراءة البيانات. أعد المحاولة أو حدّث التطبيق.';
  static const unexpected = 'حدث خطأ غير متوقع. حاول مرة أخرى.';

  static String from(Object error) {
    if (error is AppException) return error.message;
    if (error is FirebaseException) {
      if (error.code.contains('network') ||
          error.code.contains('unavailable')) {
        return network;
      }
      if (error.code.contains('permission-denied') ||
          error.code.contains('unauthorized')) {
        return access;
      }
      return server;
    }
    if (error is SocketException ||
        error is http.ClientException ||
        error is HttpException) {
      return network;
    }
    if (error is TimeoutException) return timeout;
    if (error is FormatException) return invalidData;
    if (error is PlatformException || error is MissingPluginException) {
      return storage;
    }
    if (error is FileSystemException) return storage;
    if (error is StateError) return error.message.toString();
    return unexpected;
  }

  static bool isTransient(Object error) {
    if (error is AppException) {
      return error.kind == AppErrorKind.network ||
          error.kind == AppErrorKind.timeout;
    }
    if (error is FirebaseException) {
      return error.code.contains('network') ||
          error.code.contains('unavailable') ||
          error.code.contains('deadline-exceeded');
    }
    return error is SocketException ||
        error is http.ClientException ||
        error is HttpException ||
        error is TimeoutException;
  }
}

class AppErrorNotice {
  const AppErrorNotice(this.message);

  final String message;
}

class AppErrorReporter {
  AppErrorReporter._();

  static final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  static String? _lastMessage;
  static DateTime? _lastReportedAt;
  static AppErrorNotice? _pendingNotice;

  static AppErrorNotice? takePendingNotice() {
    final notice = _pendingNotice;
    _pendingNotice = null;
    return notice;
  }

  static void report(Object error) {
    if (_isUnauthenticatedAccessError(error)) {
      debugPrint('Ignoring an access notice for a signed-out user');
      return;
    }

    final message = AppErrorMessage.from(error);
    final now = DateTime.now();
    if (message == _lastMessage &&
        _lastReportedAt != null &&
        now.difference(_lastReportedAt!) < const Duration(seconds: 4)) {
      return;
    }

    _lastMessage = message;
    _lastReportedAt = now;
    debugPrint('Application operation failed: $message');
    if (AppErrorMessage.isTransient(error)) return;

    final notice = AppErrorNotice(message);
    try {
      if (scaffoldMessengerKey.currentState == null) {
        _pendingNotice = notice;
      } else {
        showNotice(notice);
      }
    } on FlutterError {
      _pendingNotice = notice;
    }
  }

  static bool _isUnauthenticatedAccessError(Object error) {
    final isAccessError = switch (error) {
      AppException(:final kind) => kind == AppErrorKind.access,
      FirebaseException(:final code) =>
        code.contains('permission-denied') || code.contains('unauthorized'),
      _ => false,
    };
    if (!isAccessError || Firebase.apps.isEmpty) return isAccessError;

    try {
      return FirebaseAuth.instance.currentUser == null;
    } on FirebaseException {
      return true;
    }
  }

  static void showNotice(AppErrorNotice notice) {
    try {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(notice.message),
            duration: const Duration(seconds: 6),
          ),
        );
      });
    } on FlutterError {
      _pendingNotice = notice;
    }
  }
}

class AppErrorListener extends StatefulWidget {
  const AppErrorListener({required this.child, super.key});

  final Widget child;

  @override
  State<AppErrorListener> createState() => _AppErrorListenerState();
}

class _AppErrorListenerState extends State<AppErrorListener> {
  @override
  void initState() {
    super.initState();
    final pendingNotice = AppErrorReporter.takePendingNotice();
    if (pendingNotice != null) AppErrorReporter.showNotice(pendingNotice);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
