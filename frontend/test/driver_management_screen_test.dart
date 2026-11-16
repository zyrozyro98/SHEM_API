import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/data/services/admin_service.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';
import 'package:she_m_app/presentation/admin/admin_management_detail_screens.dart';

void main() {
  testWidgets('lists, searches, filters, and updates driver availability',
      (tester) async {
    final database = _DriverDatabase({
      'driver-1': {
        'full_name': 'سائق صنعاء',
        'phone': '0500000001',
        'role': 'driver',
        'city': 'صنعاء',
        'vehicle_type': 'دراجة نارية',
        'is_available': false,
      },
      'driver-2': {
        'full_name': 'سائق إب',
        'phone': '0500000002',
        'role': 'driver',
        'city': 'إب',
        'vehicle_type': 'سيارة صغيرة',
        'is_available': true,
      },
      'customer-1': {
        'full_name': 'عميل',
        'role': 'customer',
        'is_available': true,
      },
    });

    await tester.pumpWidget(_app(database));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('سائق صنعاء'),
      240,
      scrollable: _driverListScrollable(),
    );
    expect(find.text('سائق صنعاء'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('سائق إب'),
      240,
      scrollable: _driverListScrollable(),
    );
    expect(find.text('سائق إب'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byTooltip('تغيير توفر سائق صنعاء'),
      240,
      scrollable: _driverListScrollable(),
    );
    await tester.tap(find.byTooltip('تغيير توفر سائق صنعاء'));
    await tester.pumpAndSettle();

    expect(database.profiles['driver-1']!['is_available'], isTrue);
    expect(find.text('تم تفعيل توفر السائق'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'سائق إب');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('سائق إب').last,
      240,
      scrollable: _driverListScrollable(),
    );
    expect(find.text('سائق إب').last, findsOneWidget);
    expect(find.text('سائق صنعاء'), findsNothing);
  });

  testWidgets('shows a recoverable error when driver data cannot load',
      (tester) async {
    await tester.pumpWidget(_app(_DriverDatabase({}, failReads: true)));
    await tester.pumpAndSettle();

    expect(find.text('تعذر تحميل بيانات السائقين'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
  });
}

Widget _app(_DriverDatabase database) {
  return MaterialApp(
    home: DriverManagementScreen(
      service: AdminService(databaseService: database),
    ),
  );
}

Finder _driverListScrollable() {
  return find
      .descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      )
      .first;
}

class _DriverDatabase implements DatabaseService {
  _DriverDatabase(this.profiles, {this.failReads = false});

  final Map<String, Map<String, dynamic>> profiles;
  final bool failReads;

  @override
  Future<Map<String, dynamic>> read(String path) async {
    if (failReads) throw StateError('تعذر الاتصال بقاعدة البيانات');
    if (path == 'profiles') return profiles;
    return <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> write(
    String path,
    Map<String, dynamic> data,
  ) async =>
      data;

  @override
  Future<Map<String, dynamic>> update(
    String path,
    Map<String, dynamic> data,
  ) async {
    final id = path.substring('profiles/'.length);
    profiles[id] = {...profiles[id]!, ...data};
    return profiles[id]!;
  }

  @override
  Future<Map<String, dynamic>?> updateIf(
    String path, {
    required bool Function(Map<String, dynamic> current) condition,
    required Map<String, dynamic> updates,
  }) async =>
      updates;

  @override
  Future<void> delete(String path) async {}
}
