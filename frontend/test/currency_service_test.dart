import 'package:flutter_test/flutter_test.dart';
import 'package:she_m_app/data/services/currency_service.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';

void main() {
  const currencies = [
    CurrencyOption(
      title: 'دولار أمريكي',
      code: 'USD',
      symbol: '\$',
      rateToYER: 530,
    ),
    CurrencyService.yerCurrency,
  ];

  test('keeps order totals already stored in YER unchanged', () {
    expect(
      CurrencyService.orderTotalInYER(
        {'total': 1200, 'currency_code': 'YER'},
        currencies,
      ),
      1200,
    );
  });

  test('converts a legacy single-currency order using configured rate', () {
    expect(
      CurrencyService.orderTotalInYER(
        {
          'total': 10,
          'items': [
            {'currency_code': 'USD'},
          ],
        },
        currencies,
      ),
      5300,
    );
  });

  test('uses the saved item exchange rate for historical order totals', () {
    expect(
      CurrencyService.orderTotalInYER(
        {
          'total': 10,
          'items': [
            {'currency_code': 'USD', 'rate_to_yer': 500},
          ],
        },
        currencies,
      ),
      5000,
    );
  });

  test('does not invent a rate for mixed-currency legacy orders', () {
    expect(
      CurrencyService.orderTotalInYER(
        {
          'total': 10,
          'items': [
            {'currency_code': 'USD'},
            {'currency_code': 'SAR'},
          ],
        },
        currencies,
      ),
      isNull,
    );
  });

  test('currency archive state is hidden from active currency options',
      () async {
    final database = _CurrencyDatabase({
      'SAR': {
        'title': 'ريال سعودي',
        'code': 'SAR',
        'symbol': 'ر.س',
        'is_default': true,
        'enabled': true,
      },
      'USD': {
        'title': 'دولار أمريكي',
        'code': 'USD',
        'symbol': r'$',
        'enabled': false,
      },
      'YER': {
        'title': 'ريال يمني',
        'code': 'YER',
        'symbol': 'ر.ي',
        'enabled': true,
      },
    });
    final service = CurrencyService(databaseService: database);

    final activeCurrencies = await service.getCurrencies();
    final archivedCurrencies = await service.getCurrencies(
      includeDisabled: true,
    );

    expect(activeCurrencies.map((currency) => currency.code), ['SAR', 'YER']);
    expect(archivedCurrencies.map((currency) => currency.code),
        ['SAR', 'USD', 'YER']);
    expect(
      await service.saveCurrencies(archivedCurrencies
          .map((currency) => currency.code == 'USD'
              ? CurrencyOption(
                  title: currency.title,
                  code: currency.code,
                  symbol: currency.symbol,
                  enabled: false,
                )
              : currency)
          .toList()),
      isTrue,
    );
    expect(database.written?['USD']['enabled'], isFalse);
  });
}

class _CurrencyDatabase implements DatabaseService {
  _CurrencyDatabase(this.currencies);

  final Map<String, dynamic> currencies;
  Map<String, dynamic>? written;

  @override
  Future<Map<String, dynamic>> read(String path) async => currencies;

  @override
  Future<Map<String, dynamic>> write(
    String path,
    Map<String, dynamic> data,
  ) async {
    written = data;
    return data;
  }

  @override
  Future<Map<String, dynamic>> update(
    String path,
    Map<String, dynamic> data,
  ) async =>
      data;

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
