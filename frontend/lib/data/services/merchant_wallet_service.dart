import 'package:she_m_app/data/services/firebase_database_service.dart';
import 'package:she_m_app/data/services/currency_service.dart';
import 'package:she_m_app/data/services/merchant_order_accounting.dart';

class MerchantWalletSnapshot {
  final String merchantId;
  final double pendingSales;
  final double availableBalance;
  final double pendingWithdrawals;
  final double totalSales;
  final int pendingOrders;
  final int releasableOrders;
  final String currencySymbol;
  final int unconvertedOrderCount;

  const MerchantWalletSnapshot({
    required this.merchantId,
    required this.pendingSales,
    required this.availableBalance,
    required this.pendingWithdrawals,
    required this.totalSales,
    required this.pendingOrders,
    required this.releasableOrders,
    required this.currencySymbol,
    this.unconvertedOrderCount = 0,
  });

  const MerchantWalletSnapshot.empty(String merchantId)
      : this(
          merchantId: merchantId,
          pendingSales: 0,
          availableBalance: 0,
          pendingWithdrawals: 0,
          totalSales: 0,
          pendingOrders: 0,
          releasableOrders: 0,
          currencySymbol: 'ر.ي',
          unconvertedOrderCount: 0,
        );

  double get withdrawableBalance =>
      (availableBalance - pendingWithdrawals).clamp(0, double.infinity);
}

class MerchantWithdrawalRequest {
  final String id;
  final String merchantId;
  final double amount;
  final String currencySymbol;
  final String status;
  final String accountName;
  final String accountNumber;
  final String? note;
  final DateTime createdAt;

  const MerchantWithdrawalRequest({
    required this.id,
    required this.merchantId,
    required this.amount,
    required this.currencySymbol,
    required this.status,
    required this.accountName,
    required this.accountNumber,
    required this.note,
    required this.createdAt,
  });

  factory MerchantWithdrawalRequest.fromJson(Map<String, dynamic> json) {
    final rawAmount = json['amount'];
    return MerchantWithdrawalRequest(
      id: json['id']?.toString() ?? '',
      merchantId: json['merchant_id']?.toString() ?? '',
      amount: rawAmount is num
          ? rawAmount.toDouble()
          : double.tryParse(rawAmount?.toString() ?? '') ?? 0,
      currencySymbol: json['currency_symbol']?.toString() ?? 'ر.س',
      status: json['status']?.toString() ?? 'pending',
      accountName: json['account_name']?.toString() ?? '',
      accountNumber: json['account_number']?.toString() ?? '',
      note: json['note']?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'merchant_id': merchantId,
        'amount': amount,
        'currency_symbol': currencySymbol,
        'status': status,
        'account_name': accountName,
        'account_number': accountNumber,
        'note': note,
        'created_at': createdAt.toUtc().toIso8601String(),
      };
}

class MerchantWalletService {
  MerchantWalletService({DatabaseService? database})
      : _database = database ?? FirebaseDatabaseService.instance;

  static const releasePeriod = Duration(days: 3);
  final DatabaseService _database;

  Future<MerchantWalletSnapshot> load(String merchantId) async {
    final normalizedId = merchantId.trim();
    if (normalizedId.isEmpty) return const MerchantWalletSnapshot.empty('');

    final results = await Future.wait([
      _database.read('orders'),
      _database.read('merchant_withdrawals/$normalizedId'),
      _database.read('products'),
    ]);
    final orders = results[0].values.whereType<Map>();
    final withdrawals = results[1]
        .values
        .whereType<Map>()
        .map((value) => MerchantWithdrawalRequest.fromJson(
            Map<String, dynamic>.from(value)))
        .where((request) =>
            request.status == 'pending' ||
            request.status == 'approved' ||
            request.status == 'paid');
    final productOwners = <String, String>{};
    final merchantProductIds = <String>{};
    for (final entry in results[2].entries) {
      if (entry.value is! Map) continue;
      final product = Map<String, dynamic>.from(entry.value as Map);
      final productId = (product['id'] ?? entry.key).toString().trim();
      final ownerId = (product['merchant_id'] ?? product['merchantId'])
              ?.toString()
              .trim() ??
          '';
      if (productId.isEmpty || ownerId.isEmpty) continue;
      productOwners[productId] = ownerId;
      productOwners[entry.key.trim()] = ownerId;
      if (ownerId == normalizedId) {
        merchantProductIds
          ..add(productId)
          ..add(entry.key.trim());
      }
    }

    final currencies =
        await CurrencyService(databaseService: _database).getCurrencies();
    var pendingSales = 0.0;
    var availableBalance = 0.0;
    var totalSales = 0.0;
    var pendingOrders = 0;
    var releasableOrders = 0;
    var unconvertedOrderCount = 0;
    const currencySymbol = 'ر.ي';
    final now = DateTime.now().toUtc();
    DateTime? parseDate(Object? value) {
      if (value is num) {
        return DateTime.fromMillisecondsSinceEpoch(value.toInt()).toUtc();
      }
      return DateTime.tryParse(value?.toString() ?? '')?.toUtc();
    }

    for (final rawOrder in orders) {
      final order = Map<String, dynamic>.from(rawOrder);
      if (!MerchantOrderAccounting.countsAsSale(order)) continue;
      final rawItems = order['items'] ?? order['order_items'];
      final hasMerchantItem = rawItems is List &&
          rawItems.whereType<Map>().any((rawItem) {
            return MerchantOrderAccounting.itemBelongsToMerchant(
              Map<String, dynamic>.from(rawItem),
              merchantId: normalizedId,
              productOwners: productOwners,
              merchantProductIds: merchantProductIds,
            );
          });
      if (!hasMerchantItem) continue;

      final merchantSale = MerchantOrderAccounting.productsTotalInYER(
        order: order,
        merchantId: normalizedId,
        productOwners: productOwners,
        merchantProductIds: merchantProductIds,
        currencies: currencies,
      );
      if (merchantSale == null) {
        unconvertedOrderCount++;
        continue;
      }
      totalSales += merchantSale;

      final status = (order['status'] ?? '').toString().trim().toLowerCase();
      final deliveredAt = parseDate(
            order['delivered_at'] ?? order['deliveredAt'],
          ) ??
          parseDate(order['created_at'] ?? order['createdAt']);
      final released = status == 'delivered' &&
          deliveredAt != null &&
          !now.isBefore(deliveredAt.add(releasePeriod));
      if (released) {
        availableBalance += merchantSale;
        releasableOrders++;
      } else {
        pendingSales += merchantSale;
        pendingOrders++;
      }
    }

    final pendingWithdrawals = withdrawals.fold<double>(
      0,
      (sum, request) => sum + request.amount,
    );
    return MerchantWalletSnapshot(
      merchantId: normalizedId,
      pendingSales: pendingSales,
      availableBalance: availableBalance,
      pendingWithdrawals: pendingWithdrawals,
      totalSales: totalSales,
      pendingOrders: pendingOrders,
      releasableOrders: releasableOrders,
      currencySymbol: currencySymbol,
      unconvertedOrderCount: unconvertedOrderCount,
    );
  }

  Future<List<MerchantWithdrawalRequest>> getRequests({
    String? status,
    bool propagateErrors = false,
  }) async {
    try {
      final snapshot = await _database.read('merchant_withdrawal_requests');
      final requests = <MerchantWithdrawalRequest>[];
      for (final entry in snapshot.entries) {
        if (entry.value is! Map) continue;
        final value = Map<String, dynamic>.from(entry.value as Map);
        final request = MerchantWithdrawalRequest.fromJson(value);
        if (status == null || request.status == status) requests.add(request);
      }
      requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return requests;
    } catch (_) {
      if (propagateErrors) rethrow;
      return const [];
    }
  }

  Future<MerchantWithdrawalRequest?> requestWithdrawal({
    required String merchantId,
    required double amount,
    required String currencySymbol,
    required String accountName,
    required String accountNumber,
  }) async {
    final normalizedId = merchantId.trim();
    if (normalizedId.isEmpty ||
        !amount.isFinite ||
        amount <= 0 ||
        accountName.trim().isEmpty ||
        accountNumber.trim().isEmpty) {
      return null;
    }
    final wallet = await load(merchantId);
    if (amount <= 0 || amount > wallet.withdrawableBalance) return null;
    final id = 'withdrawal-${DateTime.now().millisecondsSinceEpoch}';
    final request = MerchantWithdrawalRequest(
      id: id,
      merchantId: merchantId,
      amount: amount,
      currencySymbol: currencySymbol,
      status: 'pending',
      accountName: accountName.trim(),
      accountNumber: accountNumber.trim(),
      note: null,
      createdAt: DateTime.now(),
    );
    await _database.write(
      'merchant_withdrawals/${merchantId.trim()}/$id',
      request.toJson(),
    );
    await _database.write('merchant_withdrawal_requests/$id', request.toJson());
    return request;
  }

  Future<bool> updateRequestStatus({
    required MerchantWithdrawalRequest request,
    required String status,
    String? note,
  }) async {
    if (!{'approved', 'rejected', 'paid'}.contains(status)) return false;
    final updated = request.toJson()
      ..['status'] = status
      ..['note'] = note;
    try {
      await _database.write(
        'merchant_withdrawals/${request.merchantId}/${request.id}',
        updated,
      );
      await _database.write(
          'merchant_withdrawal_requests/${request.id}', updated);
      return true;
    } catch (_) {
      return false;
    }
  }
}
