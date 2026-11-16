import 'package:flutter/material.dart';
import 'package:she_m_app/data/models/product_model.dart';
import 'package:she_m_app/data/services/cart_service.dart';

Future<bool> confirmCartAddition(
  BuildContext context,
  ProductModel product,
) async {
  final alreadyInCart =
      CartService.instance.items.any((item) => item.product.id == product.id);
  if (!alreadyInCart) return true;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('المنتج موجود في السلة'),
      content: const Text(
        'المنتج موجود مسبقاً في السلة. هل تريد إضافته مجدداً؟ '
        'ستؤدي الموافقة إلى زيادة الكمية.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('موافقة'),
        ),
      ],
    ),
  );

  return confirmed == true;
}

void showCartAddedSnackBar(
  BuildContext context, {
  required VoidCallback onOpenCart,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        duration: const Duration(seconds: 4),
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline_rounded, size: 18),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'تمت إضافة المنتج إلى السلة',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () {
                messenger.hideCurrentSnackBar();
                onOpenCart();
              },
              child: const Text(
                'فتح السلة',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
}

bool productInCart(ProductModel product) {
  return CartService.instance.items
      .any((item) => item.product.id == product.id);
}

String cartActionLabel(bool inCart) =>
    inCart ? 'موجود في السلة' : 'أضف إلى السلة';

IconData cartActionIcon(bool inCart) =>
    inCart ? Icons.check_rounded : Icons.add_shopping_cart_rounded;

Color cartActionColor(bool inCart) =>
    inCart ? const Color(0xFF16A34A) : const Color(0xFFD4AF37);
