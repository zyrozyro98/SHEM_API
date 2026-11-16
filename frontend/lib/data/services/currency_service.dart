import 'package:she_m_app/data/services/firebase_database_service.dart';

class CurrencyOption {
  final String title;
  final String code;
  final String symbol;
  final bool isDefault;
  final bool enabled;
  final double? rateToYER;

  const CurrencyOption({
    required this.title,
    required this.code,
    required this.symbol,
    this.isDefault = false,
    this.enabled = true,
    this.rateToYER,
  });

  factory CurrencyOption.fromJson(Map<String, dynamic> json) {
    final code = json['code']?.toString().trim().toUpperCase() ?? '';
    return CurrencyOption(
      title: json['title']?.toString() ?? '',
      code: code,
      symbol: json['symbol']?.toString() ?? '',
      isDefault: json['is_default'] == true,
      enabled: json['enabled'] != false,
      rateToYER: code == CurrencyService.yerCode
          ? 1
          : _parseRate(json['rate_to_yer'] ?? json['rateToYER']),
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'code': code,
        'symbol': symbol,
        'is_default': isDefault,
        'enabled': enabled,
        'rate_to_yer':
            code.toUpperCase() == CurrencyService.yerCode ? 1 : rateToYER,
      };

  double? convertToYER(num amount) {
    final rate = rateToYER;
    if (rate == null || !rate.isFinite || rate <= 0) return null;
    return amount * rate;
  }

  static double? orderTotalInYER(
    Map<String, dynamic> order,
    List<CurrencyOption> currencies,
  ) {
    double? amount(Object? value) {
      final parsed =
          value is num ? value.toDouble() : double.tryParse('$value');
      return parsed != null && parsed.isFinite ? parsed : null;
    }

    final total = amount(order['total']);
    if (total == null) return null;
    final currencyByCode = {
      for (final currency in currencies) currency.code.toUpperCase(): currency,
      CurrencyService.yerCode: CurrencyService.yerCurrency,
    };
    double? convert(double value, String code, Object? rateOverride) {
      final normalizedCode = code.trim().toUpperCase();
      if (normalizedCode == CurrencyService.yerCode) return value;
      final overrideRate = amount(rateOverride);
      final rate = overrideRate ?? currencyByCode[normalizedCode]?.rateToYER;
      return rate != null && rate > 0 ? value * rate : null;
    }

    final rawItems = order['items'] ?? order['order_items'];
    final items = rawItems is List
        ? rawItems
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
        : const <Map<String, dynamic>>[];
    final explicitCode =
        (order['currency_code'] ?? order['currencyCode'])?.toString().trim();
    if (explicitCode != null && explicitCode.isNotEmpty) {
      final normalizedCode = explicitCode.toUpperCase();
      Object? snapshotRate;
      for (final item in items) {
        final itemCode = (item['currency_code'] ?? item['currencyCode'] ?? '')
            .toString()
            .trim()
            .toUpperCase();
        if (itemCode == normalizedCode) {
          snapshotRate = item['rate_to_yer'];
          break;
        }
      }
      return convert(total, explicitCode, snapshotRate);
    }

    if (items.isEmpty) return null;
    final itemCodes = items
        .map((item) => (item['currency_code'] ?? item['currencyCode'] ?? 'SAR')
            .toString()
            .trim()
            .toUpperCase())
        .toSet();
    if (itemCodes.length == 1) {
      return convert(total, itemCodes.single, items.first['rate_to_yer']);
    }
    return null;
  }

  static double? _parseRate(Object? value) {
    final rate = value is num ? value.toDouble() : double.tryParse('$value');
    return rate != null && rate.isFinite && rate > 0 ? rate : null;
  }
}

class CurrencyService {
  CurrencyService({DatabaseService? databaseService})
      : _databaseService = databaseService ?? FirebaseDatabaseService.instance;

  static const String _path = 'settings/currencies';
  static const String yerCode = 'YER';
  static const CurrencyOption yerCurrency = CurrencyOption(
    title: 'ريال يمني',
    code: yerCode,
    symbol: 'ر.ي',
    rateToYER: 1,
  );
  final DatabaseService _databaseService;

  static const List<CurrencyOption> fallbackCurrencies = [
    CurrencyOption(
        title: 'ريال سعودي', code: 'SAR', symbol: 'ر.س', isDefault: true),
    CurrencyOption(
        title: 'دولار أمريكي', code: 'USD', symbol: '\$', enabled: true),
    CurrencyOption(
        title: 'درهم إماراتي', code: 'AED', symbol: 'د.إ', enabled: true),
    yerCurrency,
  ];

  static double? orderTotalInYER(
    Map<String, dynamic> order,
    List<CurrencyOption> currencies,
  ) =>
      CurrencyOption.orderTotalInYER(order, currencies);

  Future<List<CurrencyOption>> getCurrencies(
      {bool includeDisabled = false}) async {
    try {
      final snapshot = await _databaseService.read(_path);
      final currencies = snapshot.values
          .whereType<Map>()
          .map((value) =>
              CurrencyOption.fromJson(Map<String, dynamic>.from(value)))
          .where((currency) =>
              currency.code.isNotEmpty && (includeDisabled || currency.enabled))
          .toList();
      final availableCurrencies =
          snapshot.isEmpty ? fallbackCurrencies : currencies;
      if (availableCurrencies.any((currency) => currency.code == yerCode)) {
        return availableCurrencies;
      }
      return [...availableCurrencies, yerCurrency];
    } catch (_) {
      return fallbackCurrencies;
    }
  }

  Future<CurrencyOption> getDefaultCurrency() async {
    final currencies = await getCurrencies();
    return currencies.firstWhere(
      (currency) => currency.isDefault,
      orElse: () => currencies.first,
    );
  }

  Future<bool> saveCurrencies(List<CurrencyOption> currencies) async {
    if (currencies.any((currency) =>
        currency.code.toUpperCase() != yerCode &&
        currency.rateToYER != null &&
        (!currency.rateToYER!.isFinite || currency.rateToYER! <= 0))) {
      return false;
    }
    try {
      final payload = <String, dynamic>{};
      for (final currency in currencies) {
        payload[currency.code] = currency.toJson();
      }
      payload.putIfAbsent(yerCode, () => yerCurrency.toJson());
      await _databaseService.write(_path, payload);
      return true;
    } catch (_) {
      return false;
    }
  }
}
