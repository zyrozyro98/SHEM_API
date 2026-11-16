import 'dart:io';

import 'package:she_m_app/core/errors/app_error.dart';

class StorageService {
  Future<String> uploadPaymentProof({
    required File file,
    required String orderId,
  }) async {
    const error = AppException(
      'رفع إيصالات الدفع غير مهيأ في التطبيق.',
      kind: AppErrorKind.server,
    );
    AppErrorReporter.report(error);
    throw error;
  }
}
