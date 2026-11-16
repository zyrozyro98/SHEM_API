import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:she_m_app/core/animations/route_transitions.dart';
import 'package:she_m_app/data/models/product_model.dart';
import 'package:she_m_app/data/models/user_model.dart';
import 'package:she_m_app/data/services/media_upload_service.dart';
import 'package:she_m_app/presentation/catalog/product_detail_screen_full.dart';

class StoreDetailScreen extends StatefulWidget {
  final UserModel merchant;
  final List<ProductModel> products;

  const StoreDetailScreen({
    super.key,
    required this.merchant,
    this.products = const [],
  });

  @override
  State<StoreDetailScreen> createState() => _StoreDetailScreenState();
}

class _StoreDetailScreenState extends State<StoreDetailScreen> {
  static const int _pageSize = 12;

  final ScrollController _scrollController = ScrollController();
  int _visibleCount = _pageSize;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    if (position.extentAfter < 300) {
      final maxVisible = widget.products.length;
      if (_visibleCount >= maxVisible) return;

      setState(() {
        _visibleCount = (_visibleCount + _pageSize).clamp(0, maxVisible);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayProducts =
        widget.products.isNotEmpty ? widget.products : const <ProductModel>[];
    final visibleProducts = displayProducts.take(_visibleCount).toList();
    final hasMore = _visibleCount < displayProducts.length;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المنتجات'),
        ),
        body: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.extentAfter < 300 &&
                !notification.metrics.outOfRange) {
              _handleScroll();
            }
            return false;
          },
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 30),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF8F3DF), Color(0xFFFFFFFF)],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFFE7DCC3)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.shopping_bag_rounded,
                        size: 34,
                        color: Color(0xFFD4AF37),
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        'منتجاتنا',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'المنتجات',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              if (displayProducts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text('لا توجد منتجات في هذا المتجر حاليًا'),
                  ),
                )
              else ...[
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: visibleProducts.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.78,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemBuilder: (context, index) {
                    final product = visibleProducts[index];
                    return InkWell(
                      onTap: () {
                        Navigator.of(context).push(
                          slideFadeRoute(
                            page: ProductDetailFullScreen(product: product),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 90,
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
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: product.imageUrl.isNotEmpty
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: MediaUploadService.isDataUri(
                                              product.imageUrl)
                                          ? Image.memory(
                                              MediaUploadService
                                                  .decodeDataUriToBytes(
                                                product.imageUrl,
                                              )!,
                                              width: double.infinity,
                                              height: double.infinity,
                                              fit: BoxFit.cover,
                                              alignment: Alignment.center,
                                              errorBuilder: (_, __, ___) =>
                                                  Center(
                                                child: Icon(
                                                  Icons.shopping_bag_rounded,
                                                  size: 36,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary,
                                                ),
                                              ),
                                            )
                                          : Image(
                                              image: CachedNetworkImageProvider(
                                                product.imageUrl,
                                              ),
                                              width: double.infinity,
                                              height: double.infinity,
                                              fit: BoxFit.cover,
                                              alignment: Alignment.center,
                                              errorBuilder: (_, __, ___) =>
                                                  Center(
                                                child: Icon(
                                                  Icons.shopping_bag_rounded,
                                                  size: 36,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary,
                                                ),
                                              ),
                                            ),
                                    )
                                  : Center(
                                      child: Icon(
                                        Icons.shopping_bag_rounded,
                                        size: 36,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                    ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              product.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              product.formatPrice(product.priceIncludingVat),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                if (hasMore)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        'جاري تحميل المزيد...',
                        style: TextStyle(
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
