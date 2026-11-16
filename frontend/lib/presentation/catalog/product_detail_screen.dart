import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:she_m_app/data/models/product_model.dart';
import 'package:she_m_app/data/services/cart_service.dart';
import 'package:she_m_app/data/services/media_upload_service.dart';
import 'package:she_m_app/data/services/wishlist_service.dart';
import 'package:she_m_app/presentation/cart/cart_screen.dart';
import 'package:she_m_app/core/animations/route_transitions.dart';
import 'package:she_m_app/presentation/common/cart_interaction.dart';
import 'package:she_m_app/presentation/common/custom_appbar.dart';
import 'package:she_m_app/presentation/common/product_media_fullscreen.dart';

class ProductDetailScreen extends StatelessWidget {
  final ProductModel? product;
  final String? productName;
  final String? price;
  final String? category;

  const ProductDetailScreen({
    super.key,
    this.product,
    this.productName,
    this.price,
    this.category,
  });

  ProductModel get _resolvedProduct {
    if (product != null) return product!;

    final resolvedName = productName ?? 'منتج';
    final resolvedCategory = category ?? 'عام';
    final resolvedPrice = price != null && price!.contains('ر.س')
        ? double.tryParse(price!.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0
        : double.tryParse(price ?? '0') ?? 0;

    return ProductModel(
      id: 'legacy-product',
      name: resolvedName,
      price: resolvedPrice,
      category: resolvedCategory,
      description: 'منتج عالي الجودة مصمم لتلبية احتياجاتك اليومية.',
      imageUrl: '',
      available: true,
      merchantId: 'legacy-merchant',
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeProduct = _resolvedProduct;
    final primary = Theme.of(context).colorScheme.primary;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: CustomAppBar(
          title: 'تفاصيل المنتج',
          icon: Icons.shopping_bag_rounded,
          actions: [
            AnimatedBuilder(
              animation: WishlistService.instance,
              builder: (context, _) {
                final isFavorite =
                    WishlistService.instance.contains(activeProduct.id);
                return IconButton(
                  tooltip:
                      isFavorite ? 'إزالة من المفضلة' : 'إضافة إلى المفضلة',
                  onPressed: () {
                    final isAdded =
                        WishlistService.instance.toggle(activeProduct);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(isAdded
                            ? 'تمت إضافة المنتج إلى المفضلة'
                            : 'تمت إزالة المنتج من المفضلة'),
                      ),
                    );
                  },
                  icon: Icon(
                    isFavorite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: isFavorite ? Colors.red : null,
                  ),
                );
              },
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [
                      primary.withValues(alpha: 0.12),
                      const Color(0xFFFFFFFF),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.topLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Text(
                          activeProduct.category,
                          style: TextStyle(
                            color: primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: primary.withValues(alpha: 0.18),
                            blurRadius: 22,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: activeProduct.imageUrl.isNotEmpty
                          ? GestureDetector(
                              key: const ValueKey('product-detail-image'),
                              onTap: () {
                                final provider = MediaUploadService.imageProvider(
                                  activeProduct.imageUrl,
                                );
                                if (provider != null) {
                                  showProductImageFullscreen(context, provider);
                                }
                              },
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: ClipOval(
                                      child: MediaUploadService.isDataUri(
                                              activeProduct.imageUrl)
                                          ? Image.memory(
                                              MediaUploadService
                                                  .decodeDataUriToBytes(
                                                activeProduct.imageUrl,
                                              )!,
                                              width: 150,
                                              height: 150,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  Icon(
                                                Icons.shopping_bag_rounded,
                                                size: 78,
                                                color: primary,
                                              ),
                                            )
                                          : Image(
                                              image: CachedNetworkImageProvider(
                                                activeProduct.imageUrl,
                                              ),
                                              width: 150,
                                              height: 150,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  Icon(
                                                Icons.shopping_bag_rounded,
                                                size: 78,
                                                color: primary,
                                              ),
                                            ),
                                    ),
                                  ),
                                  const Positioned(
                                    bottom: 8,
                                    left: 8,
                                    child: Icon(
                                      Icons.open_in_full_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Icon(
                              Icons.shopping_bag_rounded,
                              size: 78,
                              color: primary,
                            ),
                    ),
                    const SizedBox(height: 18),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _TinyBadge(label: '4.9', icon: Icons.star_rounded),
                        SizedBox(width: 10),
                        _TinyBadge(
                            label: 'توصيل سريع',
                            icon: Icons.local_shipping_rounded),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      activeProduct.name,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'متوفر الآن',
                      style: TextStyle(
                        color: primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                activeProduct.formatPrice(activeProduct.priceIncludingVat),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: primary,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'الوصف',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      activeProduct.description.isNotEmpty
                          ? activeProduct.description
                          : 'منتج عالي الجودة مصمم لتلبية احتياجاتك اليومية مع تصميم أنيق، أداء موثوق، وتجربة استخدام مريحة ومناسبة للمنزل والعمل.',
                      style: const TextStyle(
                        height: 1.8,
                        color: Color(0xFF4B5563),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'المميزات',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const _FeatureRow(
                  icon: Icons.battery_charging_full_rounded,
                  label: 'بطارية تدوم طويلاً'),
              const _FeatureRow(
                  icon: Icons.bluetooth_connected_rounded,
                  label: 'اتصال لاسلكي سريع'),
              const _FeatureRow(
                  icon: Icons.shield_rounded, label: 'ضمان شامل لمدة عام'),
              const _FeatureRow(
                  icon: Icons.sync_rounded, label: 'إرجاع سهل خلال 7 أيام'),
              const SizedBox(height: 26),
              AnimatedBuilder(
                animation: CartService.instance,
                builder: (context, _) {
                  final alreadyInCart = productInCart(activeProduct);
                  final buttonColor = cartActionColor(alreadyInCart);

                  return SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        if (alreadyInCart) {
                          Navigator.of(context).push(
                            slideFadeRoute(page: const CartScreen()),
                          );
                          return;
                        }

                        if (!await confirmCartAddition(
                                context, activeProduct) ||
                            !context.mounted) {
                          return;
                        }
                        CartService.instance.addProduct(activeProduct);
                        Navigator.of(context).push(
                          slideFadeRoute(page: const CartScreen()),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        backgroundColor: buttonColor,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        elevation: 0,
                      ),
                      icon: Icon(cartActionIcon(alreadyInCart)),
                      label: Text(
                        cartActionLabel(alreadyInCart),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TinyBadge extends StatelessWidget {
  final String label;
  final IconData icon;

  const _TinyBadge({
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFFD4AF37)),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeatureRow({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon,
                color: Theme.of(context).colorScheme.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF374151),
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
