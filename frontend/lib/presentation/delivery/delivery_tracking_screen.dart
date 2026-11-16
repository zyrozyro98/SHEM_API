import 'dart:async';

import 'package:flutter/material.dart';
import 'package:she_m_app/data/models/order_number.dart';
import 'package:she_m_app/data/services/auth_service.dart';
import 'package:she_m_app/data/services/delivery_service.dart';
import 'package:she_m_app/presentation/common/custom_appbar.dart';

class DeliveryTrackingScreen extends StatefulWidget {
  const DeliveryTrackingScreen({super.key});

  @override
  State<DeliveryTrackingScreen> createState() => _DeliveryTrackingScreenState();
}

class _DeliveryTrackingScreenState extends State<DeliveryTrackingScreen> {
  final DeliveryService _deliveryService = DeliveryService();
  final AuthService _authService = AuthService();

  String? _currentCustomerId;
  List<Map<String, dynamic>> _shipments = const [];
  bool _isLoading = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTrackingState());
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshDeliveries(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadTrackingState() async {
    setState(() => _isLoading = true);

    final sessionProfile = await _authService.loadSession();
    if (!mounted) return;
    if (sessionProfile != null && sessionProfile.id.trim().isNotEmpty) {
      setState(() => _currentCustomerId = sessionProfile.id.trim());
    } else {
      setState(() => _currentCustomerId = null);
    }

    await _refreshDeliveries();
  }

  Future<void> _refreshDeliveries() async {
    if (_isLoading && _shipments.isNotEmpty) return;
    final customerId = _currentCustomerId;
    if (customerId == null) {
      if (!mounted) return;
      setState(() {
        _shipments = const [];
        _isLoading = false;
      });
      return;
    }

    final latest = await _deliveryService.getCustomerDeliveries(customerId);
    if (!mounted) return;
    setState(() {
      _shipments = latest;
      _isLoading = false;
    });
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'preparing':
        return const Color(0xFF8B5CF6);
      case 'accepted':
        return const Color(0xFF0EA5E9);
      case 'picked_up':
        return const Color(0xFF14B8A6);
      case 'shipped':
        return const Color(0xFF10B981);
      case 'delivered':
        return const Color(0xFF3B82F6);
      default:
        return const Color(0xFFF59E0B);
    }
  }

  int _statusStep(String status) {
    switch (status) {
      case 'preparing':
        return 1;
      case 'accepted':
        return 2;
      case 'picked_up':
      case 'shipped':
        return 3;
      case 'delivered':
        return 4;
      default:
        return 0;
    }
  }

  String _statusLabel(String status) => DeliveryService.statusLabel(status);

  @override
  Widget build(BuildContext context) {
    final bodyContent = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : Directionality(
            textDirection: TextDirection.rtl,
            child: RefreshIndicator(
              onRefresh: _refreshDeliveries,
              color: const Color(0xFF0EA5E9),
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF8F3DF), Color(0xFFFFFFFF)],
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFFE7DCC3)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'تتبع الطلبات',
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _shipments.isEmpty
                                    ? 'لا توجد طلبات نشطة حالياً'
                                    : 'مراقبة ${_shipments.length} طلبية حاليًا',
                                style:
                                    const TextStyle(color: Color(0xFF6B7280)),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFFD4AF37).withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.route_rounded,
                            color: Color(0xFFD4AF37),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (_shipments.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: const Color(0xFF0EA5E9)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(Icons.delivery_dining_rounded,
                                color: Color(0xFF0EA5E9)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${_shipments.first['courier']} • ${_statusLabel(_shipments.first['status']?.toString() ?? '')}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_shipments.length > 1) ...[
                    const SizedBox(height: 12),
                    Text(
                      'آخر تحديثات الطلبات',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ],
                  if (_shipments.isEmpty) ...[
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.inventory_2_outlined,
                              size: 42, color: Color(0xFF8B5CF6)),
                          SizedBox(height: 12),
                          Text(
                            'لا توجد طلبات قيد التوصيل حاليًا',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'ستظهر هنا الطلبات الفعلية عند بدء تجهيزها أو تسليمها.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Color(0xFF6B7280)),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 18),
                    ..._shipments.map((shipment) {
                      final status = _statusLabel(
                          shipment['status']?.toString() ?? 'preparing');
                      final eta = shipment['eta']?.toString() ?? 'قريبا';
                      final courier = shipment['courier']?.toString() ?? 'سائق';
                      final color = _statusColor(
                          shipment['status']?.toString() ?? 'preparing');

                      return _ShipmentCard(
                        orderId: OrderNumber.fromOrder(shipment),
                        status: status,
                        eta: eta,
                        courier: courier,
                        color: color,
                        progress: _statusStep(
                          shipment['status']?.toString() ?? 'preparing',
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          );

    return Scaffold(
      appBar: const CustomAppBar(
        title: 'تتبع الطلبات',
        icon: Icons.local_shipping_rounded,
      ),
      body: bodyContent,
    );
  }
}

class _ShipmentCard extends StatelessWidget {
  final String orderId;
  final String status;
  final String eta;
  final String courier;
  final Color color;
  final int progress;

  const _ShipmentCard({
    required this.orderId,
    required this.status,
    required this.eta,
    required this.courier,
    required this.color,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'الطلب #$orderId',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  status,
                  style: TextStyle(color: color, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _DeliveryProgress(progress: progress, color: color),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.location_on_outlined, color: Color(0xFF64748B)),
              const SizedBox(width: 6),
              Expanded(child: Text('التوصيل: $courier')),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.access_time_rounded, color: Color(0xFF64748B)),
              const SizedBox(width: 6),
              Expanded(child: Text('التقدير: $eta')),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeliveryProgress extends StatelessWidget {
  const _DeliveryProgress({required this.progress, required this.color});

  final int progress;
  final Color color;

  static const _steps = [
    ('تجهيز', Icons.inventory_2_outlined),
    ('قبول', Icons.check_circle_outline_rounded),
    ('استلام', Icons.storefront_outlined),
    ('تسليم', Icons.home_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(_steps.length, (index) {
        final active = progress >= index + 1;
        final isLast = index == _steps.length - 1;
        return Expanded(
          child: Row(
            children: [
              Column(
                children: [
                  Icon(
                    _steps[index].$2,
                    size: 20,
                    color: active ? color : const Color(0xFFCBD5E1),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _steps[index].$1,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                      color: active ? color : const Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    color:
                        progress > index + 1 ? color : const Color(0xFFE2E8F0),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }
}
