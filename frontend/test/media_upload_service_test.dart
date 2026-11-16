import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:she_m_app/data/models/user_model.dart';
import 'package:she_m_app/data/services/media_upload_service.dart';

void main() {
  test('video upload enforces the 12 MiB compressed size limit', () {
    expect(MediaUploadService.isVideoSizeAllowed(1), isTrue);
    expect(
      MediaUploadService.isVideoSizeAllowed(
        MediaUploadService.maxVideoUploadBytes,
      ),
      isTrue,
    );
    expect(
      MediaUploadService.isVideoSizeAllowed(
        MediaUploadService.maxVideoUploadBytes + 1,
      ),
      isFalse,
    );
    expect(MediaUploadService.isVideoSizeAllowed(0), isFalse);
  });

  test('MP4 validation checks the ftyp container signature', () {
    final validMp4 = Uint8List(12)
      ..setRange(4, 8, const [0x66, 0x74, 0x79, 0x70]);

    expect(MediaUploadService.hasMp4FileSignature(validMp4), isTrue);
    expect(MediaUploadService.hasMp4FileSignature(Uint8List(12)), isFalse);
    expect(MediaUploadService.hasMp4FileSignature(Uint8List(7)), isFalse);
  });

  test('video MIME type follows the selected file extension', () {
    expect(
      MediaUploadService.videoContentTypeForFileName('product.mp4'),
      'video/mp4',
    );
    expect(
      MediaUploadService.videoContentTypeForFileName('product.MOV'),
      'video/quicktime',
    );
    expect(
      MediaUploadService.videoContentTypeForFileName('product.webm'),
      'video/webm',
    );
  });

  test('video upload rejects formats the media server does not accept',
      () async {
    final uploaded = await MediaUploadService.uploadVideo(
      Uint8List(12),
      fileName: 'product.mov',
      contentType: 'video/quicktime',
    );

    expect(uploaded, isNull);
  });

  test('compact image service returns compact bytes', () async {
    final image = img.Image(width: 500, height: 300);
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        image.setPixelRgba(x, y, 120, 90, 150, 255);
      }
    }

    final bytes = Uint8List.fromList(img.encodeJpg(image, quality: 80));
    final value = await MediaUploadService.compactImageBytes(
      bytes,
      quality: 30,
    );

    expect(value, isNotNull);
    expect(value!.length, lessThan(180000));
  });

  test('user model keeps compressed profile image in base64 form', () {
    const profileImage = 'data:image/jpeg;base64,/9j/4AAQSkZJRgABAQAAAQABAAD';
    final user = UserModel(
      id: '123',
      fullName: 'Test User',
      phone: '+967700000000',
      role: 'customer',
      isVerified: true,
      profileImageData: profileImage,
      createdAt: DateTime.now(),
    );

    final json = user.toJson();
    final restored = UserModel.fromJson(json);

    expect(json['profile_image'], equals(profileImage));
    expect(restored.profileImageData, equals(profileImage));
    expect(restored.profileImageData, startsWith('data:image/'));
  });

  test('user model preserves current location in profile data', () {
    final user = UserModel(
      id: '123',
      fullName: 'Test User',
      phone: '+967700000000',
      role: 'customer',
      isVerified: true,
      currentLocation: '15.3694, 44.1910',
      createdAt: DateTime.now(),
    );

    final json = user.toJson();
    final restored = UserModel.fromJson(json);

    expect(json['current_location'], '15.3694, 44.1910');
    expect(restored.currentLocation, '15.3694, 44.1910');
  });

  test('blank profile image is normalized to null and trimmed data URIs decode',
      () {
    final blankUser = UserModel.fromJson({
      'id': '123',
      'full_name': 'Blank User',
      'phone': '+967700000000',
      'role': 'customer',
      'is_verified': true,
      'profile_image': '   ',
      'created_at': DateTime.now().toIso8601String(),
    });

    expect(blankUser.profileImageData, isNull);

    final image = img.Image(width: 80, height: 60);
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        image.setPixelRgba(x, y, 40, 60, 120, 255);
      }
    }

    final dataUri =
        'data:image/jpeg;base64,${base64Encode(img.encodeJpg(image))}';
    final decoded = MediaUploadService.decodeDataUriToBytes('  $dataUri  ');
    expect(decoded, isNotNull);
    expect(decoded, isNotEmpty);
  });

  test('copyWith can explicitly clear profile image and shop banner', () {
    final user = UserModel(
      id: '123',
      fullName: 'Test User',
      phone: '+967700000000',
      role: 'merchant',
      isVerified: true,
      profileImageData: 'data:image/jpeg;base64,abc',
      shopBannerUrl: 'data:image/jpeg;base64,xyz',
      createdAt: DateTime.now(),
    );

    final cleared = user.copyWith(
      profileImageData: null,
      shopBannerUrl: null,
    );

    expect(cleared.profileImageData, isNull);
    expect(cleared.shopBannerUrl, isNull);
  });

  test('compact image keeps a reasonable size for display quality', () async {
    final image = img.Image(width: 1200, height: 900);
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        image.setPixelRgba(x, y, 30 + (x % 200), 80 + (y % 150), 150, 255);
      }
    }

    final compressed = await MediaUploadService.compactImageBytes(
      Uint8List.fromList(img.encodeJpg(image, quality: 85)),
      targetSizeBytes: 180000,
      quality: 62,
      maxWidth: 1200,
      maxHeight: 900,
    );

    expect(compressed, isNotNull);
    expect(compressed!.length, lessThan(180000));

    final resized = img.decodeImage(compressed);
    expect(resized, isNotNull);
    expect(resized!.width, greaterThan(200));
    expect(resized.height, greaterThan(150));
  });
}
