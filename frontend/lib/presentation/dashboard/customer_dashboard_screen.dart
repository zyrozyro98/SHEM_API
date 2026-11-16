import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:she_m_app/core/animations/route_transitions.dart';
import 'package:she_m_app/core/errors/app_error.dart';
import 'package:she_m_app/data/models/order_model.dart';
import 'package:she_m_app/data/models/product_model.dart';
import 'package:she_m_app/data/models/promotion_model.dart';
import 'package:she_m_app/data/models/user_model.dart';
import 'package:she_m_app/data/services/auth_service.dart';
import 'package:she_m_app/data/services/cart_service.dart';
import 'package:she_m_app/data/services/catalog_service.dart';
import 'package:she_m_app/data/services/currency_service.dart';
import 'package:she_m_app/data/services/media_upload_service.dart';
import 'package:she_m_app/data/services/merchant_category_service.dart';
import 'package:she_m_app/data/services/order_service.dart';
import 'package:she_m_app/data/services/promotion_service.dart';
import 'package:she_m_app/data/services/wishlist_service.dart';
import 'package:she_m_app/presentation/auth/phone_login_screen.dart';
import 'package:she_m_app/presentation/auth/profile_setup_screen.dart';
import 'package:she_m_app/presentation/cart/cart_screen.dart';
import 'package:she_m_app/presentation/catalog/product_catalog.dart';
import 'package:she_m_app/presentation/catalog/product_detail_screen_full.dart';
import 'package:she_m_app/presentation/common/custom_appbar.dart';
import 'package:she_m_app/presentation/common/app_version_list_tile.dart';
import 'package:she_m_app/presentation/common/logout_confirmation_dialog.dart';
import 'package:she_m_app/presentation/common/notification_bell.dart';
import 'package:she_m_app/presentation/delivery/delivery_tracking_screen.dart';
import 'package:she_m_app/presentation/orders/orders_screen.dart';
import 'package:she_m_app/presentation/profile/profile_screen.dart';
import 'package:she_m_app/presentation/support/support_center_screen.dart';

String _normalizeCategoryName(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll(RegExp(r'\s+'), ' ');
}

List<ProductCategory> _legacyCategoriesFromProducts(
  List<ProductModel> products,
) {
  final categoriesByName = <String, ProductCategory>{};
  for (final product in products) {
    final name = product.mainCategory?.trim().isNotEmpty == true
        ? product.mainCategory!.trim()
        : product.category.trim();
    if (name.isEmpty) continue;

    final normalizedName = _normalizeCategoryName(name);
    final existing = categoriesByName[normalizedName];
    categoriesByName[normalizedName] = ProductCategory(
      id: 'legacy:$normalizedName',
      name: name,
      active: true,
      subcategories: const [],
      sortOrder: product.mainCategorySortOrder ?? existing?.sortOrder ?? 0,
    );
  }
  final categories = categoriesByName.values.toList()
    ..sort((first, second) {
      final order = first.sortOrder.compareTo(second.sortOrder);
      return order == 0 ? first.name.compareTo(second.name) : order;
    });
  return categories;
}

bool _productBelongsToCategory(
  ProductModel product,
  ProductCategory category,
) {
  final productCategoryId = product.mainCategoryId?.trim() ?? '';
  if (!category.id.startsWith('legacy:') && productCategoryId.isNotEmpty) {
    return productCategoryId == category.id;
  }

  final productMainCategory = product.mainCategory?.trim() ?? '';
  if (productMainCategory.isNotEmpty) {
    return _normalizeCategoryName(productMainCategory) ==
        _normalizeCategoryName(category.name);
  }

  final productCategory = product.category.trim();
  if (_normalizeCategoryName(productCategory) ==
      _normalizeCategoryName(category.name)) {
    return true;
  }

  return category.activeSubcategories.any(
    (subcategory) =>
        _normalizeCategoryName(subcategory.name) ==
        _normalizeCategoryName(productCategory),
  );
}

bool _productBelongsToSubcategory(
  ProductModel product,
  ProductCategory category,
  ProductSubcategory subcategory,
) {
  if (!_productBelongsToCategory(product, category)) return false;

  final productSubcategoryId = product.subcategoryId?.trim() ?? '';
  if (productSubcategoryId.isNotEmpty) {
    return productSubcategoryId == subcategory.id;
  }

  final productSubcategory = product.subcategory?.trim().isNotEmpty == true
      ? product.subcategory!.trim()
      : product.category.trim();
  return _normalizeCategoryName(productSubcategory) ==
      _normalizeCategoryName(subcategory.name);
}

Future<List<ProductCategory>> _loadDisplayCategories(
  MerchantCategoryService categoryService,
  List<ProductModel> products, {
  Future<_CategoryDataResult>? categoryDataFuture,
  bool forceRefresh = false,
}) async {
  final result = await (categoryDataFuture ??
      _loadCategoryData(categoryService, forceRefresh: forceRefresh));
  if (result.error != null) {
    final error = result.error!;
    if (error is AppException && error.kind == AppErrorKind.access) {
      return _legacyCategoriesFromProducts(products);
    }
    Error.throwWithStackTrace(error, result.stackTrace!);
  }
  final categoryData = result.data!;
  if (categoryData.isEmpty) {
    return _legacyCategoriesFromProducts(products);
  }
  return categoryService.getActiveProductCategoryTree(
    categoryData: categoryData,
  );
}

Future<_CategoryDataResult> _loadCategoryData(
  MerchantCategoryService categoryService, {
  required bool forceRefresh,
}) async {
  try {
    final data = await categoryService.getAllProductCategories(
      forceRefresh: forceRefresh,
    );
    return _CategoryDataResult.success(data);
  } catch (error, stackTrace) {
    return _CategoryDataResult.failure(error, stackTrace);
  }
}

class _CategoryDataResult {
  const _CategoryDataResult.success(this.data)
      : error = null,
        stackTrace = null;
  const _CategoryDataResult.failure(this.error, this.stackTrace) : data = null;

  final Map<String, dynamic>? data;
  final Object? error;
  final StackTrace? stackTrace;
}

class CustomerDashboardScreen extends StatefulWidget {
  const CustomerDashboardScreen({
    super.key,
    this.showCartPrompt = false,
  });

  final bool showCartPrompt;

  @override
  State<CustomerDashboardScreen> createState() =>
      _CustomerDashboardScreenState();
}

class _CustomerDashboardScreenState extends State<CustomerDashboardScreen> {
  UserModel? _profile;
  List<OrderModel> _orders = const [];
  String _currencySymbol = 'ر.ي';
  double _totalSpentYER = 0;
  int _unconvertedOrderCount = 0;
  bool _loading = true;
  int _currentIndex = 0;
  bool _cartPromptShown = false;
  Widget? _productsPage;

  @override
  void initState() {
    super.initState();
    AuthService.profileUpdated.addListener(_handleProfileUpdated);
    _loadData();
  }

  @override
  void dispose() {
    AuthService.profileUpdated.removeListener(_handleProfileUpdated);
    super.dispose();
  }

  void _handleProfileUpdated() {
    if (mounted) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
    });

    final authService = AuthService();
    final profile = await authService.loadSession();
    final customerId = profile == null
        ? null
        : (profile.id.trim().isNotEmpty
            ? profile.id
            : (profile.phone.trim().isNotEmpty ? profile.phone : null));

    final orders = customerId == null
        ? const <OrderModel>[]
        : await OrderService().getOrdersByCustomer(customerId);
    final currencies = await CurrencyService().getCurrencies();
    final convertedTotals = orders.map((order) {
      final orderData = order.toJson();
      if (!order.hasExplicitCurrencyCode) {
        orderData.remove('currency_code');
      }
      return CurrencyOption.orderTotalInYER(orderData, currencies);
    }).toList();
    final totalSpentYER = convertedTotals.fold<double>(
      0,
      (sum, value) => sum + (value ?? 0),
    );
    final unconvertedOrderCount =
        convertedTotals.where((value) => value == null).length;
    if (customerId != null) {
      await WishlistService.instance.loadForCustomer(customerId);
    }

    if (!mounted) return;

    setState(() {
      _profile = profile;
      _orders = orders;
      _currencySymbol = CurrencyService.yerCurrency.symbol;
      _totalSpentYER = totalSpentYER;
      _unconvertedOrderCount = unconvertedOrderCount;
      _loading = false;
    });
    _showCartPromptIfNeeded();
  }

  void _showCartPromptIfNeeded() {
    if (!widget.showCartPrompt ||
        _cartPromptShown ||
        CartService.instance.items.isEmpty) {
      return;
    }

    _cartPromptShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('منتجاتك ما زالت في السلة'),
          content: const Text('يمكنك متابعة التسوق أو فتح السلة الآن.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('إغلاق'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                if (mounted) setState(() => _currentIndex = 3);
              },
              icon: const Icon(Icons.shopping_cart_rounded),
              label: const Text('فتح السلة'),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _refreshData() async {
    await _loadData();
  }

  void _selectTab(int index) {
    if (index == 2) {
      final catalogService = CatalogService();
      final cachedProducts = catalogService.cachedProducts;
      _productsPage ??= ProductCatalogScreen(
        catalogService: catalogService,
        initialProducts: cachedProducts.isEmpty ? null : cachedProducts,
        reloadInitialProducts: () =>
            catalogService.getProducts(forceRefresh: true),
        searchHistoryUserId: _profile?.id,
      );
    }
    setState(() => _currentIndex = index);
  }

  Widget _buildBottomNavigationBar({bool forOrdersScreen = false}) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: forOrdersScreen ? 1 : _currentIndex,
        selectedItemColor: const Color(0xFFB69449),
        unselectedItemColor: const Color(0xFF6B7280),
        backgroundColor: Colors.white,
        onTap: (index) {
          if (forOrdersScreen) {
            if (index == 1) return;
            Navigator.of(context).pop();
            _selectTab(index);
            return;
          }
          if (index == 1) {
            Navigator.of(context).push(
              slideFadeRoute(
                page: OrdersScreen(
                  bottomNavigationBar:
                      _buildBottomNavigationBar(forOrdersScreen: true),
                ),
              ),
            );
            return;
          }
          _selectTab(index);
        },
        items: [
          const BottomNavigationBarItem(
              icon: Icon(Icons.home_rounded), label: 'الرئيسية'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.receipt_long_rounded), label: 'الطلبات'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.storefront_rounded), label: 'المنتجات'),
          BottomNavigationBarItem(
            icon: AnimatedBuilder(
              animation: CartService.instance,
              builder: (context, child) {
                final count = CartService.instance.itemCount;
                return Badge(
                  isLabelVisible: count > 0,
                  label: Text('$count'),
                  child: child,
                );
              },
              child: const Icon(Icons.shopping_cart_rounded),
            ),
            label: 'السلة',
          ),
          const BottomNavigationBarItem(
              icon: Icon(Icons.person_rounded), label: 'حسابي'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final pages = <Widget>[
      CustomerHomeScreen(
        profile: _profile,
        orders: _orders,
        currencySymbol: _currencySymbol,
        onRefresh: _refreshData,
      ),
      CustomerCategoriesScreen(searchHistoryUserId: _profile?.id),
      _productsPage ?? const SizedBox.shrink(),
      const CartScreen(),
      const ProfileScreen(),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        final navigator = Navigator.of(context);
        if (navigator.canPop()) {
          navigator.pop();
          return;
        }

        if (_currentIndex != 0) {
          setState(() => _currentIndex = 0);
          return;
        }

        showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('الخروج من التطبيق'),
            content: const Text('هل أنت متأكد من رغبتك في الخروج من التطبيق؟'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  SystemNavigator.pop();
                },
                child: const Text('خروج'),
              ),
            ],
          ),
        );
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: _currentIndex == 0
            ? AppBar(
                automaticallyImplyLeading: false,
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1B120C),
                elevation: 0,
                titleSpacing: 12,
                leadingWidth: 52,
                leading: IconButton(
                  tooltip: 'المفضلة',
                  onPressed: () => Navigator.of(context).push(
                    slideFadeRoute(page: const CustomerWishlistScreen()),
                  ),
                  icon: const Icon(Icons.favorite_border_rounded),
                ),
                title: Semantics(
                  button: true,
                  label: 'فتح البحث',
                  child: InkWell(
                    onTap: () => Navigator.of(context).push(
                      slideFadeRoute(
                        page: ProductCatalogScreen(
                            searchHistoryUserId: _profile?.id),
                      ),
                    ),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE8DED0)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search_rounded,
                              size: 20, color: Color(0xFF6B7280)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'بحث',
                              style: TextStyle(
                                color: const Color(0xFF6B7280)
                                    .withValues(alpha: 0.8),
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                actions: [
                  const NotificationBell(compactBadge: true),
                  Builder(
                    builder: (context) => IconButton(
                      tooltip: 'القائمة الجانبية',
                      onPressed: () => Scaffold.of(context).openEndDrawer(),
                      icon: const Icon(Icons.menu_rounded),
                    ),
                  ),
                ],
              )
            : null,
        endDrawer: Drawer(
          width: 330,
          backgroundColor: Colors.white,
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 20),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF111111),
                              Color(0xFF23180F),
                            ],
                            begin: Alignment.topRight,
                            end: Alignment.bottomLeft,
                          ),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: const Color(0xFFD4AF37),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.14),
                              blurRadius: 16,
                              offset: const Offset(0, 7),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(
                                      alpha: 0.10,
                                    ),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Image.asset(
                                    'assets/icon/app_icon.png',
                                    fit: BoxFit.contain,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'SHE M',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 17,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        'تجربة تسوقك تبدأ هنا',
                                        style: TextStyle(
                                          color: Color(0xFFE8D8BA),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFD4AF37)
                                        .withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    _profile == null ? 'ضيف' : 'حسابي',
                                    style: const TextStyle(
                                      color: Color(0xFFF5E9C9),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Divider(
                                height: 1,
                                color: Color(0x33FFFFFF),
                              ),
                            ),
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 24,
                                  backgroundColor: const Color(0xFFD4AF37),
                                  backgroundImage: () {
                                    final imageData =
                                        _profile?.profileImageData;
                                    final imageBytes = imageData == null
                                        ? null
                                        : MediaUploadService
                                            .decodeDataUriToBytes(
                                            imageData,
                                          );
                                    return imageBytes == null
                                        ? null
                                        : MemoryImage(imageBytes);
                                  }(),
                                  child: () {
                                    final imageData =
                                        _profile?.profileImageData;
                                    final imageBytes = imageData == null
                                        ? null
                                        : MediaUploadService
                                            .decodeDataUriToBytes(
                                            imageData,
                                          );
                                    return imageBytes == null
                                        ? Text(
                                            (_profile?.fullName
                                                        .trim()
                                                        .isNotEmpty ??
                                                    false)
                                                ? _profile!.fullName
                                                    .trim()[0]
                                                    .toUpperCase()
                                                : 'S',
                                            style: const TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w900,
                                              color: Color(0xFF1B120C),
                                            ),
                                          )
                                        : null;
                                  }(),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _profile?.fullName ?? 'ضيف',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        _profile?.phone ?? 'أهلاً بك في SHE M',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFFE8D8BA),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_profile != null)
                                  const Icon(
                                    Icons.verified_rounded,
                                    color: Color(0xFFD4AF37),
                                    size: 20,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: const BoxDecoration(
                        color: Color(0xFFF5E9C9),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        tooltip: 'إغلاق القائمة',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded, size: 20),
                        color: const Color(0xFF1B120C),
                        padding: const EdgeInsets.all(8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_profile != null)
                  Row(
                    children: [
                      Expanded(
                        child: _DrawerSummary(
                          icon: Icons.receipt_long_rounded,
                          value: '${_orders.length}',
                          label: 'طلب',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AnimatedBuilder(
                          animation: CartService.instance,
                          builder: (context, _) => _DrawerSummary(
                            icon: Icons.shopping_bag_rounded,
                            value: '${CartService.instance.itemCount}',
                            label: 'في السلة',
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  AnimatedBuilder(
                    animation: CartService.instance,
                    builder: (context, _) => _DrawerSummary(
                      icon: Icons.shopping_bag_rounded,
                      value: '${CartService.instance.itemCount}',
                      label: 'في السلة',
                    ),
                  ),
                const SizedBox(height: 20),
                const _DrawerSectionTitle('التسوق'),
                _DrawerTile(
                  icon: Icons.storefront_rounded,
                  title: 'تصفح المنتجات',
                  subtitle: 'اكتشف أحدث المنتجات والمتاجر',
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      slideFadeRoute(
                        page: ProductCatalogScreen(
                          searchHistoryUserId: _profile?.id,
                        ),
                      ),
                    );
                  },
                ),
                _DrawerTile(
                  icon: Icons.shopping_cart_rounded,
                  title: 'السلة',
                  subtitle: 'راجع المنتجات قبل إتمام الطلب',
                  onTap: () {
                    Navigator.of(context).pop();
                    setState(() => _currentIndex = 3);
                  },
                ),
                if (_profile != null) ...[
                  const _DrawerSectionTitle('طلباتي'),
                  _DrawerTile(
                    icon: Icons.receipt_long_rounded,
                    title: 'كل الطلبات',
                    subtitle: 'عرض سجل مشترياتك',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        slideFadeRoute(
                          page: OrdersScreen(
                            bottomNavigationBar: _buildBottomNavigationBar(
                              forOrdersScreen: true,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  _DrawerTile(
                    icon: Icons.insights_rounded,
                    title: 'ملخص الأداء',
                    subtitle: 'إحصائيات طلباتك وإنفاقك',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        slideFadeRoute(
                          page: CustomerStatsScreen(
                            orders: _orders,
                            totalSpentYER: _totalSpentYER,
                            unconvertedOrderCount: _unconvertedOrderCount,
                            currencySymbol: _currencySymbol,
                          ),
                        ),
                      );
                    },
                  ),
                  _DrawerTile(
                    icon: Icons.local_shipping_rounded,
                    title: 'متابعة الطلب',
                    subtitle: 'اعرف حالة التوصيل لحظة بلحظة',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                          slideFadeRoute(page: const DeliveryTrackingScreen()));
                    },
                  ),
                  const _DrawerSectionTitle('المساعدة والحساب'),
                  _DrawerTile(
                    icon: Icons.support_agent_rounded,
                    title: 'مركز المساعدة',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                          slideFadeRoute(page: const SupportCenterScreen()));
                    },
                  ),
                ] else ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E8),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE7D3A3)),
                    ),
                    child: const Text(
                      'لإتمام الطلب، يرجى تسجيل الدخول أو إنشاء حساب جديد.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF6B5422),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                const Divider(height: 28),
                if (_profile == null) ...[
                  _DrawerTile(
                    icon: Icons.login_rounded,
                    title: 'تسجيل الدخول',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        slideFadeRoute(page: const PhoneLoginScreen()),
                      );
                    },
                  ),
                  _DrawerTile(
                    icon: Icons.person_add_alt_1_rounded,
                    title: 'إنشاء حساب جديد',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        slideFadeRoute(page: const ProfileSetupScreen()),
                      );
                    },
                  ),
                ] else
                  _DrawerTile(
                    icon: Icons.logout_rounded,
                    title: 'تسجيل الخروج',
                    iconColor: const Color(0xFFB91C1C),
                    titleColor: const Color(0xFFB91C1C),
                    onTap: () async {
                      Navigator.of(context).pop();
                      final shouldSignOut =
                          await showLogoutConfirmationDialog(context);
                      if (!shouldSignOut || !context.mounted) return;
                      await AuthService().clearSession();
                      await CartService.instance.loadForUser(null);
                      if (!context.mounted) return;
                      Navigator.of(context).pushAndRemoveUntil(
                        slideFadeRoute(page: const CustomerDashboardScreen()),
                        (route) => false,
                      );
                    },
                  ),
                const Divider(height: 28),
                const AppVersionListTile(),
              ],
            ),
          ),
        ),
        bottomNavigationBar: _buildBottomNavigationBar(),
        body: AnimatedIndexedStack(
          index: _currentIndex,
          children: pages,
        ),
      ),
    );
  }
}

class _PromoCarousel extends StatefulWidget {
  const _PromoCarousel({required this.promotions, required this.onTap});

  final List<PromotionModel> promotions;
  final ValueChanged<PromotionModel> onTap;

  @override
  State<_PromoCarousel> createState() => _PromoCarouselState();
}

class _PromoCarouselState extends State<_PromoCarousel> {
  late final PageController _controller;
  Timer? _timer;
  int _activeIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_controller.hasClients || widget.promotions.isEmpty) {
        return;
      }
      final nextIndex = (_activeIndex + 1) % widget.promotions.length;
      _controller.animateToPage(
        nextIndex,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 170,
      child: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.promotions.length,
            onPageChanged: (index) => setState(() => _activeIndex = index),
            itemBuilder: (context, index) {
              final promotion = widget.promotions[index];
              return InkWell(
                onTap: () => widget.onTap(promotion),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image(
                          image: MediaUploadService.imageProvider(
                                widget.promotions[index].imageUrl,
                              ) ??
                              NetworkImage(widget.promotions[index].imageUrl),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: const Color(0xFFE8DED0),
                            child: const Center(
                              child: Icon(Icons.image_rounded,
                                  size: 40, color: Color(0xFFB69449)),
                            ),
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.48),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          right: 18,
                          bottom: 18,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                promotion.title.isEmpty
                                    ? 'خصومات حصرية'
                                    : promotion.title,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                promotion.subtitle.isEmpty
                                    ? 'تسوق الآن واستمتع بعروض اليوم'
                                    : promotion.subtitle,
                                style: TextStyle(
                                  color: Color(0xFFF3F4F6),
                                  fontSize: 12,
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
            },
          ),
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                widget.promotions.length,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: _activeIndex == index ? 16 : 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: _activeIndex == index
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheMBrand extends StatefulWidget {
  const _SheMBrand();

  @override
  State<_SheMBrand> createState() => _SheMBrandState();
}

class _SheMBrandState extends State<_SheMBrand>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Text _brandText({Color? sheColor, Color? mColor}) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'SHE',
            style: TextStyle(
              color: sheColor ?? Colors.white,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.2,
            ),
          ),
          const TextSpan(text: ' '),
          TextSpan(
            text: 'M',
            style: TextStyle(
              color: mColor ?? const Color(0xFFD4AF37),
              fontWeight: FontWeight.w900,
              letterSpacing: 2.2,
            ),
          ),
        ],
      ),
      style: const TextStyle(fontSize: 20, height: 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'SHE M',
      child: SizedBox(
        width: 92,
        height: 30,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.hardEdge,
          children: [
            _brandText(),
            AnimatedBuilder(
              animation: _controller,
              child: const Text(
                'M',
                style: TextStyle(
                  color: Color(0xFFFFF4B0),
                  fontSize: 20,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.2,
                ),
              ),
              builder: (context, child) {
                final start = -2.2 + (_controller.value * 4.4);
                return Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: ShaderMask(
                      blendMode: BlendMode.srcIn,
                      shaderCallback: (bounds) => LinearGradient(
                        begin: Alignment(start, 0),
                        end: Alignment(start + 1.1, 0),
                        colors: const [
                          Colors.transparent,
                          Color(0x99FFF4B0),
                          Color(0xFFFFFBE6),
                          Color(0x99FFF4B0),
                          Colors.transparent,
                        ],
                        stops: const [0, 0.35, 0.5, 0.65, 1],
                      ).createShader(bounds),
                      child: child,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerSectionTitle extends StatelessWidget {
  const _DrawerSectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF1B120C),
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DrawerSummary extends StatelessWidget {
  const _DrawerSummary({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F3DF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 19, color: const Color(0xFF1B120C)),
          const SizedBox(width: 7),
          Text(value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1B120C),
              )),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF4B5563),
              )),
        ],
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  const _DrawerTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.iconColor,
    this.titleColor,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: (iconColor ?? const Color(0xFF1B120C)).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child:
            Icon(icon, color: iconColor ?? const Color(0xFF1B120C), size: 21),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: titleColor ?? const Color(0xFF1B120C),
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF4B5563),
              ),
            ),
      trailing:
          const Icon(Icons.chevron_left_rounded, color: Color(0xFF6B7280)),
      onTap: onTap,
    );
  }
}

class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({
    super.key,
    required this.profile,
    required this.orders,
    required this.currencySymbol,
    required this.onRefresh,
    this.catalogService,
    this.promotionService,
    this.categoryService,
  });

  final UserModel? profile;
  final List<OrderModel> orders;
  final String currencySymbol;
  final Future<void> Function() onRefresh;
  final CatalogService? catalogService;
  final PromotionService? promotionService;
  final MerchantCategoryService? categoryService;

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen>
    with WidgetsBindingObserver {
  late final CatalogService _catalogService;
  late final PromotionService _promotionService;
  late final MerchantCategoryService _categoryService;
  List<ProductModel> _products = const [];
  List<ProductCategory> _categories = const [];
  List<PromotionModel> _promotions = const [];
  Map<String, _CategoryHomeImages> _fallbackImages = const {};
  bool _productsLoading = true;
  bool _productsLoadFailed = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _catalogService = widget.catalogService ?? CatalogService();
    _promotionService = widget.promotionService ?? PromotionService();
    _categoryService = widget.categoryService ?? MerchantCategoryService();
    _loadProducts();
    _loadPromotions();
  }

  Future<void> _loadPromotions() async {
    try {
      final promotions = await _promotionService.getVisiblePromotions();
      if (!mounted) return;
      setState(() {
        _promotions = promotions;
      });
      for (final promotion in promotions) {
        final provider = MediaUploadService.imageProvider(promotion.imageUrl);
        if (provider != null) {
          precacheImage(provider, context);
        }
      }
    } catch (_) {}
  }

  Future<void> _openPromotion(PromotionModel promotion) async {
    final productId = promotion.productId.trim();
    if (productId.isEmpty) return;
    ProductModel? product;
    for (final item in _products) {
      if (item.id == productId) {
        product = item;
        break;
      }
    }
    product ??= await _catalogService.getProductById(productId);
    if (!mounted || product == null) return;
    Navigator.of(context).push(
      slideFadeRoute(page: ProductDetailFullScreen(product: product)),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_productsLoading) {
      _loadProducts(forceRefresh: true);
    }
  }

  Future<void> _loadProducts({bool forceRefresh = false}) async {
    if (forceRefresh) {
      setState(() {
        _productsLoading = true;
        _productsLoadFailed = false;
      });
    }
    try {
      final productsFuture = _catalogService.getProducts(
        forceRefresh: forceRefresh,
      );
      final categoryDataFuture = _loadCategoryData(
        _categoryService,
        forceRefresh: forceRefresh,
      );
      final products = await productsFuture;
      final categories = await _loadDisplayCategories(
        _categoryService,
        products,
        categoryDataFuture: categoryDataFuture,
        forceRefresh: forceRefresh,
      );
      final fallbackImages = _buildFallbackImages(categories, products);
      if (!mounted) return;
      setState(() {
        _products = products;
        _categories = categories;
        _fallbackImages = fallbackImages;
        _productsLoading = false;
        _productsLoadFailed = false;
      });
      WishlistService.instance.syncProducts(_products);
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() {
        _products = const [];
        _categories = const [];
        _fallbackImages = const {};
        _productsLoading = false;
        _productsLoadFailed = true;
      });
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'customer dashboard',
          context: ErrorDescription('while loading homepage categories'),
        ),
      );
    }
  }

  Map<String, _CategoryHomeImages> _buildFallbackImages(
    List<ProductCategory> categories,
    List<ProductModel> products,
  ) {
    final random = math.Random();
    return {
      for (final category in categories)
        category.id: _CategoryHomeImages.fromProducts(
          products.where(
            (product) =>
                _productBelongsToCategory(product, category) &&
                product.imageUrl.trim().isNotEmpty,
          ),
          random,
        ),
    };
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  List<ProductModel> _productsInCategory(ProductCategory category) {
    final products = _products
        .where((product) => _productBelongsToCategory(product, category))
        .toList()
      ..sort(ProductModel.compareNewestFirst);
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return products;
    return products
        .where(
          (product) =>
              '${product.name} ${product.category} ${product.mainCategory ?? ''} '
                      '${product.subcategory ?? ''} ${product.merchantName}'
                  .toLowerCase()
                  .contains(query),
        )
        .toList();
  }

  bool _categoryMatchesSearch(ProductCategory category) {
    final query = _searchQuery.trim().toLowerCase();
    return query.isEmpty ||
        category.name.toLowerCase().contains(query) ||
        _productsInCategory(category).isNotEmpty;
  }

  void _openCategory(ProductCategory category) {
    Future<List<ProductModel>> reloadCategoryProducts() async {
      final products = await _catalogService.getProducts(forceRefresh: true);
      return products
          .where((product) => _productBelongsToCategory(product, category))
          .toList();
    }

    Navigator.of(context).push(
      slideFadeRoute(
        page: ProductCatalogScreen(
          catalogService: _catalogService,
          initialProducts: _products
              .where(
                (product) => _productBelongsToCategory(product, category),
              )
              .toList(),
          reloadInitialProducts: reloadCategoryProducts,
          categoryName: category.name,
          searchHistoryUserId: widget.profile?.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categoriesWithProducts = _categories
        .where(
          (category) => _products.any(
            (product) => _productBelongsToCategory(product, category),
          ),
        )
        .toList();
    final visibleCategories =
        categoriesWithProducts.where(_categoryMatchesSearch).toList();

    return RefreshIndicator(
      onRefresh: () async {
        await widget.onRefresh();
        await _loadProducts(forceRefresh: true);
      },
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
          children: [
            const SizedBox(height: 8),
            if (widget.profile == null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE8DED0)),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'تصفح المتجر كضيف',
                        style: TextStyle(
                          color: Color(0xFF1B120C),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        slideFadeRoute(page: const PhoneLoginScreen()),
                      ),
                      child: const Text('دخول'),
                    ),
                    FilledButton.tonal(
                      onPressed: () => Navigator.of(context).push(
                        slideFadeRoute(page: const ProfileSetupScreen()),
                      ),
                      child: const Text('حساب جديد'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: visibleCategories.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final category = visibleCategories[index];
                        final isSelected = _searchQuery.toLowerCase() ==
                            category.name.toLowerCase();
                        return InkWell(
                          onTap: () {
                            final nextQuery = isSelected ? '' : category.name;
                            _searchQuery = nextQuery;
                            setState(() {});
                          },
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF1B120C)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: const Color(0xFFE8DED0),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              category.name,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : const Color(0xFF111827),
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => Navigator.of(context).push(
                    slideFadeRoute(
                      page: CustomerCategoriesScreen(
                        searchHistoryUserId: widget.profile?.id,
                      ),
                    ),
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFFE8DED0)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon:
                      const Icon(Icons.apps_rounded, color: Color(0xFF1B120C)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_promotions.isNotEmpty)
              _PromoCarousel(
                onTap: _openPromotion,
                promotions: _promotions,
              ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'الأقسام الرئيسية',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1B120C),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    slideFadeRoute(
                      page: CustomerCategoriesScreen(
                        searchHistoryUserId: widget.profile?.id,
                      ),
                    ),
                  ),
                  child: const Text('جميع الفئات'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_productsLoading)
              const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_productsLoadFailed)
              Center(
                child: TextButton.icon(
                  onPressed: () => _loadProducts(forceRefresh: true),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('تعذر التحميل، أعد المحاولة'),
                ),
              )
            else if (visibleCategories.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 36),
                child: Center(
                  child: Text(
                    'لا توجد أقسام متاحة حالياً',
                    style: TextStyle(color: Color(0xFF6B7280)),
                  ),
                ),
              )
            else ...[
              for (final category in visibleCategories)
                _HomeMainCategoryCard(
                  category: category,
                  images: _fallbackImages[category.id],
                  products: _productsInCategory(category).take(7).toList(),
                  onOpenCategory: () => _openCategory(category),
                ),
            ],
            if (!_productsLoading)
              _AllCategoriesHomeCard(
                onTap: () => Navigator.of(context).push(
                  slideFadeRoute(
                    page: CustomerCategoriesScreen(
                      searchHistoryUserId: widget.profile?.id,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _CategoryHomeImages {
  const _CategoryHomeImages({this.logo});

  factory _CategoryHomeImages.fromProducts(
    Iterable<ProductModel> products,
    math.Random random,
  ) {
    final imageUrls = products
        .map((product) => product.imageUrl.trim())
        .where((url) => url.isNotEmpty)
        .toSet()
        .toList();
    String? pickImage() =>
        imageUrls.isEmpty ? null : imageUrls[random.nextInt(imageUrls.length)];
    return _CategoryHomeImages(logo: pickImage());
  }

  final String? logo;
}

class _HomeMainCategoryCard extends StatelessWidget {
  const _HomeMainCategoryCard({
    required this.category,
    required this.products,
    required this.onOpenCategory,
    this.images,
  });

  final ProductCategory category;
  final List<ProductModel> products;
  final _CategoryHomeImages? images;
  final VoidCallback onOpenCategory;

  @override
  Widget build(BuildContext context) {
    final logoUrl = category.logoImageUrl ?? images?.logo;
    final logoProvider =
        logoUrl == null ? null : MediaUploadService.imageProvider(logoUrl);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(10),
      key: ValueKey('home-category-${category.id}'),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8DED0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C1B120C),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onOpenCategory,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: const Color(0xFFF8F3DF),
                      backgroundImage: logoProvider,
                      child: logoProvider == null
                          ? const Icon(
                              Icons.category_rounded,
                              color: Color(0xFF9A7B2F),
                            )
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            category.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF1B120C),
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const Text(
                            'تصفح منتجات القسم',
                            style: TextStyle(
                              color: Color(0xFF6B7280),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const CircleAvatar(
                      radius: 18,
                      backgroundColor: Color(0xFFF8F3DF),
                      child: Icon(
                        Icons.arrow_back_rounded,
                        color: Color(0xFF9A7B2F),
                        size: 19,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 156,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: products.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                if (index == products.length) {
                  return const SizedBox(
                    width: 82,
                    child: Center(
                      child: Text(
                        'وصلت للنهاية',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF9A7B2F),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  );
                }
                final product = products[index];
                final imageProvider =
                    MediaUploadService.imageProvider(product.imageUrl);
                return SizedBox(
                  width: 104,
                  child: Material(
                    color: const Color(0xFFFFF8E8),
                    borderRadius: BorderRadius.circular(13),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => Navigator.of(context).push(
                        slideFadeRoute(
                          page: ProductDetailFullScreen(product: product),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (imageProvider == null)
                                  const Center(
                                    child: Icon(
                                      Icons.shopping_bag_rounded,
                                      color: Color(0xFFB69449),
                                      size: 30,
                                    ),
                                  )
                                else
                                  Image(
                                    image: imageProvider,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Center(
                                      child: Icon(
                                        Icons.shopping_bag_rounded,
                                        color: Color(0xFFB69449),
                                        size: 30,
                                      ),
                                    ),
                                  ),
                                Positioned(
                                  right: 4,
                                  left: 4,
                                  bottom: 4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xE61B120C),
                                      borderRadius: BorderRadius.circular(7),
                                    ),
                                    child: Text(
                                      product.formatPrice(
                                        product.priceIncludingVat,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            height: 42,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 3,
                            ),
                            decoration: const BoxDecoration(
                              color: Color(0xFFFFF1CF),
                              borderRadius: BorderRadius.vertical(
                                bottom: Radius.circular(13),
                              ),
                            ),
                            child: Text(
                              product.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF332715),
                                fontSize: 9,
                                height: 1.15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AllCategoriesHomeCard extends StatelessWidget {
  const _AllCategoriesHomeCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: const Color(0xFF1B120C),
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 20),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Color(0xFFD4AF37),
                  child: Icon(
                    Icons.apps_rounded,
                    color: Color(0xFF1B120C),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'اكتشف جميع الفئات',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'اعثر على المزيد من المنتجات التي تناسبك',
                        style: TextStyle(
                          color: Color(0xFFEDE7D5),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_back_rounded, color: Color(0xFFD4AF37)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CustomerCategoriesScreen extends StatefulWidget {
  const CustomerCategoriesScreen({
    super.key,
    this.searchHistoryUserId,
    this.catalogService,
    this.categoryService,
  });

  final String? searchHistoryUserId;
  final CatalogService? catalogService;
  final MerchantCategoryService? categoryService;

  @override
  State<CustomerCategoriesScreen> createState() =>
      _CustomerCategoriesScreenState();
}

class _CustomerCategoriesScreenState extends State<CustomerCategoriesScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<ProductCategory> _categories = const [];
  List<ProductModel> _products = const [];
  final Set<String> _expandedCategoryIds = {};
  late final CatalogService _catalogService;
  late final MerchantCategoryService _categoryService;
  String _searchQuery = '';
  bool _isLoading = true;
  bool _hasLoadError = false;

  @override
  void initState() {
    super.initState();
    _catalogService = widget.catalogService ?? CatalogService();
    _categoryService = widget.categoryService ?? MerchantCategoryService();
    _loadCategories();
  }

  Future<void> _loadCategories({bool forceRefresh = false}) async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _hasLoadError = false;
      });
    }
    try {
      final productsFuture =
          _catalogService.getProducts(forceRefresh: forceRefresh);
      final categoryDataFuture = _loadCategoryData(
        _categoryService,
        forceRefresh: forceRefresh,
      );
      final products = await productsFuture;
      final categories = await _loadDisplayCategories(
        _categoryService,
        products,
        categoryDataFuture: categoryDataFuture,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _products = products;
        _categories = categories;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasLoadError = true;
        _isLoading = false;
      });
    }
  }

  int _categoryProductCount(ProductCategory category) => _products
      .where((product) => _productBelongsToCategory(product, category))
      .length;

  List<ProductModel> _productsInCategory(
    List<ProductModel> products,
    ProductCategory category, {
    ProductSubcategory? subcategory,
  }) {
    return products.where((product) {
      if (subcategory != null) {
        return _productBelongsToSubcategory(product, category, subcategory);
      }
      return _productBelongsToCategory(product, category);
    }).toList();
  }

  int _subcategoryProductCount(
    ProductCategory category,
    ProductSubcategory subcategory,
  ) =>
      _products
          .where((product) => _productBelongsToSubcategory(
                product,
                category,
                subcategory,
              ))
          .length;

  void _openCategory(
    ProductCategory category, {
    ProductSubcategory? subcategory,
  }) {
    final selectedProducts = _productsInCategory(
      _products,
      category,
      subcategory: subcategory,
    );
    Future<List<ProductModel>> reloadSelectedProducts() async {
      final products = await _catalogService.getProducts(forceRefresh: true);
      return _productsInCategory(
        products,
        category,
        subcategory: subcategory,
      );
    }

    Navigator.of(context).push(
      slideFadeRoute(
        page: ProductCatalogScreen(
          catalogService: _catalogService,
          searchHistoryUserId: widget.searchHistoryUserId,
          initialProducts: selectedProducts,
          reloadInitialProducts: reloadSelectedProducts,
          categoryName: subcategory?.name ?? category.name,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = _normalizeCategoryName(_searchQuery);
    final categoriesWithProducts = _categories
        .where((category) => _categoryProductCount(category) > 0)
        .toList();
    final categories = categoriesWithProducts.where((category) {
      if (normalizedQuery.isEmpty ||
          _normalizeCategoryName(category.name).contains(normalizedQuery)) {
        return true;
      }
      return category.activeSubcategories.any(
        (subcategory) =>
            _subcategoryProductCount(category, subcategory) > 0 &&
            _normalizeCategoryName(subcategory.name).contains(normalizedQuery),
      );
    }).toList();
    final colors = [
      const Color(0xFFE9D5FF),
      const Color(0xFFDBEAFE),
      const Color(0xFFDCFCE7),
      const Color(0xFFFDE68A),
      const Color(0xFFFECACA),
      const Color(0xFFE0E7FF),
    ];
    final icons = <IconData>[
      Icons.checkroom_rounded,
      Icons.devices_rounded,
      Icons.spa_rounded,
      Icons.home_rounded,
      Icons.child_care_rounded,
      Icons.auto_awesome_rounded,
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const CustomAppBar(
        title: 'الأقسام',
        icon: Icons.category_rounded,
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadCategories(forceRefresh: true),
        child: SafeArea(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(18),
            children: [
              TextField(
                key: const ValueKey('category_search_field'),
                controller: _searchController,
                onChanged: (value) => setState(() => _searchQuery = value),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'ابحث عن قسم',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'مسح البحث',
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                  filled: true,
                  fillColor: const Color(0xFFF9F7F2),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE8DED0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE8DED0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFB69449)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 64),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_hasLoadError)
                _buildCategoriesMessage(
                  icon: Icons.wifi_off_rounded,
                  message: 'تعذر تحميل الأقسام',
                  actionLabel: 'إعادة المحاولة',
                  onAction: () => _loadCategories(forceRefresh: true),
                )
              else if (categoriesWithProducts.isEmpty)
                _buildCategoriesMessage(
                  icon: Icons.category_outlined,
                  message: 'لا توجد أقسام تحتوي على منتجات حاليًا',
                )
              else if (categories.isEmpty)
                _buildCategoriesMessage(
                  icon: Icons.search_off_rounded,
                  message: 'لا توجد أقسام مطابقة لبحثك',
                  actionLabel: 'مسح البحث',
                  onAction: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              else
                ...categories.asMap().entries.map((entry) {
                  final index = entry.key;
                  final category = entry.value;
                  final activeSubcategories = category.activeSubcategories
                      .where(
                        (subcategory) =>
                            _subcategoryProductCount(category, subcategory) > 0,
                      )
                      .toList();
                  final categoryMatchesQuery = normalizedQuery.isEmpty ||
                      _normalizeCategoryName(category.name)
                          .contains(normalizedQuery);
                  final visibleSubcategories = categoryMatchesQuery
                      ? activeSubcategories
                      : activeSubcategories
                          .where((subcategory) =>
                              _normalizeCategoryName(subcategory.name)
                                  .contains(normalizedQuery))
                          .toList();
                  final expanded = _expandedCategoryIds.contains(category.id) ||
                      (!categoryMatchesQuery &&
                          visibleSubcategories.isNotEmpty);

                  return Card(
                    key: ValueKey('category-${category.id}'),
                    margin: const EdgeInsets.only(bottom: 12),
                    color: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: const BorderSide(color: Color(0xFFE8DED0)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: colors[index % colors.length],
                            foregroundColor: const Color(0xFF1B120C),
                            child: Icon(icons[index % icons.length]),
                          ),
                          title: Text(
                            category.name,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle:
                              Text('${_categoryProductCount(category)} منتج'),
                          trailing: activeSubcategories.isEmpty
                              ? const Icon(Icons.chevron_left_rounded)
                              : IconButton(
                                  key: ValueKey(
                                    'expand-category-${category.id}',
                                  ),
                                  tooltip: expanded
                                      ? 'إخفاء الأقسام الفرعية'
                                      : 'عرض الأقسام الفرعية',
                                  onPressed: () {
                                    setState(() {
                                      if (expanded) {
                                        _expandedCategoryIds
                                            .remove(category.id);
                                      } else {
                                        _expandedCategoryIds.add(category.id);
                                      }
                                    });
                                  },
                                  icon: Icon(
                                    expanded
                                        ? Icons.expand_less_rounded
                                        : Icons.expand_more_rounded,
                                  ),
                                ),
                          onTap: () => _openCategory(category),
                        ),
                        if (expanded && visibleSubcategories.isNotEmpty)
                          const Divider(height: 1, indent: 16, endIndent: 16),
                        if (expanded)
                          for (final subcategory in visibleSubcategories)
                            ListTile(
                              key: ValueKey(
                                'subcategory-${category.id}-${subcategory.id}',
                              ),
                              dense: true,
                              contentPadding:
                                  const EdgeInsetsDirectional.fromSTEB(
                                24,
                                0,
                                16,
                                0,
                              ),
                              leading: const Icon(
                                Icons.subdirectory_arrow_left_rounded,
                                color: Color(0xFF9A7B1F),
                                size: 20,
                              ),
                              title: Text(subcategory.name),
                              subtitle: Text(
                                '${_subcategoryProductCount(category, subcategory)} منتج',
                              ),
                              trailing: const Icon(Icons.chevron_left_rounded),
                              onTap: () => _openCategory(
                                category,
                                subcategory: subcategory,
                              ),
                            ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoriesMessage({
    required IconData icon,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Column(
        children: [
          Icon(icon, size: 54, color: const Color(0xFF9CA3AF)),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF6B7280)),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(actionLabel),
            ),
          ],
        ],
      ),
    );
  }
}

class CustomerWishlistScreen extends StatelessWidget {
  const CustomerWishlistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wishlist = WishlistService.instance;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const CustomAppBar(
        title: 'المفضلة',
        icon: Icons.favorite_rounded,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            AnimatedBuilder(
              animation: wishlist,
              builder: (context, _) {
                if (wishlist.items.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.only(top: 70),
                      child: Text(
                        'لا توجد عناصر في المفضلة حالياً',
                        style:
                            TextStyle(fontSize: 16, color: Color(0xFF6B7280)),
                      ),
                    ),
                  );
                }

                return Column(
                  children: wishlist.items
                      .map((product) => _WishlistItem(product: product))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _WishlistItem extends StatelessWidget {
  const _WishlistItem({required this.product});

  final ProductModel product;

  @override
  Widget build(BuildContext context) {
    final imageProvider = MediaUploadService.imageProvider(product.imageUrl);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8DED0)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            Navigator.of(context).push(
              slideFadeRoute(
                page: ProductDetailFullScreen(product: product),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: 66,
                    height: 66,
                    color: const Color(0xFFF8F3DF),
                    child: imageProvider == null
                        ? const Icon(Icons.shopping_bag_rounded,
                            color: Color(0xFFB69449))
                        : Image(
                            image: imageProvider,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.shopping_bag_rounded,
                              color: Color(0xFFB69449),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(product.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 5),
                      Text(product.formatPrice(product.priceIncludingVat),
                          style: const TextStyle(
                              color: Color(0xFF9A7B2F),
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'إزالة من المفضلة',
                  onPressed: () {
                    WishlistService.instance.remove(product.id);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('تمت إزالة المنتج من المفضلة'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.favorite_rounded,
                      color: Color(0xFFB91C1C)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _ActionCard({
    required this.label,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 28, color: color),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: Color(0xFF1B120C),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _SortChip({
    required this.label,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1B120C) : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? const Color(0xFF1B120C) : const Color(0xFFE5E7EB),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF111827),
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _DashboardSummaryCard extends StatelessWidget {
  const _DashboardSummaryCard({
    required this.orderCount,
    required this.activeOrders,
    required this.totalSpent,
    required this.currencySymbol,
    required this.onTap,
  });

  final int orderCount;
  final int activeOrders;
  final double totalSpent;
  final String currencySymbol;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE8DED0)),
        ),
        child: Row(
          children: [
            const Icon(Icons.insights_rounded, color: Color(0xFF9A7B2F)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$orderCount طلب • $activeOrders نشط • ${totalSpent.toStringAsFixed(0)} $currencySymbol',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
            const Icon(Icons.chevron_left_rounded, color: Color(0xFF9CA3AF)),
          ],
        ),
      ),
    );
  }
}

class CustomerStatsScreen extends StatelessWidget {
  const CustomerStatsScreen({
    super.key,
    required this.orders,
    required this.totalSpentYER,
    required this.unconvertedOrderCount,
    required this.currencySymbol,
  });

  final List<OrderModel> orders;
  final double totalSpentYER;
  final int unconvertedOrderCount;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final activeOrders = orders
        .where((order) =>
            order.status != 'delivered' && order.status != 'cancelled')
        .length;
    return Scaffold(
      appBar: AppBar(title: const Text('ملخص الأداء')),
      backgroundColor: Colors.white,
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const Text(
              'ملخص مشترياتك',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            const Text(
              'أرقام محدثة من طلباتك المسجلة',
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                    child: _StatCard(
                        label: 'الطلبات',
                        value: '${orders.length}',
                        color: const Color(0xFF10B981),
                        icon: Icons.receipt_long_rounded)),
                const SizedBox(width: 12),
                Expanded(
                    child: _StatCard(
                        label: 'النشطة',
                        value: '$activeOrders',
                        color: const Color(0xFF3B82F6),
                        icon: Icons.local_shipping_rounded)),
              ],
            ),
            const SizedBox(height: 12),
            _StatCard(
                label: 'إجمالي الإنفاق',
                value: '${totalSpentYER.toStringAsFixed(0)} $currencySymbol',
                color: const Color(0xFFB69449),
                icon: Icons.account_balance_wallet_rounded,
                fullWidth: true),
            if (unconvertedOrderCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'لم تُحتسب قيمة $unconvertedOrderCount طلب لعدم توفر سعر صرف أو لتعدد عملات بنوده القديمة.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 20),
            const Text('ملاحظة',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: const Text(
                  'يتم احتساب الإجمالي من الطلبات المسجلة لدى حسابك فقط.',
                  style: TextStyle(color: Color(0xFF6B7280))),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  final bool fullWidth;

  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: fullWidth
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF4B5563),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1B120C),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
