import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:she_m_app/core/responsive.dart';
import 'package:she_m_app/data/models/product_model.dart';
import 'package:she_m_app/data/models/user_model.dart';
import 'package:she_m_app/data/services/catalog_service.dart';
import 'package:she_m_app/data/services/firebase_database_service.dart';
import 'package:she_m_app/presentation/admin/admin_dashboard_screen.dart';
import 'package:she_m_app/presentation/admin/admin_management_detail_screens.dart';
import 'package:she_m_app/presentation/cart/cart_screen.dart';
import 'package:she_m_app/presentation/driver/driver_registration_screen.dart';
import 'package:she_m_app/presentation/catalog/product_catalog.dart';
import 'package:she_m_app/presentation/dashboard/multi_role_dashboard.dart';
import 'package:she_m_app/presentation/delivery/delivery_tracking_screen.dart';
import 'package:she_m_app/presentation/orders/orders_screen.dart';
import 'package:she_m_app/presentation/profile/profile_screen.dart';
import 'package:she_m_app/core/animations/route_transitions.dart';

class MarketplaceDashboardScreen extends StatefulWidget {
  const MarketplaceDashboardScreen({
    super.key,
    this.catalogService,
    this.databaseService,
  });

  final CatalogService? catalogService;
  final DatabaseService? databaseService;

  @override
  State<MarketplaceDashboardScreen> createState() =>
      _MarketplaceDashboardScreenState();
}

class _MarketplaceDashboardScreenState
    extends State<MarketplaceDashboardScreen> {
  int _currentIndex = 0;
  bool _isAuthorized = false;
  late final CatalogService _catalogService =
      widget.catalogService ?? CatalogService();
  late final DatabaseService _databaseService =
      widget.databaseService ?? FirebaseDatabaseService.instance;

  late final List<Widget> _screens = [
    MarketplaceHomeView(
      catalogService: _catalogService,
      databaseService: _databaseService,
      ordersBottomNavigationBar:
          _buildBottomNavigationBar(forOrdersScreen: true),
    ),
    ProductCatalogScreen(),
    const CartScreen(),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    setState(() => _isAuthorized = true);
  }

  Widget _buildBottomNavigationBar({bool forOrdersScreen = false}) {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      currentIndex: forOrdersScreen ? 0 : _currentIndex,
      selectedItemColor: const Color(0xFFD4AF37),
      unselectedItemColor: const Color(0xFF6B7280),
      onTap: (index) {
        if (forOrdersScreen) {
          Navigator.of(context).pop();
        }
        setState(() => _currentIndex = index);
      },
      items: const [
        BottomNavigationBarItem(
            icon: Icon(Icons.home_rounded), label: 'الرئيسية'),
        BottomNavigationBarItem(
            icon: Icon(Icons.category_rounded), label: 'المنتجات'),
        BottomNavigationBarItem(
            icon: Icon(Icons.shopping_cart_rounded), label: 'السلة'),
        BottomNavigationBarItem(
            icon: Icon(Icons.person_rounded), label: 'حسابي'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAuthorized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

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
        body: IndexedStack(
          index: _currentIndex,
          children: _screens,
        ),
        bottomNavigationBar: _buildBottomNavigationBar(),
      ),
    );
  }
}

class MarketplaceHomeView extends StatefulWidget {
  const MarketplaceHomeView({
    super.key,
    this.catalogService,
    this.databaseService,
    this.ordersBottomNavigationBar,
  });

  final CatalogService? catalogService;
  final DatabaseService? databaseService;
  final Widget? ordersBottomNavigationBar;

  @override
  State<MarketplaceHomeView> createState() => _MarketplaceHomeViewState();
}

class _MarketplaceHomeViewState extends State<MarketplaceHomeView> {
  late final CatalogService _catalogService =
      widget.catalogService ?? CatalogService();
  late final DatabaseService _databaseService =
      widget.databaseService ?? FirebaseDatabaseService.instance;
  List<ProductModel> _products = const [];
  List<UserModel> _merchants = const [];
  int _customerCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    setState(() {
      _loading = false;
    });
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final products = await _catalogService.getProducts();
      final profilesSnapshot = await _databaseService.read('profiles');
      final merchants = <UserModel>[];
      var customerCount = 0;

      for (final entry in profilesSnapshot.entries) {
        final value = entry.value;
        if (value is! Map) continue;

        final map = Map<String, dynamic>.from(value);
        final merchant = UserModel.fromJson(map);
        if (merchant.role == 'customer') customerCount++;
        if (merchant.role == 'merchant' ||
            (merchant.shopName?.isNotEmpty ?? false) ||
            (merchant.shopCategory?.isNotEmpty ?? false)) {
          merchants.add(merchant);
        }
      }

      if (!mounted) return;
      setState(() {
        _products = products;
        _merchants = merchants;
        _customerCount = customerCount;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _products = const [];
        _merchants = const [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final statCards = [
      _StatCard(
        title: 'إجمالي المبيعات',
        value: _products.isEmpty
            ? '0'
            : _products.first.formatPrice(_products.fold<double>(
                0, (sum, product) => sum + product.priceIncludingVat)),
        color: Theme.of(context).colorScheme.primary,
        icon: Icons.trending_up_rounded,
      ),
      _StatCard(
        title: 'الطلبات',
        value: '${_products.length}',
        color: const Color(0xFF10B981),
        icon: Icons.shopping_bag_rounded,
      ),
      _StatCard(
        title: 'المتاجر',
        value: '${_merchants.length}',
        color: const Color(0xFF0EA5E9),
        icon: Icons.storefront_rounded,
      ),
      _StatCard(
        title: 'العملاء',
        value: '$_customerCount',
        color: const Color(0xFFF59E0B),
        icon: Icons.people_alt_rounded,
      ),
    ];

    final quickActions = [
      _QuickActionCard(
        title: 'إدارة المنتجات',
        icon: Icons.inventory_2_rounded,
        color: const Color(0xFF8B5CF6),
        onTap: () => Navigator.of(context).push(
          slideFadeRoute(page: ProductCatalogScreen()),
        ),
      ),
      _QuickActionCard(
        title: 'الطلبات',
        icon: Icons.receipt_long_rounded,
        color: const Color(0xFF10B981),
        onTap: () {
          Navigator.of(context).push(
            slideFadeRoute(
              page: OrdersScreen(
                bottomNavigationBar: widget.ordersBottomNavigationBar,
              ),
            ),
          );
        },
      ),
      _QuickActionCard(
        title: 'المحفظات',
        icon: Icons.wallet_rounded,
        color: const Color(0xFF3B82F6),
        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('إدارة المحافظ ستكون متاحة قريبًا')),
        ),
      ),
      _QuickActionCard(
        title: 'التسليم',
        icon: Icons.local_shipping_rounded,
        color: const Color(0xFFF59E0B),
        onTap: () {
          Navigator.of(context).push(
            slideFadeRoute(page: const DeliveryTrackingScreen()),
          );
        },
      ),
      _QuickActionCard(
        title: 'لوحة السائق',
        icon: Icons.delivery_dining_rounded,
        color: const Color(0xFF0EA5E9),
        onTap: () {
          Navigator.of(context).push(
            slideFadeRoute(page: const DriverDashboardScreen()),
          );
        },
      ),
      _QuickActionCard(
        title: 'تسجيل المندوب',
        icon: Icons.person_add_alt_rounded,
        color: const Color(0xFF7C3AED),
        onTap: () {
          Navigator.of(context).push(
            slideFadeRoute(page: const DriverRegistrationScreen()),
          );
        },
      ),
    ];

    final featuredProducts = _products.take(3).map((product) {
      return _ProductCard(
        name: product.name,
        price: product.formatPrice(product.priceIncludingVat),
        subtitle: product.category,
        color: const Color(0xFFEDE9FE),
        imageUrl: product.imageUrl,
      );
    }).toList();

    final paymentMethods = [
      'الدفع عند الاستلام',
      'محفظة جيب',
      'محفظة جوالي',
      'محفظة فلوسك',
      'كريمي',
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'She M',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'تسوق أذكى .. بأسلوب أسهل',
              style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
            ),
          ],
        ),
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF111111), Color(0xFF1E1B4B)],
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'مرحباً بك في She M',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'تسوق أذكى .. بأسلوب أسهل',
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFFE5E7EB),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4AF37).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.local_fire_department_rounded,
                      color: Color(0xFFD4AF37),
                      size: 28,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE5E7EB)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: const Row(
                children: [
                  Icon(Icons.search, color: Color(0xFF9CA3AF)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ابحث عن المنتجات، المتاجر، والعروض...',
                      style: TextStyle(color: Color(0xFF9CA3AF)),
                    ),
                  ),
                  Icon(Icons.tune_rounded, color: Color(0xFF9CA3AF)),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 92,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: List.generate(6, (index) {
                  final categories = [
                    'أزياء',
                    'إلكترونيات',
                    'للاطفال',
                    'المنزل',
                    'جمال',
                    'مكتبية'
                  ];
                  final icons = [
                    Icons.checkroom_rounded,
                    Icons.devices_rounded,
                    Icons.toys_rounded,
                    Icons.home_rounded,
                    Icons.spa_rounded,
                    Icons.book_rounded,
                  ];

                  return Container(
                    width: 84,
                    margin: const EdgeInsets.only(right: 12),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFF3F4F6)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.02),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              )
                            ],
                          ),
                          child: Icon(icons[index],
                              color: const Color(0xFF111827)),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          categories[index],
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(builder: (context, constraints) {
              final cols = Responsive.columnsForWidth(constraints.maxWidth,
                  mobile: 2, tablet: 3, desktop: 4);
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: cols,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: cols > 2 ? 1.5 : 1.35,
                children: statCards,
              );
            }),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('لوحة التحكم',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text('المزيد',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 132,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: quickActions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) => quickActions[index],
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              key: const ValueKey('delivery_tracking_action'),
              onPressed: () {
                Navigator.of(context).push(
                  slideFadeRoute(page: const DeliveryTrackingScreen()),
                );
              },
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                backgroundColor: const Color(0xFFD4AF37),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.local_shipping_rounded),
              label: const Text('التسليم'),
            ),
            const SizedBox(height: 24),
            const Text(
              'لوحة الإدارة',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 8,
                  )
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.admin_panel_settings_rounded,
                      color: Color(0xFFD4AF37)),
                  const SizedBox(width: 12),
                  const Expanded(
                      child: Text('لوحة الإدارة',
                          style: TextStyle(fontWeight: FontWeight.w700))),
                  TextButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          slideFadeRoute(page: const AdminDashboardScreen()),
                        );
                      },
                      child: const Text('فتح'))
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'المنتجات المميزة',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      slideFadeRoute(page: ProductCatalogScreen()),
                    );
                  },
                  child: const Text('عرض الكل'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              child: featuredProducts.isEmpty
                  ? const Center(
                      child: Text('لا توجد منتجات مميزة حاليًا'),
                    )
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemBuilder: (_, i) => SizedBox(
                        width: 240,
                        child: featuredProducts[i],
                      ),
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemCount: featuredProducts.length,
                    ),
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  slideFadeRoute(page: const MultiRoleDashboardScreen()),
                );
              },
              child: const Text(
                'طرق الدفع المتاحة',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'الدفع عند الاستلام',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827)),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: paymentMethods
                  .map(
                    (method) => ChoiceChip(
                      label: Text(method),
                      selected: method == 'الدفع عند الاستلام',
                      onSelected: (_) {},
                      selectedColor: const Color(0xFFE9D5FF),
                      labelStyle: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF0B0B0B),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'لوحة الإدارة المتكاملة',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'التجار • العملاء • الإدارة • التطوير \nبدون خدمات مدفوعة: الدفع عند الاستلام + المحافظ الإلكترونية + التكامل الذكي.',
                    style: TextStyle(color: Color(0xFFE5E7EB), height: 1.8),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final IconData icon;

  const _StatCard({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            offset: const Offset(0, 4),
            blurRadius: 12,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color),
              ),
              const Icon(Icons.arrow_upward_rounded, color: Color(0xFF10B981)),
            ],
          ),
          Text(
            value,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 120,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1F2937),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final String name;
  final String price;
  final String subtitle;
  final Color color;
  final String imageUrl;

  const _ProductCard({
    required this.name,
    required this.price,
    required this.subtitle,
    required this.color,
    this.imageUrl = '',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(18),
            ),
            child: imageUrl.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image(
                      image: CachedNetworkImageProvider(imageUrl),
                      width: 76,
                      height: 76,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.shopping_bag_rounded,
                        size: 32,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                  )
                : const Icon(Icons.shopping_bag_rounded,
                    size: 32, color: Color(0xFF1F2937)),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                Text(
                  price,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.primary,
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
