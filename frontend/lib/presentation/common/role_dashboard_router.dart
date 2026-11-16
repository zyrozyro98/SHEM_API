import 'package:flutter/widgets.dart';
import 'package:she_m_app/presentation/admin/admin_dashboard_screen.dart';
import 'package:she_m_app/presentation/admin/admin_management_detail_screens.dart';
import 'package:she_m_app/presentation/admin/merchant_management_screen.dart';
import 'package:she_m_app/presentation/dashboard/customer_dashboard_screen.dart';
import 'package:she_m_app/presentation/delivery/central_dispatcher_dashboard_screen.dart';

Widget dashboardForRole(String role) {
  return switch (role.trim().toLowerCase()) {
    'admin' => const AdminDashboardScreen(),
    'merchant' => const MerchantManagementScreen(),
    'driver' => const DriverDashboardScreen(),
    'central_dispatcher' ||
    'manager' =>
      const CentralDispatcherDashboardScreen(),
    _ => const CustomerDashboardScreen(),
  };
}
