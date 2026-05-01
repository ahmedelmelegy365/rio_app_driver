// lib/services/error_formatter.dart
//
// Single source of truth for turning any thrown error from an API call into
// a driver-readable Arabic message. Use this anywhere a `catch (e)` value
// or an AsyncValue.error would otherwise be shown to the user — it prevents
// raw `DioException [...]: ...` strings, stack traces, and English-only
// framework errors from leaking into the UI.
//
// Order of precedence:
//   1. Backend `message` field on the response body (server already speaks Arabic)
//   2. Status-code defaults for common HTTP errors
//   3. Dio transport errors (timeout / no internet / cancel / cert)
//   4. Plain `Exception('message')` — strip the "Exception: " prefix
//   5. Anything else → generic fallback
//
// Keep messages short and action-oriented; they show up in tight error
// banners and snackbars.

import 'package:dio/dio.dart';

/// Returns a user-facing Arabic message for any error thrown from an API call.
String formatApiError(Object error) {
  if (error is DioException) {
    return _formatDioException(error);
  }

  // Plain `throw Exception('foo')` — strip the framework prefix so the
  // driver sees just "foo", not "Exception: foo".
  final raw = error.toString();
  if (raw.startsWith('Exception: ')) {
    return raw.substring('Exception: '.length);
  }

  return 'حدث خطأ غير متوقع، حاول مرة أخرى';
}

String _formatDioException(DioException e) {
  // 1. Backend message wins. The Laravel API consistently returns
  //    { success: false, message: "..." } in Arabic for business errors.
  final data = e.response?.data;
  if (data is Map) {
    final msg = data['message'];
    if (msg is String && msg.trim().isNotEmpty) {
      return msg;
    }
  }

  // 2. HTTP status-code defaults for when the body had no message.
  final status = e.response?.statusCode;
  if (status != null) {
    switch (status) {
      case 401:
        return 'انتهت الجلسة، سجّل الدخول من جديد';
      case 403:
        return 'لا تملك صلاحية لهذا الإجراء';
      case 404:
        return 'العنصر المطلوب غير موجود';
      case 422:
        return 'بيانات غير صحيحة';
      case 429:
        return 'محاولات كثيرة، انتظر قليلاً ثم حاول';
      case >= 500:
        return 'الخادم لا يستجيب حالياً، حاول لاحقاً';
    }
  }

  // 3. Transport-layer errors (no HTTP response came back at all).
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return 'انقطع الاتصال — تحقق من الشبكة';
    case DioExceptionType.connectionError:
      return 'تعذّر الاتصال بالخادم — تحقق من الإنترنت';
    case DioExceptionType.badCertificate:
      return 'مشكلة في شهادة الأمان';
    case DioExceptionType.cancel:
      return 'تم إلغاء الطلب';
    case DioExceptionType.unknown:
    case DioExceptionType.badResponse:
      return 'تعذّر الاتصال بالخادم';
  }
}
