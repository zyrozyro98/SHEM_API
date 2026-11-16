import 'package:flutter/material.dart';
import 'package:she_m_app/presentation/admin/merchant_management_screen.dart';
import 'package:she_m_app/core/animations/route_transitions.dart';
import 'package:she_m_app/core/responsive.dart';

class MultiRoleDashboardScreen extends StatelessWidget {
  const MultiRoleDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('لوحات التحكم المتعددة'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'العملاء'),
              Tab(text: 'التجار'),
              Tab(text: 'الإدارة'),
              Tab(text: 'التطوير'),
            ],
          ),
        ),
        body: Directionality(
          textDirection: TextDirection.rtl,
          child: TabBarView(
            children: [
              _buildCustomerTab(),
              _buildMerchantTab(),
              _buildAdminTab(),
              _buildDeveloperTab(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomerTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: const [
        _RoleSummaryCard(
          title: 'لوحة العميل',
          subtitle:
              'تصفح المنتجات، متابعة الطلبات، وتتبع التوصيل في الوقت الحقيقي.',
          accent: Color(0xFF7C3AED),
        ),
        SizedBox(height: 16),
        _MetricRow(
          items: [
            _MetricTile(label: 'الطلبات', value: '24'),
            _MetricTile(label: 'العروض', value: '8'),
            _MetricTile(label: 'المفضلة', value: '15'),
          ],
        ),
        SizedBox(height: 16),
        _InfoPanel(
          title: 'أحدث الطلبات',
          lines: [
            'طلب #1042 - قيد التجهيز',
            'طلب #1078 - في الطريق',
            'طلب #1100 - تم التوصيل',
          ],
        ),
      ],
    );
  }

  Widget _buildMerchantTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: const [
        _RoleSummaryCard(
          title: 'لوحة التاجر',
          subtitle:
              'إدارة المنتجات، الطلبات، المبيعات، والعروض الترويجية بسهولة.',
          accent: Color(0xFF10B981),
        ),
        SizedBox(height: 16),
        _MetricRow(
          items: [
            _MetricTile(label: 'المبيعات', value: '4.2K'),
            _MetricTile(label: 'المنتجات', value: '140'),
            _MetricTile(label: 'التقييم', value: '4.9'),
          ],
        ),
        SizedBox(height: 16),
        _InfoPanel(
          title: 'إدارة المتجر',
          lines: [
            'إضافة منتج جديد',
            'تحديث العروض الأسبوعية',
            'تنشيط شحن مجاني',
          ],
        ),
      ],
    );
  }

  Widget _buildAdminTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const _RoleSummaryCard(
          title: 'لوحة الإدارة',
          subtitle: 'مراقبة المتاجر، الطلبات، الإيرادات، والسياسات التشغيلية.',
          accent: Color(0xFF3B82F6),
        ),
        const SizedBox(height: 16),
        const _MetricRow(
          items: [
            _MetricTile(label: 'المتاجر', value: '96'),
            _MetricTile(label: 'الإيراد', value: '12.4K'),
            _MetricTile(label: 'الشكاوى', value: '12'),
          ],
        ),
        const SizedBox(height: 16),
        Builder(
          builder: (context) {
            return GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  slideFadeRoute(page: const MerchantManagementScreen()),
                );
              },
              child: const _InfoPanel(
                title: 'إجراءات فورية',
                lines: [
                  'تفعيل متجر جديد',
                  'مراجعة طلبات الاسترجاع',
                  'إعداد الخصومات الشهرية',
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildDeveloperTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: const [
        _RoleSummaryCard(
          title: 'لوحة التطوير',
          subtitle:
              'مراقبة الأداء، التكاملات، والميزة التقنية بدون خدمات مدفوعة.',
          accent: Color(0xFFF59E0B),
        ),
        SizedBox(height: 16),
        _MetricRow(
          items: [
            _MetricTile(label: 'API', value: '99.9%'),
            _MetricTile(label: 'Build', value: 'OK'),
            _MetricTile(label: 'التكاملات', value: '12'),
          ],
        ),
        SizedBox(height: 16),
        _InfoPanel(
          title: 'التقنيات المستخدمة',
          lines: [
            'Flutter + Dart',
            'الدفع عند الاستلام + المحافظ الرقمية',
            'بدون رسوم شهرية أو اشتراكات',
          ],
        ),
      ],
    );
  }
}

class _RoleSummaryCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color accent;

  const _RoleSummaryCard({
    required this.title,
    required this.subtitle,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.dashboard_rounded, color: accent),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final List<_MetricTile> items;

  const _MetricRow({required this.items});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final cols = Responsive.columnsForWidth(width,
          mobile: items.length, tablet: items.length, desktop: items.length);
      final itemWidth = (width - (8 * (cols - 1))) / cols;
      return Wrap(
        spacing: 8,
        children: items
            .map(
              (item) => SizedBox(
                width: itemWidth,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      Text(
                        item.value,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.label,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF6B7280)),
                      ),
                    ],
                  ),
                ),
              ),
            )
            .toList(),
      );
    });
  }
}

class _MetricTile {
  final String label;
  final String value;

  const _MetricTile({required this.label, required this.value});
}

class _InfoPanel extends StatelessWidget {
  final String title;
  final List<String> lines;

  const _InfoPanel({required this.title, required this.lines});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ...lines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '• $line',
                style: const TextStyle(color: Color(0xFFE5E7EB), height: 1.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
