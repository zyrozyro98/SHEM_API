import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:she_m_app/core/animations/route_transitions.dart';
import 'package:she_m_app/presentation/common/custom_appbar.dart';
import 'package:she_m_app/core/responsive.dart';
import 'package:she_m_app/data/models/product_model.dart';
import 'package:she_m_app/data/services/cart_service.dart';
import 'package:she_m_app/data/services/catalog_service.dart';
import 'package:she_m_app/data/services/media_upload_service.dart';
import 'package:she_m_app/data/services/search_history_service.dart';
import 'package:she_m_app/data/services/wishlist_service.dart';
import 'package:she_m_app/presentation/cart/cart_screen.dart';
import 'package:she_m_app/presentation/catalog/product_detail_screen_full.dart';
import 'package:she_m_app/presentation/common/cart_interaction.dart';

class ProductCatalogScreen extends StatefulWidget {
  ProductCatalogScreen({
    super.key,
    CatalogService? catalogService,
    this.initialQuery = '',
    this.autofocusSearch = false,
    this.searchHistoryUserId,
    this.initialProducts,
    this.reloadInitialProducts,
    this.categoryName,
    SearchHistoryStore? searchHistoryStore,
  })  : _catalogService = catalogService ?? CatalogService(),
        _searchHistoryStore =
            searchHistoryStore ?? const SecureSearchHistoryStore();

  final CatalogService _catalogService;
  final String initialQuery;
  final bool autofocusSearch;
  final String? searchHistoryUserId;
  final List<ProductModel>? initialProducts;
  final Future<List<ProductModel>> Function()? reloadInitialProducts;
  final String? categoryName;
  final SearchHistoryStore _searchHistoryStore;

  @override
  State<ProductCatalogScreen> createState() => _ProductCatalogScreenState();
}

class _ProductCatalogScreenState extends State<ProductCatalogScreen>
    with WidgetsBindingObserver {
  static const int _pageSize = 12;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final List<ProductModel> _products = <ProductModel>[];
  String _searchQuery = '';
  String _sortMode = 'newest';
  int _visibleCount = _pageSize;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  List<String> _recentSearches = const [];
  String? _lastLoadedProductKey;

  CatalogService get _catalogService => widget._catalogService;
  SearchHistoryStore get _searchHistoryStore => widget._searchHistoryStore;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _searchQuery = widget.initialQuery;
    _searchController.text = widget.initialQuery;
    _loadSearchHistory();
    _loadProducts();
    _scrollController.addListener(_handleScroll);
    if (widget.autofocusSearch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocusNode.requestFocus();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isLoading) {
      _loadProducts(forceRefresh: true);
    }
  }

  Future<void> _loadProducts({bool forceRefresh = false}) async {
    if (forceRefresh) {
      setState(() {
        _isLoading = true;
        _isLoadingMore = false;
      });
    }
    try {
      final scopedProducts = widget.initialProducts;
      if (scopedProducts != null) {
        final products = forceRefresh && widget.reloadInitialProducts != null
            ? await widget.reloadInitialProducts!()
            : scopedProducts;
        if (!mounted) return;
        setState(() {
          _products
            ..clear()
            ..addAll(products);
          _visibleCount = _products.length;
          _lastLoadedProductKey = null;
          _hasMore = false;
          _isLoading = false;
          _isLoadingMore = false;
        });
        return;
      }

      final page = await _catalogService.getProductCatalogPageAfter(
        limit: _pageSize,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _products
          ..clear()
          ..addAll(page.products);
        _visibleCount = _pageSize;
        _lastLoadedProductKey = page.nextCursor;
        _hasMore = page.hasMore;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _products.clear();
        _visibleCount = 0;
        _hasMore = false;
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  String get _historyUserId {
    final userId = widget.searchHistoryUserId?.trim() ?? '';
    return userId.isEmpty ? 'guest' : userId;
  }

  Future<void> _loadSearchHistory() async {
    final searches = await _searchHistoryStore.load(_historyUserId);
    if (!mounted) return;
    setState(() => _recentSearches = searches);
  }

  Future<void> _recordSearch(String query) async {
    if (query.trim().isEmpty) return;
    final searches = await _searchHistoryStore.addSearch(_historyUserId, query);
    if (!mounted) return;
    setState(() => _recentSearches = searches);
  }

  Future<void> _clearSearchHistory() async {
    await _searchHistoryStore.clear(_historyUserId);
    if (!mounted) return;
    setState(() => _recentSearches = const []);
  }

  void _applyRecentSearch(String query) {
    _searchController.text = query;
    setState(() {
      _searchQuery = query;
      _visibleCount = _pageSize;
      _isLoadingMore = false;
    });
  }

  List<ProductModel> _filteredProducts(List<ProductModel> products) {
    final query = _searchQuery.trim().toLowerCase();
    final filtered = query.isEmpty
        ? List<ProductModel>.from(products)
        : products.where((product) {
            final haystack = [
              product.name,
              product.category,
              product.mainCategory,
              product.subcategory,
            ].join(' ').toLowerCase();
            return haystack.contains(query);
          }).toList();

    switch (_sortMode) {
      case 'price_asc':
        filtered.sort((a, b) => a.price.compareTo(b.price));
        break;
      case 'price_desc':
        filtered.sort((a, b) => b.price.compareTo(a.price));
        break;
      case 'name':
        filtered.sort((a, b) => a.name.compareTo(b.name));
        break;
      case 'newest':
      default:
        filtered.sort(ProductModel.compareNewestFirst);
        break;
    }

    return filtered;
  }

  void _handleScroll() {
    if (!_scrollController.hasClients || _isLoadingMore || !_hasMore) return;

    final position = _scrollController.position;
    final isNearEnd = position.atEdge ||
        position.pixels >= position.maxScrollExtent - 200 ||
        position.extentAfter <= 600;

    if (!isNearEnd) return;

    setState(() => _isLoadingMore = true);
    _loadMoreProducts();
  }

  Future<void> _loadMoreProducts() async {
    if (widget.initialProducts != null) {
      setState(() {
        _visibleCount =
            (_visibleCount + _pageSize).clamp(0, _products.length);
        _hasMore = _visibleCount < _products.length;
        _isLoadingMore = false;
      });
      return;
    }

    try {
      final page = await _catalogService.getProductCatalogPageAfter(
        startAfter: _lastLoadedProductKey,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        final loadedIds = _products.map((product) => product.id).toSet();
        _products.addAll(
          page.products.where((product) => loadedIds.add(product.id)),
        );
        _visibleCount = _products.length;
        _lastLoadedProductKey = page.nextCursor;
        _hasMore = page.hasMore;
        _isLoadingMore = false;
      });
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'product catalog',
          context: ErrorDescription('while loading the next product page'),
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredProducts = _filteredProducts(_products);
    final visibleProducts = filteredProducts.take(_visibleCount).toList();
    final hasMore = _hasMore;
    final showLoadingIndicator = hasMore && _isLoadingMore;

    return Scaffold(
      appBar: CustomAppBar(
        title: widget.categoryName?.trim().isNotEmpty == true
            ? widget.categoryName!.trim()
            : 'المنتجات',
        icon: Icons.category_rounded,
        actions: [
          IconButton(
            key: const ValueKey('refresh_product_catalog'),
            tooltip: 'تحديث المنتجات',
            onPressed:
                _isLoading ? null : () => _loadProducts(forceRefresh: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE8DED0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded, color: Color(0xFF6B7280)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('product_search_field'),
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        textDirection: TextDirection.rtl,
                        textInputAction: TextInputAction.search,
                        onSubmitted: _recordSearch,
                        onChanged: (value) {
                          setState(() {
                            _searchQuery = value;
                            _visibleCount = _pageSize;
                            _isLoadingMore = false;
                          });
                        },
                        decoration: const InputDecoration(
                          hintText: 'ابحث عن منتج',
                          border: InputBorder.none,
                          hintStyle: TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    if (_searchQuery.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                            _visibleCount = _pageSize;
                          });
                        },
                        child: const Icon(
                          Icons.close_rounded,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_recentSearches.isNotEmpty && _searchQuery.trim().isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'عمليات البحث السابقة',
                            style: TextStyle(
                              color: Color(0xFF1B120C),
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          key: const ValueKey('clear_search_history'),
                          onPressed: _clearSearchHistory,
                          icon: const Icon(Icons.delete_outline_rounded,
                              size: 17),
                          label: const Text('مسح'),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (var index = 0;
                            index < _recentSearches.length;
                            index++)
                          ActionChip(
                            key: ValueKey('recent_search_$index'),
                            avatar: const Icon(Icons.history_rounded, size: 17),
                            label: Text(
                              _recentSearches[index],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onPressed: () =>
                                _applyRecentSearch(_recentSearches[index]),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _SortChip(
                    label: 'الأحدث',
                    selected: _sortMode == 'newest',
                    onTap: () => setState(() {
                      _sortMode = 'newest';
                      _visibleCount = _pageSize;
                    }),
                  ),
                  _SortChip(
                    label: 'الأرخص',
                    selected: _sortMode == 'price_asc',
                    onTap: () => setState(() {
                      _sortMode = 'price_asc';
                      _visibleCount = _pageSize;
                    }),
                  ),
                  _SortChip(
                    label: 'الأغلى',
                    selected: _sortMode == 'price_desc',
                    onTap: () => setState(() {
                      _sortMode = 'price_desc';
                      _visibleCount = _pageSize;
                    }),
                  ),
                  _SortChip(
                    label: 'الاسم',
                    selected: _sortMode == 'name',
                    onTap: () => setState(() {
                      _sortMode = 'name';
                      _visibleCount = _pageSize;
                    }),
                  ),
                ],
              ),
            ),
            if (_isLoading)
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              )
            else if (filteredProducts.isEmpty)
              const Expanded(
                child: Center(
                  child: Text('لا توجد منتجات مطابقة لبحثك'),
                ),
              )
            else
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final cols = Responsive.columnsForWidth(
                      constraints.maxWidth,
                      mobile: 2,
                      tablet: 3,
                      desktop: 4,
                    );

                    return GridView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: visibleProducts.length +
                          (showLoadingIndicator ? 1 : 0),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        mainAxisExtent: constraints.maxWidth < 600 ? 260 : 270,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemBuilder: (context, index) {
                        if (index >= visibleProducts.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          );
                        }

                        final product = visibleProducts[index];
                        final productPrice =
                            product.formatPrice(product.priceIncludingVat);

                        return InkWell(
                          onTap: () async {
                            await _recordSearch(_searchQuery);
                            if (!context.mounted) return;
                            Navigator.of(context).push(
                              slideFadeRoute(
                                page: ProductDetailFullScreen(product: product),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(22),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(22),
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
                                  height: 88,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: 0.12),
                                        const Color(0xFFF8F3DF),
                                      ],
                                      begin: Alignment.topRight,
                                      end: Alignment.bottomLeft,
                                    ),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: Stack(
                                    children: [
                                      Positioned(
                                        top: 10,
                                        left: 10,
                                        child: AnimatedBuilder(
                                          animation: WishlistService.instance,
                                          builder: (context, _) {
                                            final isFavorite = WishlistService
                                                .instance
                                                .contains(product.id);
                                            return IconButton(
                                              tooltip: isFavorite
                                                  ? 'إزالة من المفضلة'
                                                  : 'إضافة إلى المفضلة',
                                              onPressed: () {
                                                final isAdded = WishlistService
                                                    .instance
                                                    .toggle(product);
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                    content: Text(isAdded
                                                        ? 'تمت إضافة المنتج إلى المفضلة'
                                                        : 'تمت إزالة المنتج من المفضلة'),
                                                  ),
                                                );
                                              },
                                              style: IconButton.styleFrom(
                                                backgroundColor: Colors.white,
                                                minimumSize: const Size(28, 28),
                                                padding: EdgeInsets.zero,
                                              ),
                                              icon: Icon(
                                                isFavorite
                                                    ? Icons.favorite_rounded
                                                    : Icons
                                                        .favorite_border_rounded,
                                                size: 16,
                                                color: isFavorite
                                                    ? const Color(0xFFB91C1C)
                                                    : const Color(0xFF111827),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                      Positioned.fill(
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(18),
                                          child: product.imageUrl.isNotEmpty
                                              ? (MediaUploadService.isDataUri(
                                                      product.imageUrl)
                                                  ? Image.memory(
                                                      MediaUploadService
                                                          .decodeDataUriToBytes(
                                                        product.imageUrl,
                                                      )!,
                                                      width: double.infinity,
                                                      height: double.infinity,
                                                      fit: BoxFit.cover,
                                                      errorBuilder:
                                                          (_, __, ___) =>
                                                              Center(
                                                        child: Icon(
                                                          Icons
                                                              .shopping_bag_rounded,
                                                          size: 42,
                                                          color:
                                                              Theme.of(context)
                                                                  .colorScheme
                                                                  .primary,
                                                        ),
                                                      ),
                                                    )
                                                  : Image(
                                                      image:
                                                          CachedNetworkImageProvider(
                                                        product.imageUrl,
                                                      ),
                                                      width: double.infinity,
                                                      height: double.infinity,
                                                      fit: BoxFit.cover,
                                                      errorBuilder:
                                                          (_, __, ___) =>
                                                              Center(
                                                        child: Icon(
                                                          Icons
                                                              .shopping_bag_rounded,
                                                          size: 42,
                                                          color:
                                                              Theme.of(context)
                                                                  .colorScheme
                                                                  .primary,
                                                        ),
                                                      ),
                                                    ))
                                              : Center(
                                                  child: Icon(
                                                    Icons.shopping_bag_rounded,
                                                    size: 42,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .primary,
                                                  ),
                                                ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  product.category,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: const Color(0xFF6B7280),
                                        fontSize: 12,
                                      ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  product.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontSize: 15),
                                ),
                                const SizedBox(height: 6),
                                const SizedBox(height: 8),
                                const Row(
                                  children: [
                                    Icon(Icons.star_rounded,
                                        size: 14, color: Color(0xFFD4AF37)),
                                    SizedBox(width: 4),
                                    Text(
                                      '4.9',
                                      style: TextStyle(
                                        color: Color(0xFF111827),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                AnimatedBuilder(
                                  animation: CartService.instance,
                                  builder: (context, _) {
                                    final alreadyInCart =
                                        productInCart(product);
                                    final buttonColor =
                                        cartActionColor(alreadyInCart);

                                    return Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            productPrice,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          decoration: BoxDecoration(
                                            color: buttonColor,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: IconButton(
                                            onPressed: () async {
                                              if (alreadyInCart) {
                                                Navigator.of(context).push(
                                                  slideFadeRoute(
                                                    page: const CartScreen(),
                                                  ),
                                                );
                                                return;
                                              }

                                              if (product.colors.isNotEmpty) {
                                                Navigator.of(context).push(
                                                  slideFadeRoute(
                                                    page:
                                                        ProductDetailFullScreen(
                                                      product: product,
                                                    ),
                                                  ),
                                                );
                                                return;
                                              }
                                              if (!await confirmCartAddition(
                                                      context, product) ||
                                                  !context.mounted) {
                                                return;
                                              }
                                              CartService.instance
                                                  .addProduct(product);
                                              Navigator.of(context).push(
                                                slideFadeRoute(
                                                  page: const CartScreen(),
                                                ),
                                              );
                                            },
                                            icon: Icon(
                                              cartActionIcon(alreadyInCart),
                                              color: Colors.black,
                                            ),
                                            constraints: const BoxConstraints(
                                              minWidth: 32,
                                              minHeight: 32,
                                            ),
                                            padding: const EdgeInsets.all(6),
                                            tooltip: alreadyInCart
                                                ? 'المنتج موجود في السلة'
                                                : 'إضافة إلى السلة',
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

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
