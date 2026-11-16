import 'package:flutter/material.dart';
import 'package:she_m_app/core/errors/app_error.dart';
import 'package:she_m_app/data/models/order_number.dart';
import 'package:she_m_app/data/services/admin_service.dart';
import 'package:she_m_app/data/services/currency_service.dart';

class DispatcherPerformanceReportScreen extends StatefulWidget {
  const DispatcherPerformanceReportScreen({super.key});

  @override
  State<DispatcherPerformanceReportScreen> createState() =>
      _DispatcherPerformanceReportScreenState();
}

class _DispatcherPerformanceReportScreenState
    extends State<DispatcherPerformanceReportScreen> {
  final AdminService _service = AdminService();
  late final Future<List<Map<String, dynamic>>> _profilesFuture;
  late Future<DispatcherPerformanceReport> _reportFuture;
  String? _selectedDispatcherId;
  DispatcherReportPeriod _period = DispatcherReportPeriod.daily;

  @override
  void initState() {
    super.initState();
    _profilesFuture = _loadDispatchers();
  }

  Future<List<Map<String, dynamic>>> _loadDispatchers() async {
    final profiles = await _service.getProfilesForAdmin(
      role: 'central_dispatcher',
      limit: 200,
    );
    if (profiles.isNotEmpty) {
      _selectedDispatcherId = profiles.first['id']?.toString();
      _reportFuture = _loadReport(_selectedDispatcherId!);
    }
    return profiles;
  }

  Future<DispatcherPerformanceReport> _loadReport(String dispatcherId) {
    return _service.getDispatcherPerformanceReport(
      dispatcherId: dispatcherId,
      period: _period,
    );
  }

  String _periodLabel(DispatcherReportPeriod period) => switch (period) {
        DispatcherReportPeriod.daily => 'يومي',
        DispatcherReportPeriod.monthly => 'شهري',
        DispatcherReportPeriod.yearly => 'سنوي',
      };

  String _statusLabel(Object? status) => switch (status?.toString()) {
        'delivered' => 'تم التوصيل',
        'cancelled' => 'ملغي',
        'rejected' => 'مرفوض',
        'picked_up' => 'تم تسليم الطلب للسائق',
        'shipped' => 'جاهز للاستلام من المتجر',
        'preparing' => 'قيد التجهيز',
        'confirmed' => 'مؤكد',
        'accepted' => 'مقبول',
        _ => status?.toString() ?? 'غير محدد',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تقارير مسؤولي التوصيل')),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _profilesFuture,
          builder: (context, profilesSnapshot) {
            if (profilesSnapshot.hasError) {
              return _ReportError(
                message: AppErrorMessage.from(profilesSnapshot.error!),
              );
            }
            if (!profilesSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final profiles = profilesSnapshot.data!;
            if (profiles.isEmpty) {
              return const Center(
                child: Text('لا يوجد مسؤول توصيل مركزي مضاف إلى النظام'),
              );
            }
            final selectedId =
                _selectedDispatcherId ?? profiles.first['id']?.toString();
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedId,
                  decoration: const InputDecoration(
                    labelText: 'مسؤول التوصيل',
                    border: OutlineInputBorder(),
                  ),
                  items: profiles
                      .map(
                        (profile) => DropdownMenuItem(
                          value: profile['id']?.toString(),
                          child: Text(
                            '${profile['full_name'] ?? 'مسؤول'} • ${profile['phone'] ?? ''}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (id) {
                    if (id == null) return;
                    setState(() {
                      _selectedDispatcherId = id;
                      _reportFuture = _loadReport(id);
                    });
                  },
                ),
                const SizedBox(height: 12),
                SegmentedButton<DispatcherReportPeriod>(
                  segments: DispatcherReportPeriod.values
                      .map(
                        (period) => ButtonSegment(
                          value: period,
                          label: Text(_periodLabel(period)),
                        ),
                      )
                      .toList(),
                  selected: {_period},
                  onSelectionChanged: (selection) {
                    final period = selection.first;
                    final id = _selectedDispatcherId ?? selectedId;
                    if (id == null) return;
                    setState(() {
                      _period = period;
                      _reportFuture = _loadReport(id);
                    });
                  },
                ),
                const SizedBox(height: 12),
                FutureBuilder<DispatcherPerformanceReport>(
                  future: _reportFuture,
                  builder: (context, reportSnapshot) {
                    if (reportSnapshot.hasError) {
                      return _ReportError(
                        message: AppErrorMessage.from(reportSnapshot.error!),
                      );
                    }
                    if (!reportSnapshot.hasData) {
                      return const Padding(
                        padding: EdgeInsets.all(30),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    return _buildReport(reportSnapshot.data!);
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildReport(DispatcherPerformanceReport report) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ReportMetric(
                label: 'الطلبات المسندة', value: report.totalAssigned),
            _ReportMetric(label: 'تم توصيلها', value: report.delivered),
            _ReportMetric(label: 'قيد التنفيذ', value: report.inProgress),
            _ReportMetric(label: 'ملغاة', value: report.cancelled),
          ],
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: const Text('إجمالي قيمة الطلبات المسندة'),
            trailing: Text(
              '${report.totalOrderValue.toStringAsFixed(0)} '
              '${CurrencyService.yerCurrency.symbol}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
        if (report.unconvertedOrderCount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'تعذّر تحويل قيمة ${report.unconvertedOrderCount} طلب إلى الريال اليمني. '
              'أدخل أسعار صرف العملات الناقصة من إدارة العملات.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 10),
        Text(
          'تفاصيل الطلبات (${report.orders.length})',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        if (report.orders.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('لا توجد طلبات مسندة خلال الفترة المحددة'),
            ),
          )
        else
          ...report.orders.map((order) {
            final assignedAt = DateTime.tryParse(
              order['dispatcher_assigned_at']?.toString() ?? '',
            );
            final date = assignedAt == null
                ? 'غير محدد'
                : '${assignedAt.day}/${assignedAt.month}/${assignedAt.year} '
                    '${assignedAt.hour.toString().padLeft(2, '0')}:'
                    '${assignedAt.minute.toString().padLeft(2, '0')}';
            return Card(
              child: ExpansionTile(
                leading: const Icon(Icons.local_shipping_outlined),
                title: Text('الطلب #${OrderNumber.fromOrder(order)}'),
                subtitle: Text(
                  '${_statusLabel(order['status'])} • $date',
                ),
                childrenPadding:
                    const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 14),
                children: [
                  _detailLine(
                      'السائق', order['courier_name'] ?? order['driver_name']),
                  _detailLine('رقم السائق', order['driver_phone']),
                  _detailLine(
                    'قيمة الطلب',
                    order['report_total_yer'] == null
                        ? 'تعذّر التحويل (سعر الصرف غير محدد)'
                        : '${(order['report_total_yer'] as num).toStringAsFixed(0)} '
                            '${CurrencyService.yerCurrency.symbol}',
                  ),
                  _detailLine(
                    'عنوان التسليم',
                    order['delivery_address'] ?? order['address'],
                  ),
                  _detailLine('حالة السائق', order['driver_status']),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _detailLine(String label, Object? value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
                child: Text(value?.toString().trim().isNotEmpty == true
                    ? value.toString()
                    : 'غير متوفر')),
          ],
        ),
      );
}

class _ReportMetric extends StatelessWidget {
  final String label;
  final int value;

  const _ReportMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: (MediaQuery.sizeOf(context).width - 48) / 2,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value.toString(),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(label),
              ],
            ),
          ),
        ),
      );
}

class _ReportError extends StatelessWidget {
  final String message;

  const _ReportError({required this.message});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'تعذر تحميل التقرير: $message',
          textAlign: TextAlign.center,
        ),
      );
}
