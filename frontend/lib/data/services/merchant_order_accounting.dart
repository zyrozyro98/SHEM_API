import 'package:she_m_app/data/services/currency_service.dart';
import 'package:she_m_app/data/services/order_service.dart';

class MerchantOrderAccounting {
  static const saleStatuses = {
    'new',
    'confirmed',
    'accepted',
    'preparing',
    'shipped',
    'picked_up',
    'delivered',
  };

  static bool countsAsSale(Map<String, dynamic> order) {
    final status = (order['status'] ?? '').toString().trim().toLowerCase();
    return saleStatuses.contains(status);
  }

  static bool itemBelongsToMerchant(
    Map<String, dynamic> item, {
    required String merchantId,
    Map<String, String> productOwners = const {},
    Set<String> merchantProductIds = const {},
  }) {
    return OrderService.orderItemBelongsToMerchant(
      item: item,
      merchantId: merchantId,
      productOwners: productOwners,
      merchantProductIds: merchantProductIds,
    );
  }

  static double? productsTotalInYER({
    required Map<String, dynamic> order,
    required String merchantId,
    Map<String, String> productOwners = const {},
    Set<String> merchantProductIds = const {},
    List<CurrencyOption> currencies = const [],
  }) {
    double? amount(Object? value) {
      final parsed =
          value is num ? value.toDouble() : double.tryParse('$value');
      return parsed != null && parsed.isFinite ? parsed : null;
    }

    final rawItems = order['items'] ?? order['order_items'];
    if (rawItems is! List) return null;

    Map? firstItem;
    for (final item in rawItems) {
      if (item is Map) {
        firstItem = item;
        break;
      }
    }
    final firstItemCurrency = firstItem == null
        ? null
        : (firstItem['currency_code'] ?? firstItem['currencyCode'])
            ?.toString()
            .trim();
    final explicitOrderCurrency =
        (order['currency_code'] ?? order['currencyCode'])?.toString().trim();
    final orderCurrency = (explicitOrderCurrency?.isNotEmpty == true
            ? explicitOrderCurrency
            : firstItemCurrency?.isNotEmpty == true
                ? firstItemCurrency
                : CurrencyService.yerCode)
        .toString()
        .toUpperCase();
    final rates = {
      for (final currency in currencies)
        if (currency.rateToYER != null)
          currency.code.toUpperCase(): currency.rateToYER!,
      CurrencyService.yerCode: 1.0,
    };

    double? rateFor(Map<String, dynamic> item, String currencyCode) {
      if (currencyCode == CurrencyService.yerCode) return 1;
      final snapshotRate = amount(item['rate_to_yer'] ?? item['rateToYER']);
      final rate = snapshotRate ?? rates[currencyCode];
      return rate != null && rate.isFinite && rate > 0 ? rate : null;
    }

    final commissionIncluded = order['commission_included_in_subtotal'] == true;
    final commission = amount(order['commission']) ?? 0;
    var commissionInYER = commission;
    if (commissionIncluded && commission != 0) {
      if (orderCurrency != CurrencyService.yerCode) {
        Object? commissionRate;
        for (final rawItem in rawItems) {
          if (rawItem is! Map) continue;
          final item = Map<String, dynamic>.from(rawItem);
          final itemCurrency =
              (item['currency_code'] ?? item['currencyCode'] ?? '')
                  .toString()
                  .trim()
                  .toUpperCase();
          if (itemCurrency == orderCurrency) {
            commissionRate = item['rate_to_yer'] ?? item['rateToYER'];
            break;
          }
        }
        final rate = amount(commissionRate) ?? rates[orderCurrency];
        if (rate == null || rate <= 0) return null;
        commissionInYER *= rate;
      }
    }

    final lines = <({
      bool belongsToMerchant,
      double? grossYER,
      double? baseYER,
      double vatYER,
      double basisYER,
    })>[];
    var orderBasisYER = 0.0;

    for (final rawItem in rawItems) {
      if (rawItem is! Map) continue;
      final item = Map<String, dynamic>.from(rawItem);
      if (item['status']?.toString() == 'rejected') continue;

      final quantity = amount(item['quantity'] ?? item['qty']) ?? 1;
      final currencyCode =
          (item['currency_code'] ?? item['currencyCode'] ?? orderCurrency)
              .toString()
              .trim()
              .toUpperCase();
      final rate = rateFor(item, currencyCode);

      final storedGrossYER = amount(item['total_yer'] ?? item['totalYER']);
      final storedTotal = amount(
        item['total'] ?? item['line_total'] ?? item['lineTotal'],
      );
      final unitPrice = amount(
        item['unit_price'] ?? item['unitPrice'] ?? item['price'],
      );
      final rawGross =
          storedTotal ?? (unitPrice == null ? null : unitPrice * quantity);
      final grossYER = storedGrossYER ??
          (rawGross == null || rate == null ? null : rawGross * rate);

      final storedBaseUnitYER = amount(
        item['base_unit_price_yer'] ?? item['baseUnitPriceYER'],
      );
      final rawBaseUnit = amount(
        item['base_unit_price'] ?? item['baseUnitPrice'],
      );
      final baseYER = storedBaseUnitYER != null
          ? storedBaseUnitYER * quantity
          : rawBaseUnit == null || rate == null
              ? null
              : rawBaseUnit * quantity * rate;

      final storedVatYER =
          amount(item['vat_amount_yer'] ?? item['vatAmountYER']);
      final rawVat = amount(item['vat_amount'] ?? item['vatAmount']);
      final vatYER =
          storedVatYER ?? (rawVat == null || rate == null ? 0 : rawVat * rate);
      if (grossYER == null && baseYER == null) {
        final belongsToMerchant = itemBelongsToMerchant(
          item,
          merchantId: merchantId,
          productOwners: productOwners,
          merchantProductIds: merchantProductIds,
        );
        if (belongsToMerchant || (commissionIncluded && commissionInYER != 0)) {
          return null;
        }
        continue;
      }

      final basisYER =
          baseYER ?? ((grossYER ?? 0) - vatYER).clamp(0, double.infinity);
      orderBasisYER += basisYER;
      lines.add((
        belongsToMerchant: itemBelongsToMerchant(
          item,
          merchantId: merchantId,
          productOwners: productOwners,
          merchantProductIds: merchantProductIds,
        ),
        grossYER: grossYER,
        baseYER: baseYER,
        vatYER: vatYER,
        basisYER: basisYER,
      ));
    }

    var merchantTotalYER = 0.0;
    var hasMerchantItem = false;
    for (final line in lines) {
      if (!line.belongsToMerchant) continue;
      hasMerchantItem = true;
      if (line.baseYER != null) {
        merchantTotalYER += line.baseYER!;
        continue;
      }

      var lineTotalYER =
          (line.grossYER! - line.vatYER).clamp(0, double.infinity).toDouble();
      if (commissionIncluded && commissionInYER > 0 && orderBasisYER > 0) {
        lineTotalYER =
            (lineTotalYER - commissionInYER * line.basisYER / orderBasisYER)
                .clamp(0, double.infinity)
                .toDouble();
      }
      merchantTotalYER += lineTotalYER;
    }

    return hasMerchantItem ? merchantTotalYER : null;
  }
}
