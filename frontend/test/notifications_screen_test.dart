import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/data/models/user_model.dart';
import 'package:she_m_app/data/services/auth_service.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';
import 'package:she_m_app/data/services/notification_service.dart';
import 'package:she_m_app/presentation/support/notifications_screen.dart';

class _MemoryDatabase implements DatabaseService {
  _MemoryDatabase(this.data);

  final Map<String, dynamic> data;

  dynamic _readPath(String path) {
    dynamic value = data;
    for (final segment in path.split('/')) {
      if (value is! Map) return null;
      value = value[segment];
    }
    return value;
  }

  @override
  Future<Map<String, dynamic>> read(String path) async {
    final value = _readPath(path);
    return value is Map
        ? Map<String, dynamic>.from(value)
        : <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> write(
    String path,
    Map<String, dynamic> value,
  ) async {
    final segments = path.split('/');
    var parent = data;
    for (final segment in segments.take(segments.length - 1)) {
      final child = parent[segment];
      if (child is Map) {
        final nested = Map<String, dynamic>.from(child);
        parent[segment] = nested;
        parent = nested;
      } else {
        final nested = <String, dynamic>{};
        parent[segment] = nested;
        parent = nested;
      }
    }
    parent[segments.last] = value;
    return value;
  }

  @override
  Future<Map<String, dynamic>> update(
    String path,
    Map<String, dynamic> value,
  ) async {
    return write(path, {...await read(path), ...value});
  }

  @override
  Future<Map<String, dynamic>?> updateIf(
    String path, {
    required bool Function(Map<String, dynamic> current) condition,
    required Map<String, dynamic> updates,
  }) async {
    final current = await read(path);
    if (current.isEmpty || !condition(current)) return null;
    return update(path, updates);
  }

  @override
  Future<void> delete(String path) async {}
}

class _AdminAuthService extends AuthService {
  _AdminAuthService()
      : super(
          databaseService: _MemoryDatabase({}),
        );

  static final _profile = UserModel(
    id: 'admin-1',
    fullName: 'مدير',
    phone: '777000000',
    role: 'admin',
    isVerified: true,
    createdAt: DateTime(2026),
  );

  @override
  Future<UserModel?> loadSession() async => _profile;

  @override
  Future<UserModel?> getCurrentProfile() async => _profile;
}

class _MerchantAuthService extends AuthService {
  _MerchantAuthService()
      : super(
          databaseService: _MemoryDatabase({}),
        );

  static final _profile = UserModel(
    id: 'merchant-1',
    fullName: 'التاجر',
    phone: '777000001',
    role: 'merchant',
    isVerified: true,
    createdAt: DateTime(2026),
  );

  @override
  Future<UserModel?> loadSession() async => _profile;

  @override
  Future<UserModel?> getCurrentProfile() async => _profile;
}

void main() {
  testWidgets('admin taps a notification to open its order details',
      (tester) async {
    final database = _MemoryDatabase({
      'notifications': {
        'notification-1': {
          'profile_id': 'admin-1',
          'recipient_role': 'admin',
          'title': 'طلب جديد',
          'body': 'تم استلام طلب جديد.',
          'type': 'new_order',
          'order_id': 'order-42',
          'is_read': false,
          'created_at': DateTime.now().toIso8601String(),
        },
      },
    });
    String? openedOrderId;

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(
          authService: _AdminAuthService(),
          notificationService: NotificationService(databaseService: database),
          databaseService: database,
          onAdminOrderTap: (orderId) async {
            openedOrderId = orderId;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('طلب جديد'));
    await tester.pumpAndSettle();

    expect(openedOrderId, 'order-42');
    expect(
      (database.data['notifications'] as Map)['notification-1']['is_read'],
      isTrue,
    );
  });

  testWidgets('admin order notifications show product image and status colors',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final database = _MemoryDatabase({
      'notifications': {
        'new-order': {
          'profile_id': 'admin-1',
          'recipient_role': 'admin',
          'title': 'طلب جديد',
          'body': 'تم استلام طلب جديد.',
          'type': 'new_order',
          'status': 'new',
          'order_id': 'order-new',
          'is_read': false,
          'created_at': now.toIso8601String(),
        },
        'rejected': {
          'profile_id': 'admin-1',
          'recipient_role': 'admin',
          'title': 'تم رفض الطلب',
          'body': 'تعذر إتمام الطلب.',
          'type': 'product_rejected',
          'status': 'rejected',
          'is_read': false,
          'created_at':
              now.subtract(const Duration(hours: 1)).toIso8601String(),
        },
        'overdue': {
          'profile_id': 'admin-1',
          'recipient_role': 'admin',
          'title': 'طلب جديد متأخر',
          'body': 'الطلب بانتظار المتابعة.',
          'type': 'new_order',
          'status': 'new',
          'order_id': 'order-overdue',
          'is_read': false,
          'created_at': now.subtract(const Duration(days: 2)).toIso8601String(),
        },
        'read': {
          'profile_id': 'admin-1',
          'recipient_role': 'admin',
          'title': 'طلب مقروء',
          'body': 'تمت قراءة الطلب.',
          'type': 'new_order',
          'status': 'new',
          'order_id': 'order-read',
          'is_read': true,
          'created_at': now.subtract(const Duration(days: 3)).toIso8601String(),
        },
      },
      'orders': {
        'order-new': {
          'items': [
            {
              'image_url':
                  'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jk0YAAAAASUVORK5CYII=',
            },
          ],
        },
        'order-overdue': {
          'items': [
            {'image_url': 'https://example.com/overdue.png'},
          ],
        },
        'order-read': {
          'items': [
            {'image_url': 'https://example.com/read.png'},
          ],
        },
      },
    });

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(
          authService: _AdminAuthService(),
          notificationService: NotificationService(databaseService: database),
          databaseService: database,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('notification-product-image-order-new')),
      findsOneWidget,
    );
    expect(find.text('جديد'), findsOneWidget);
    expect(find.text('مرفوض'), findsOneWidget);
    expect(find.text('متأخر'), findsOneWidget);
    expect(find.text('مقروء'), findsOneWidget);

    final cards = tester.widgetList<Card>(find.byType(Card)).toList();
    expect(cards[0].color, const Color(0xFFECFDF5));
    expect(cards[1].color, const Color(0xFFFEF2F2));
    expect(cards[2].color, const Color(0xFFFFF7ED));
    expect(cards[3].color, const Color(0xFFF3F4F6));
  });

  testWidgets('merchant order notification shows only owned product images',
      (tester) async {
    const ownedImage =
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jk0YAAAAASUVORK5CYII=';
    const foreignImage = 'data:image/gif;base64,'
        'R0lGODlhAQABAAD/ACwAAAAAAQABAAACADs=';
    final database = _MemoryDatabase({
      'notifications': {
        'merchant-order': {
          'profile_id': 'merchant-1',
          'recipient_role': 'merchant',
          'title': 'طلب جديد لمتجرك',
          'body': 'تم استلام طلب يحتوي على منتجات متجرك.',
          'type': 'new_order',
          'status': 'new',
          'order_id': 'mixed-order',
          'is_read': false,
          'created_at': DateTime.now().toIso8601String(),
        },
      },
      'orders': {
        'mixed-order': {
          'items': [
            {
              'product_id': 'owned',
              'merchant_id': 'merchant-99',
              'image_url': ownedImage,
            },
            {
              'product_id': 'foreign',
              'merchant_id': 'merchant-1',
              'image_url': foreignImage,
            },
          ],
        },
      },
      'products': {
        'owned': {'merchant_id': 'merchant-1'},
        'foreign': {'merchant_id': 'merchant-99'},
      },
    });

    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsScreen(
          authService: _MerchantAuthService(),
          notificationService: NotificationService(databaseService: database),
          databaseService: database,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final productImage = find.byKey(
      const ValueKey('merchant-order-product-image-mixed-order-0'),
    );
    expect(productImage, findsOneWidget);
    expect(
      tester.widget<Image>(productImage).fit,
      BoxFit.cover,
    );
    expect(
      find.byKey(
        const ValueKey('merchant-order-product-image-mixed-order-1'),
      ),
      findsNothing,
    );
  });
}
