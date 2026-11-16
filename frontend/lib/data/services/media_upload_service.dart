import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image/image.dart' as img;
import 'package:she_m_app/core/constants/app_constants.dart';
import 'package:she_m_app/core/errors/app_error.dart';

class MediaUploadService {
  static const int maxVideoUploadBytes = 12 * 1024 * 1024;
  static const int _maxWidth = 1200;
  static const int _maxHeight = 900;
  static const int _targetSizeBytes = 180000;
  static const int _minQuality = 28;

  static bool isDataUri(String? value) {
    return value != null && value.trim().startsWith('data:image');
  }

  static String normalizePublicImageUrl(String value) {
    final normalized = value.trim();
    final match = RegExp(
      r'^https?://github\.com/([^/]+/[^/]+)/blob/([^/]+)/(.*)$',
    ).firstMatch(normalized);
    if (match == null) return normalized;

    final repository = match.group(1)!;
    final branch = Uri.encodeComponent(match.group(2)!);
    final path = match.group(3)!.split('/').map(Uri.encodeComponent).join('/');
    return 'https://raw.githubusercontent.com/$repository/$branch/$path';
  }

  static Future<String?> uploadImage(
    Uint8List imageBytes, {
    required String fileName,
    String contentType = 'image/jpeg',
    String mediaType = 'products',
  }) =>
      _uploadMedia(
        imageBytes,
        fileName: fileName,
        contentType: contentType,
        mediaType: mediaType,
      );

  static bool isVideoSizeAllowed(int sizeInBytes) =>
      sizeInBytes > 0 && sizeInBytes <= maxVideoUploadBytes;

  static bool hasMp4FileSignature(Uint8List bytes) =>
      bytes.length >= 8 &&
      bytes[4] == 0x66 &&
      bytes[5] == 0x74 &&
      bytes[6] == 0x79 &&
      bytes[7] == 0x70;

  static String videoContentTypeForFileName(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    return switch (extension) {
      'mov' => 'video/quicktime',
      'webm' => 'video/webm',
      'mkv' => 'video/x-matroska',
      _ => 'video/mp4',
    };
  }

  static Future<String?> uploadVideo(
    Uint8List videoBytes, {
    required String fileName,
    String contentType = 'video/mp4',
  }) {
    if (!isVideoSizeAllowed(videoBytes.length) ||
        contentType.toLowerCase() != 'video/mp4' ||
        !fileName.toLowerCase().endsWith('.mp4') ||
        !hasMp4FileSignature(videoBytes)) {
      return Future.value(null);
    }

    return _uploadMedia(
      videoBytes,
      fileName: fileName,
      contentType: contentType,
      mediaType: 'products',
    );
  }

  static Future<String?> _uploadMedia(
    Uint8List mediaBytes, {
    required String fileName,
    required String contentType,
    required String mediaType,
  }) async {
    final baseUrl = AppConstants.mediaApiBaseUrl.trim();
    if (baseUrl.isEmpty) {
      AppErrorReporter.report(
        const AppException(
          'خدمة رفع الملفات غير مهيأة.',
          kind: AppErrorKind.server,
        ),
      );
      return null;
    }

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl${AppConstants.mediaEndpoint}/upload'),
      )..files.add(http.MultipartFile.fromBytes(
          'file',
          mediaBytes,
          filename: fileName,
          contentType: MediaType.parse(contentType),
        ));
      request.fields['media_type'] = mediaType;
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        AppErrorReporter.report(
          const AppException(
            'يرجى تسجيل الدخول مجددًا قبل رفع الملفات.',
            kind: AppErrorKind.access,
          ),
        );
        return null;
      }
      final idToken = await currentUser.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        AppErrorReporter.report(
          const AppException(
            'تعذر التحقق من جلسة المستخدم لرفع الملفات.',
            kind: AppErrorKind.access,
          ),
        );
        return null;
      }
      request.headers['Authorization'] = 'Bearer $idToken';

      final response = await request.send().timeout(
            const Duration(seconds: 60),
          );
      final body = await response.stream
          .bytesToString()
          .timeout(const Duration(seconds: 60));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final requiresSignIn =
            response.statusCode == 401 || response.statusCode == 403;
        AppErrorReporter.report(
          AppException(
            requiresSignIn
                ? 'انتهت جلسة التحقق. سجّل الدخول مرة أخرى لرفع الملفات.'
                : AppErrorMessage.server,
            kind: requiresSignIn ? AppErrorKind.access : AppErrorKind.server,
            statusCode: response.statusCode,
          ),
        );
        return null;
      }

      final json = jsonDecode(body);
      final url = json is Map ? json['url']?.toString().trim() : null;
      if (url == null || url.isEmpty) {
        AppErrorReporter.report(
          const AppException(
            AppErrorMessage.invalidData,
            kind: AppErrorKind.invalidData,
          ),
        );
        return null;
      }
      return url;
    } on SocketException catch (error) {
      AppErrorReporter.report(error);
      return null;
    } on http.ClientException catch (error) {
      AppErrorReporter.report(error);
      return null;
    } on TimeoutException catch (error) {
      AppErrorReporter.report(error);
      return null;
    } on FormatException catch (error) {
      AppErrorReporter.report(error);
      return null;
    } catch (error) {
      AppErrorReporter.report(error);
      return null;
    }
  }

  static Future<Uint8List?> compactImageBytes(
    Uint8List imageBytes, {
    int maxWidth = _maxWidth,
    int maxHeight = _maxHeight,
    int targetSizeBytes = _targetSizeBytes,
    int quality = 62,
  }) async {
    try {
      final decoded = img.decodeImage(imageBytes);
      if (decoded == null) return null;

      img.Image resized = decoded;
      if (decoded.width > maxWidth || decoded.height > maxHeight) {
        resized = img.copyResize(
          decoded,
          width: decoded.width > maxWidth ? maxWidth : decoded.width,
          height: decoded.height > maxHeight ? maxHeight : decoded.height,
        );
      }

      Uint8List compressed = img.encodeJpg(resized, quality: quality);
      int bestQuality = quality;

      for (int pass = 0; pass < 7; pass++) {
        final nextQuality = (bestQuality - 10).clamp(_minQuality, 90);
        final candidate = img.encodeJpg(resized, quality: nextQuality);
        if (candidate.length <= targetSizeBytes) {
          compressed = candidate;
          break;
        }
        if (candidate.length < compressed.length) compressed = candidate;
        if (nextQuality <= _minQuality) break;
        bestQuality = nextQuality;
      }

      while (compressed.length > targetSizeBytes &&
          (resized.width > 64 || resized.height > 64)) {
        final nextWidth =
            (resized.width * 0.75).round().clamp(64, resized.width);
        final nextHeight =
            (resized.height * 0.75).round().clamp(64, resized.height);
        resized = img.copyResize(resized, width: nextWidth, height: nextHeight);
        compressed = img.encodeJpg(resized, quality: 22);
      }

      return compressed;
    } catch (_) {
      return null;
    }
  }

  static ImageProvider<Object>? imageProvider(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) return null;

    if (isDataUri(normalized)) {
      final bytes = decodeDataUriToBytes(normalized);
      if (bytes != null) return MemoryImage(bytes);
      return null;
    }

    return CachedNetworkImageProvider(normalizePublicImageUrl(normalized));
  }

  static Uint8List? decodeDataUriToBytes(String? value) {
    final normalized = value?.trim();
    if (normalized == null ||
        normalized.isEmpty ||
        !normalized.startsWith('data:')) {
      return null;
    }

    final commaIndex = normalized.indexOf(',');
    if (commaIndex < 0) return null;

    final metadata = normalized.substring(0, commaIndex).toLowerCase();
    if (!metadata.contains('base64') && !metadata.contains('image/')) {
      return null;
    }

    final encodedRaw = normalized.substring(commaIndex + 1).trim();
    if (encodedRaw.isEmpty) return null;

    final encoded = encodedRaw.replaceAll(RegExp(r'\s+'), '');
    if (encoded.isEmpty) return null;

    String safeEncoded = encoded;
    while (safeEncoded.length % 4 != 0) {
      safeEncoded += '=';
    }

    try {
      return base64Decode(safeEncoded);
    } catch (_) {
      return null;
    }
  }
}
