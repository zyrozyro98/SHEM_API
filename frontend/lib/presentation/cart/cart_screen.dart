import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:she_m_app/data/models/product_model.dart';
import 'package:she_m_app/data/services/cart_service.dart';
import 'package:she_m_app/data/services/auth_service.dart';
import 'package:she_m_app/data/services/catalog_service.dart';
import 'package:she_m_app/data/services/currency_service.dart';
import 'package:she_m_app/data/services/media_upload_service.dart';
import 'package:she_m_app/presentation/auth/phone_login_screen.dart';
import 'package:she_m_app/presentation/catalog/product_catalog.dart';
import 'package:she_m_app/presentation/catalog/product_detail_screen_full.dart';
import 'package:she_m_app/presentation/checkout/delivery_address_screen.dart';
import 'package:she_m_app/core/animations/route_transitions.dart';
import 'package:she_m_app/core/theme/design_tokens.dart';
import 'package:she_m_app/presentation/common/custom_appbar.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key, this.catalogService, this.currencyService});

  final CatalogService? catalogService;
  final CurrencyService? currencyService;

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final Set<String> _selectedProductIds = <String>{};
  final Set<String> _knownProductIds = <String>{};
  late final Future<List<ProductModel>> _catalogProductsFuture;
  Map<String, CurrencyOption> _currenciesByCode = const {};
  bool _currenciesLoaded = false;

  @override
  void initState() {
    super.initState();
    _catalogProductsFuture =
        (widget.catalogService ?? CatalogService()).getProducts();
    final currentIds =
        CartService.instance.items.map((item) => item.product.id).toSet();
    _selectedProductIds.addAll(currentIds);
    _knownProductIds.addAll(currentIds);
    CartService.instance.addListener(_refreshCart);
    _loadCurrencies();
  }

  Future<void> _loadCurrencies() async {
    final currencies =
        await (widget.currencyService ?? CurrencyService()).getCurrencies();
    if (!mounted) return;
    setState(() {
      _currenciesByCode = {
        for (final currency in currencies)
          currency.code.toUpperCase(): currency,
      };
      _currenciesLoaded = true;
    });
  }

  double? _rateToYER(String currencyCode) {
    if (currencyCode.toUpperCase() == CurrencyService.yerCode) return 1;
    return _currenciesByCode[currencyCode.toUpperCase()]?.rateToYER;
  }

  void _refreshCart() {
    if (!mounted) return;
    final currentIds =
        CartService.instance.items.map((item) => item.product.id).toSet();
    final newlyAddedIds = currentIds.difference(_knownProductIds);
    setState(() {
      _selectedProductIds
        ..removeWhere((id) => !currentIds.contains(id))
        ..addAll(newlyAddedIds);
      _knownProductIds
        ..clear()
        ..addAll(currentIds);
    });
  }

  void _toggleProductSelection(String productId, bool selected) {
    setState(() {
      if (selected) {
        _selectedProductIds.add(productId);
      } else {
        _selectedProductIds.remove(productId);
      }
    });
  }

  @override
  void dispose() {
    CartService.instance.removeListener(_refreshCart);
    super.dispose();
  }

  Widget _buildOrderSummary(
    BuildContext context, {
    required double subtotal,
    required String currencySymbol,
    required bool showExchangeRateWarning,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.receipt_long_rounded,
                color: Theme.of(context).colorScheme.primary,
                size: 17,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'ملخص الطلب',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (showExchangeRateWarning)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'سعر صرف إحدى العملات غير محدد من المدير.',
                style: TextStyle(color: Color(0xFFFCA5A5), fontSize: 10),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'المجموع الفرعي',
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
              Expanded(
                child: Text(
                  '${subtotal.toStringAsFixed(0)} $currencySymbol',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ],
          ),
          const Row(
            children: [
              Icon(Icons.local_shipping_outlined,
                  color: Colors.white70, size: 14),
              SizedBox(width: 5),
              Expanded(
                child: Text(
                  'تُحسب أجرة التوصيل بعد تحديد العنوان',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white24, height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'الإجمالي قبل التوصيل',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              Expanded(
                child: Text(
                  '${subtotal.toStringAsFixed(0)} $currencySymbol',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'الدفع عند الاستلام',
            style: TextStyle(color: Colors.white70, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckoutButton(
    BuildContext context, {
    required List<CartEntry> selectedItems,
    required bool hasExchangeRates,
  }) {
    final selectedProductIds =
        selectedItems.map((item) => item.product.id).toSet();

    Future<void> beginCheckout() async {
      final profile = await AuthService().loadSession();
      if (!context.mounted) return;
      Navigator.of(context).push(
        slideFadeRoute(
          page: profile == null
              ? PhoneLoginScreen(
                  returnToCheckout: true,
                  checkoutProductIds: selectedProductIds,
                )
              : DeliveryAddressScreen(
                  selectedProductIds: selectedProductIds,
                ),
        ),
      );
    }

    return SizedBox(
      height: 112,
      width: double.infinity,
      child: ElevatedButton(
        onPressed:
            selectedItems.isEmpty || !hasExchangeRates ? null : beginCheckout,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF16A34A),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.shopping_bag_rounded, size: 21),
                const SizedBox(width: 7),
                Semantics(
                  label: 'عدد المنتجات المحددة ${selectedItems.length}',
                  child: Container(
                    key: const ValueKey('checkout_selected_count'),
                    constraints: const BoxConstraints(
                      minWidth: 22,
                      minHeight: 22,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${selectedItems.length}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            const Text(
              'إتمام الطلب',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimilarProducts(
    BuildContext context,
    List<CartEntry> cartItems,
  ) {
    final cartProductIds = cartItems.map((item) => item.product.id).toSet();
    final cartCategories = cartItems
        .map((item) => item.product.category.trim().toLowerCase())
        .where((category) => category.isNotEmpty)
        .toSet();

    return FutureBuilder<List<ProductModel>>(
      future: _catalogProductsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        final suggestions = (snapshot.data ?? const <ProductModel>[])
            .where((product) =>
                product.available &&
                !cartProductIds.contains(product.id) &&
                cartCategories.contains(product.category.trim().toLowerCase()))
            .take(8)
            .toList();
        if (suggestions.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFB69449).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: Color(0xFF8B6A27),
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'منتجات قد تناسبك',
                          style: TextStyle(
                            color: Color(0xFF1B120C),
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'اختيارات مشابهة لما في سلتك',
                          style: TextStyle(
                            color: Color(0xFF766A60),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${suggestions.length} منتجات',
                    style: const TextStyle(
                      color: Color(0xFF8B6A27),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 224,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: suggestions.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 10),
                  itemBuilder: (context, index) =>
                      _buildSimilarProductCard(context, suggestions[index]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSimilarProductCard(
    BuildContext context,
    ProductModel product,
  ) {
    final imageUrl = product.imageUrl.trim();

    return SizedBox(
      width: 168,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: ValueKey('recommendation_product_${product.id}'),
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            Navigator.of(context).push(
              slideFadeRoute(page: ProductDetailFullScreen(product: product)),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE8DDD0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    height: 96,
                    width: double.infinity,
                    child: imageUrl.isEmpty
                        ? _buildRecommendationImagePlaceholder(context)
                        : CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            placeholder: (context, url) =>
                                _buildRecommendationImagePlaceholder(context),
                            errorWidget: (context, url, error) =>
                                _buildRecommendationImagePlaceholder(context),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  product.category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF8B6A27),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF1B120C),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  product.formatPrice(product.priceIncludingVat),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF8B6A27),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCartProductImage(
    BuildContext context,
    String imageUrl,
    String productId,
  ) {
    final imageProvider = MediaUploadService.imageProvider(imageUrl);
    final placeholder = Container(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
      alignment: Alignment.center,
      child: Icon(
        Icons.shopping_bag_rounded,
        color: Theme.of(context).colorScheme.primary,
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        key: ValueKey('cart-product-image-$productId'),
        width: 72,
        height: 72,
        child: imageProvider == null
            ? placeholder
            : Image(
                image: imageProvider,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => placeholder,
              ),
      ),
    );
  }

  Widget _buildRecommendationImagePlaceholder(BuildContext context) {
    return Container(
      color: const Color(0xFFF6F1EA),
      alignment: Alignment.center,
      child: Icon(
        Icons.shopping_bag_outlined,
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
        size: 30,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = CartService.instance.items;
    final selectedItems = items
        .where((item) => _selectedProductIds.contains(item.product.id))
        .toList();
    final hasExchangeRates = _currenciesLoaded &&
        selectedItems.every(
          (item) => _rateToYER(item.product.currencyCode) != null,
        );
    final subtotal = selectedItems.fold<double>(0, (sum, item) {
      final rate = _rateToYER(item.product.currencyCode);
      return sum + (rate == null ? 0 : item.lineTotal * rate);
    });
    const currencySymbol = 'ر.ي';

    if (items.isEmpty) {
      return Scaffold(
        appBar: const CustomAppBar(
          title: 'سلة التسوق',
          icon: Icons.shopping_cart_rounded,
        ),
        body: Directionality(
          textDirection: TextDirection.rtl,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Icon(
                        Icons.shopping_bag_outlined,
                        color: Theme.of(context).colorScheme.primary,
                        size: 42,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'السلة فارغة حاليًا',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'ابدأ بإضافة منتجات من المتجر',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF6B7280)),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          final navigator = Navigator.of(context);
                          if (navigator.canPop()) {
                            navigator.pop();
                            return;
                          }
                          navigator.push(
                            slideFadeRoute(page: ProductCatalogScreen()),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD4AF37),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('متابعة التسوق'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: const CustomAppBar(
        title: 'سلة التسوق',
        icon: Icons.shopping_cart_rounded,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                child: ListView(
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
                        border: Border.all(color: const Color(0xFFE8DFA8)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${selectedItems.length}/${items.length}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF111827),
                                ),
                              ),
                              Checkbox(
                                value: selectedItems.length == items.length,
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                onChanged: (selected) {
                                  setState(() {
                                    if (selected == true) {
                                      _selectedProductIds
                                        ..clear()
                                        ..addAll(items
                                            .map((item) => item.product.id));
                                    } else {
                                      _selectedProductIds.clear();
                                    }
                                  });
                                },
                              ),
                              const Text('تحديد الكل'),
                            ],
                          ),
                          const Text(
                            'حدد المنتجات لإتمامها',
                            style: TextStyle(
                              color: Color(0xFF111827),
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...items.map((item) => Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: DesignTokens.elevatedShadow,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Checkbox(
                                value: _selectedProductIds
                                    .contains(item.product.id),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                onChanged: (selected) =>
                                    _toggleProductSelection(
                                  item.product.id,
                                  selected == true,
                                ),
                              ),
                              _buildCartProductImage(
                                context,
                                item.product.imageUrl,
                                item.product.id,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 10),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              item.product.name,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'حذف المنتج',
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed: () => CartService
                                                .instance
                                                .removeProduct(item.product.id),
                                            icon: const Icon(
                                              Icons.delete_outline_rounded,
                                              color: Color(0xFFB91C1C),
                                              size: 20,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      if (item.customizationSummary.isNotEmpty)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 8),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF3F4F6),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              item.customizationSummary,
                                              style: const TextStyle(
                                                color: Color(0xFF374151),
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            '${item.product.formatPrice(item.product.priceIncludingVat)} / قطعة',
                                            style: const TextStyle(
                                              color: Color(0xFF6B7280),
                                              fontSize: 12,
                                            ),
                                          ),
                                          Container(
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF8F3DF),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  tooltip: 'زيادة الكمية',
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  onPressed: () => CartService
                                                      .instance
                                                      .updateQuantity(
                                                          item.product.id,
                                                          item.quantity + 1),
                                                  icon: const Icon(
                                                      Icons.add_rounded,
                                                      size: 18),
                                                ),
                                                Text('${item.quantity}',
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w800)),
                                                IconButton(
                                                  tooltip: 'إنقاص الكمية',
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  onPressed: () => CartService
                                                      .instance
                                                      .updateQuantity(
                                                          item.product.id,
                                                          item.quantity - 1),
                                                  icon: const Icon(
                                                      Icons.remove_rounded,
                                                      size: 18),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    item.product.formatPrice(
                                        item.product.priceIncludingVat),
                                    style: const TextStyle(
                                      color: Color(0xFF6B7280),
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 28),
                                  Text(
                                    item.product.formatPrice(item.lineTotal),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        )),
                    _buildSimilarProducts(context, items),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SafeArea(
                top: false,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      flex: 3,
                      child: _buildOrderSummary(
                        context,
                        subtotal: subtotal,
                        currencySymbol: currencySymbol,
                        showExchangeRateWarning:
                            _currenciesLoaded && !hasExchangeRates,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: _buildCheckoutButton(
                        context,
                        selectedItems: selectedItems,
                        hasExchangeRates: hasExchangeRates,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// _CartItem is not used and was removed to satisfy analyzer warnings.
