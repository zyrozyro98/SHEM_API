import 'package:flutter/material.dart';
import 'package:she_m_app/core/theme/design_tokens.dart';
import 'package:she_m_app/data/models/product_model.dart';
import 'package:she_m_app/data/services/cart_service.dart';
import 'package:she_m_app/presentation/common/cart_interaction.dart';

class ProductCard extends StatelessWidget {
  final String name;
  final String category;
  final String price;
  final VoidCallback? onTap;
  final VoidCallback? onAddToCart;
  final ProductModel? product;

  const ProductCard(
      {super.key,
      required this.name,
      required this.category,
      required this.price,
      this.onTap,
      this.onAddToCart,
      this.product});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignTokens.radiusLarge),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: DesignTokens.surface,
          borderRadius: BorderRadius.circular(DesignTokens.radiusLarge),
          boxShadow: DesignTokens.elevatedShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 96,
              width: double.infinity,
              decoration: BoxDecoration(
                color: DesignTokens.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.shopping_bag_rounded,
                  size: 44, color: DesignTokens.primary),
            ),
            const SizedBox(height: 12),
            Text(
              category,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 6),
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const Spacer(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    price,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: DesignTokens.primary,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedBuilder(
                  animation: CartService.instance,
                  builder: (context, _) {
                    final inCart = product != null && productInCart(product!);
                    return Container(
                      decoration: BoxDecoration(
                        color: cartActionColor(inCart),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        tooltip: inCart
                            ? 'المنتج موجود في السلة'
                            : 'إضافة إلى السلة',
                        onPressed: onAddToCart ??
                            () => ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content:
                                        Text('اختر المنتج لإضافته إلى السلة'),
                                  ),
                                ),
                        padding: const EdgeInsets.all(6),
                        constraints:
                            const BoxConstraints(minWidth: 32, minHeight: 32),
                        icon: Icon(cartActionIcon(inCart), color: Colors.black),
                      ),
                    );
                  },
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
