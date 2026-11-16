import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:she_m_app/core/animations/route_transitions.dart';
import 'package:she_m_app/data/models/product_model.dart';
import 'package:she_m_app/data/services/cart_service.dart';
import 'package:she_m_app/data/services/auth_service.dart';
import 'package:she_m_app/data/services/media_upload_service.dart';
import 'package:she_m_app/data/services/wishlist_service.dart';
import 'package:she_m_app/data/services/rating_service.dart';
import 'package:she_m_app/presentation/cart/cart_screen.dart';
import 'package:she_m_app/presentation/catalog/product_catalog.dart';
import 'package:she_m_app/presentation/common/cart_interaction.dart';
import 'package:she_m_app/presentation/common/custom_appbar.dart';
import 'package:she_m_app/presentation/common/product_color_selector.dart';
import 'package:she_m_app/presentation/common/product_media_fullscreen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

class ProductDetailFullScreen extends StatefulWidget {
  const ProductDetailFullScreen({
    super.key,
    required this.product,
  });

  final ProductModel product;

  @override
  State<ProductDetailFullScreen> createState() =>
      _ProductDetailFullScreenState();
}

class _ProductDetailFullScreenState extends State<ProductDetailFullScreen> {
  int _quantity = 1;
  int _selectedGalleryIndex = 0;
  double _galleryDragDistance = 0;
  bool _gallerySwipeHandled = false;
  late final PageController _galleryPageController;
  String _selectedColor = '';
  String _selectedSize = 'M';
  bool _isVideoSelected = false;
  bool _isVideoLoading = false;
  String? _videoError;
  VideoPlayerController? _videoController;
  final List<_ProductVariantSelection> _variantSelections = [];
  ProductRatingSummary _rating =
      const ProductRatingSummary(average: 0, count: 0);

  List<String> get _availableColors => widget.product.colors;

  List<String> get _availableSizes => !widget.product.hasSizes
      ? const []
      : widget.product.sizes.isEmpty
          ? const ['S', 'M', 'L', 'XL']
          : widget.product.sizes;

  List<String> get _galleryImages {
    final unique = <String>[];
    final seen = <String>{};
    final sources = [widget.product.imageUrl, ...widget.product.imageUrls];

    for (final source in sources) {
      final value = source.trim();
      if (value.isEmpty || !seen.add(value)) continue;
      unique.add(value);
    }

    return unique;
  }

  @override
  void initState() {
    super.initState();
    _selectedGalleryIndex = _galleryImages.isNotEmpty ? 0 : -1;
    _galleryPageController = PageController();
    _selectedColor = _availableColors.isEmpty ? '' : _availableColors.first;
    _selectedSize = _availableSizes.isEmpty
        ? ''
        : _availableSizes.contains('M')
            ? 'M'
            : _availableSizes.first;
    _variantSelections.add(
      _ProductVariantSelection(color: _selectedColor, size: _selectedSize),
    );
    _loadRating();
  }

  void _setQuantity(int quantity) {
    final nextQuantity = quantity.clamp(1, 99);
    setState(() {
      while (_variantSelections.length < nextQuantity) {
        _variantSelections.add(
          _ProductVariantSelection(
            color: _selectedColor,
            size: _selectedSize,
          ),
        );
      }
      if (_variantSelections.length > nextQuantity) {
        _variantSelections.removeRange(
          nextQuantity,
          _variantSelections.length,
        );
      }
      _quantity = nextQuantity;
    });
  }

  bool _addConfiguredProductToCart() {
    var wasAlreadyInCart = false;
    for (final selection in _variantSelections) {
      wasAlreadyInCart = CartService.instance.addProduct(
            widget.product,
            color: selection.color.isEmpty ? null : selection.color,
            size: selection.size.isEmpty ? null : selection.size,
          ) ||
          wasAlreadyInCart;
    }
    return wasAlreadyInCart;
  }

  Future<void> _loadRating() async {
    final rating = await RatingService().getSummary(widget.product.id);
    if (mounted) setState(() => _rating = rating);
  }

  Future<void> _selectVideo() async {
    setState(() => _isVideoSelected = true);
    if (_videoController != null || _isVideoLoading) return;

    final uri = Uri.tryParse(widget.product.videoUrl.trim());
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      setState(() => _videoError = 'رابط الفيديو غير صالح');
      return;
    }

    setState(() {
      _isVideoLoading = true;
      _videoError = null;
    });
    final controller = VideoPlayerController.networkUrl(uri);
    _videoController = controller;

    try {
      await controller.initialize();
      await controller.setLooping(true);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _isVideoLoading = false);
    } catch (error, stackTrace) {
      debugPrint('Could not initialize product video: $error');
      debugPrintStack(stackTrace: stackTrace);
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _videoController = null;
        _isVideoLoading = false;
        _videoError = 'تعذر تشغيل معاينة الفيديو';
      });
    }
  }

  void _selectImages({int? index}) {
    _videoController?.pause();
    setState(() {
      _isVideoSelected = false;
      if (index != null) _selectedGalleryIndex = index;
    });
    if (index != null && _galleryPageController.hasClients) {
      _galleryPageController.jumpToPage(index);
    }
  }

  void _handleGallerySwipeStart(DragStartDetails details) {
    _galleryDragDistance = 0;
    _gallerySwipeHandled = false;
  }

  void _selectColor(String color, {_ProductVariantSelection? selection}) {
    setState(() {
      if (selection == null) {
        _selectedColor = color;
        _variantSelections[0].color = color;
      } else {
        selection.color = color;
      }
    });

    final imageUrl = widget.product.colorImageUrls[color]?.trim();
    final imageIndex = imageUrl == null ? -1 : _galleryImages.indexOf(imageUrl);
    if (imageIndex >= 0 && _galleryPageController.hasClients) {
      _galleryPageController.animateToPage(
        imageIndex,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    }
  }

  void _handleGallerySwipeUpdate(DragUpdateDetails details) {
    if (_galleryImages.length < 2 ||
        _gallerySwipeHandled ||
        !_galleryPageController.hasClients) {
      return;
    }
    _galleryDragDistance += details.primaryDelta ?? 0;
    if (_galleryDragDistance.abs() < 50) return;
    _gallerySwipeHandled = true;
    final direction = _galleryDragDistance > 0 ? 1 : -1;
    final nextPage =
        (_selectedGalleryIndex + direction).clamp(0, _galleryImages.length - 1);
    if (nextPage == _selectedGalleryIndex) return;
    _galleryPageController.animateToPage(
      nextPage,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  Future<void> _toggleVideoPlayback() async {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
    if (mounted) setState(() {});
  }

  Future<void> _openVideoExternally() async {
    final uri = Uri.tryParse(widget.product.videoUrl.trim());
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return;
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح رابط الفيديو')),
      );
    }
  }

  Widget _buildVideoPreview() {
    final controller = _videoController;
    if (_videoError != null) {
      return _VideoPreviewMessage(
        icon: Icons.videocam_off_outlined,
        message: _videoError!,
        action: TextButton.icon(
          onPressed: _openVideoExternally,
          icon: const Icon(Icons.open_in_new_rounded),
          label: const Text('فتح الفيديو خارج التطبيق'),
        ),
      );
    }
    if (_isVideoLoading ||
        controller == null ||
        !controller.value.isInitialized) {
      return const _VideoPreviewMessage(
        icon: Icons.movie_outlined,
        message: 'جارٍ تحميل معاينة الفيديو',
        action: CircularProgressIndicator(color: Colors.white),
      );
    }

    final aspectRatio = controller.value.aspectRatio > 0
        ? controller.value.aspectRatio
        : 16 / 9;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(controller),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                key: const ValueKey('product-video-fullscreen'),
                tooltip: 'عرض الفيديو بملء الشاشة',
                onPressed: () => showProductVideoFullscreen(
                  context,
                  controller: controller,
                ),
                color: Colors.white,
                icon: const Icon(Icons.open_in_full_rounded),
              ),
            ),
            if (!controller.value.isPlaying)
              IconButton.filled(
                tooltip: 'تشغيل الفيديو',
                onPressed: _toggleVideoPlayback,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withValues(alpha: 0.62),
                  foregroundColor: Colors.white,
                  fixedSize: const Size(58, 58),
                ),
                icon: const Icon(Icons.play_arrow_rounded, size: 34),
              ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 4,
              child: Row(
                children: [
                  IconButton(
                    tooltip: controller.value.isPlaying
                        ? 'إيقاف مؤقت'
                        : 'تشغيل الفيديو',
                    onPressed: _toggleVideoPlayback,
                    color: Colors.white,
                    icon: Icon(
                      controller.value.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                  ),
                  Expanded(
                    child: VideoProgressIndicator(
                      controller,
                      allowScrubbing: true,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      colors: const VideoProgressColors(
                        playedColor: Color(0xFFD4AF37),
                        bufferedColor: Color(0x99FFFFFF),
                        backgroundColor: Color(0x55FFFFFF),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    final controller = _videoController;
    if (controller != null) unawaited(controller.dispose());
    _galleryPageController.dispose();
    super.dispose();
  }

  Widget _buildImageContent(String? value, {double? width, double? height}) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) {
      return Icon(
        Icons.shopping_bag_rounded,
        size: width != null && width < 120 ? 40 : 88,
        color: Theme.of(context).colorScheme.primary,
      );
    }

    final imageProvider = MediaUploadService.imageProvider(normalized);
    if (imageProvider == null) {
      return Icon(
        Icons.shopping_bag_rounded,
        size: width != null && width < 120 ? 40 : 88,
        color: Theme.of(context).colorScheme.primary,
      );
    }

    return Image(
      image: imageProvider,
      width: width,
      height: height,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Icon(
        Icons.shopping_bag_rounded,
        size: width != null && width < 120 ? 40 : 88,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final primary = Theme.of(context).colorScheme.primary;
    final subtotal = product.priceIncludingVat * _quantity;
    final hasVideoLink = product.videoUrl.trim().isNotEmpty;
    final galleryImages = _galleryImages;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: CustomAppBar(
          title: 'تفاصيل المنتج',
          icon: Icons.shopping_bag_rounded,
          actions: [
            IconButton(
              key: const ValueKey('product-detail-search'),
              tooltip: 'البحث عن منتج',
              onPressed: () {
                Navigator.of(context).push(
                  slideFadeRoute(
                    page: ProductCatalogScreen(autofocusSearch: true),
                  ),
                );
              },
              icon: const Icon(Icons.search_rounded),
            ),
            IconButton(
              key: const ValueKey('product-detail-share'),
              tooltip: 'مشاركة المنتج',
              onPressed: _showShareProductSheet,
              icon: const Icon(Icons.share_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      height: 320,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        gradient: LinearGradient(
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                          colors: [
                            primary.withValues(alpha: 0.14),
                            const Color(0xFFFFFFFF),
                          ],
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x0D000000),
                            blurRadius: 18,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          Positioned(
                            top: 18,
                            right: 18,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                product.category,
                                style: TextStyle(
                                  color: primary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            top: 58,
                            bottom: 56,
                            left: 12,
                            right: 12,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: _isVideoSelected
                                  ? _buildVideoPreview()
                                  : GestureDetector(
                                      key: const ValueKey(
                                        'product-main-image',
                                      ),
                                      onHorizontalDragStart:
                                          _handleGallerySwipeStart,
                                      onHorizontalDragUpdate:
                                          _handleGallerySwipeUpdate,
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(22),
                                        child: PageView.builder(
                                          key: const ValueKey(
                                            'product-image-pages',
                                          ),
                                          controller: _galleryPageController,
                                          physics:
                                              const NeverScrollableScrollPhysics(),
                                          itemCount: galleryImages.length,
                                          onPageChanged: (index) {
                                            setState(() {
                                              _selectedGalleryIndex = index;
                                            });
                                          },
                                          itemBuilder: (context, index) {
                                            final imageUrl =
                                                galleryImages[index];
                                            return GestureDetector(
                                              key: ValueKey(
                                                'product-gallery-page-$index',
                                              ),
                                              onTap: () {
                                                final provider =
                                                    MediaUploadService
                                                        .imageProvider(
                                                  imageUrl,
                                                );
                                                if (provider != null) {
                                                  showProductImageFullscreen(
                                                    context,
                                                    provider,
                                                  );
                                                }
                                              },
                                              child: SizedBox.expand(
                                                child: _buildImageContent(
                                                  imageUrl,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                          if (!_isVideoSelected && galleryImages.length > 1)
                            Positioned(
                              bottom: 58,
                              left: 18,
                              child: Container(
                                key: const ValueKey('product-gallery-counter'),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '${_selectedGalleryIndex + 1} / ${galleryImages.length}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          Positioned(
                            bottom: 18,
                            left: 18,
                            right: 18,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _TinyBadge(
                                  label: _rating.hasRatings
                                      ? _rating.average.toStringAsFixed(1)
                                      : 'جديد',
                                  icon: Icons.star_rounded,
                                ),
                                const SizedBox(width: 10),
                                const _TinyBadge(
                                  label: 'توصيل سريع',
                                  icon: Icons.local_shipping_rounded,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (hasVideoLink) ...[
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<bool>(
                          showSelectedIcon: false,
                          style: ButtonStyle(
                            foregroundColor:
                                WidgetStateProperty.resolveWith<Color>(
                              (states) => states.contains(WidgetState.selected)
                                  ? const Color(0xFF111827)
                                  : const Color(0xFF374151),
                            ),
                            backgroundColor:
                                WidgetStateProperty.resolveWith<Color>(
                              (states) => states.contains(WidgetState.selected)
                                  ? const Color(0xFFD4AF37)
                                  : Colors.white,
                            ),
                            side: WidgetStateProperty.resolveWith<BorderSide>(
                              (states) => BorderSide(
                                color: states.contains(WidgetState.selected)
                                    ? const Color(0xFFB69449)
                                    : const Color(0xFFD1D5DB),
                              ),
                            ),
                          ),
                          segments: const [
                            ButtonSegment<bool>(
                              value: false,
                              icon: Icon(Icons.photo_library_outlined),
                              label: Text('الصور'),
                            ),
                            ButtonSegment<bool>(
                              value: true,
                              icon: Icon(Icons.play_circle_outline_rounded),
                              label: Text('الفيديو'),
                            ),
                          ],
                          selected: {_isVideoSelected},
                          onSelectionChanged: (selection) {
                            if (selection.first) {
                              _selectVideo();
                            } else {
                              _selectImages();
                            }
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    if (!_isVideoSelected && galleryImages.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Row(
                          key: const ValueKey('product-gallery-indicator'),
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            galleryImages.length,
                            (index) => AnimatedContainer(
                              key: ValueKey('product-gallery-indicator-$index'),
                              duration: const Duration(milliseconds: 180),
                              width: _selectedGalleryIndex == index ? 18 : 7,
                              height: 4,
                              margin: const EdgeInsets.symmetric(
                                horizontal: 3,
                              ),
                              decoration: BoxDecoration(
                                color: _selectedGalleryIndex == index
                                    ? const Color(0xFF6B7280)
                                    : const Color(0xFFD1D5DB),
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                        ),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            product.name,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF111827),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF10B981).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'متوفر الآن',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF10B981),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          product.formatPrice(subtotal),
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: primary,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.local_offer_rounded,
                                  size: 16, color: Color(0xFFB69449)),
                              const SizedBox(width: 4),
                              Text(
                                'خصم 10%',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_availableColors.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      const Text(
                        'اللون',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: _availableColors
                            .map(
                              (color) => ProductColorSwatch(
                                name: color,
                                selected: color == _selectedColor,
                                onTap: () => _selectColor(color),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                    if (_availableSizes.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      const Text(
                        'المقاس',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _availableSizes
                            .map(
                              (size) => ChoiceChip(
                                label: Text(size),
                                selected: size == _selectedSize,
                                selectedColor: const Color(0xFFDBEAFE),
                                onSelected: (_) => setState(() {
                                  _selectedSize = size;
                                  _variantSelections[0].size = size;
                                }),
                                labelStyle: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'الكمية',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF111827),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                onPressed: _quantity > 1
                                    ? () => _setQuantity(_quantity - 1)
                                    : null,
                                icon: const Icon(Icons.remove_rounded),
                              ),
                              Text(
                                '$_quantity',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              IconButton(
                                onPressed: () => _setQuantity(_quantity + 1),
                                icon: const Icon(Icons.add_rounded),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_quantity > 1) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'تخصيص كل قطعة',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF111827),
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'اختر اللون والمقاس لكل قطعة بشكل مستقل',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                            const SizedBox(height: 12),
                            ...List.generate(
                              _variantSelections.length,
                              (index) => _buildUnitVariantPicker(index),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
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
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            product.description.isNotEmpty
                                ? product.description
                                : 'منتج عالي الجودة مصمم لتلبية احتياجاتك اليومية مع تصميم أنيق، أداء موثوق، وتجربة استخدام مريحة ومناسبة للمنزل والعمل.',
                            style: const TextStyle(
                              fontSize: 15,
                              height: 1.8,
                              color: Color(0xFF4B5563),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.all(Radius.circular(18)),
                        border: Border.fromBorderSide(
                          BorderSide(color: Color(0xFFE5E7EB)),
                        ),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'معلومات التوصيل',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF111827),
                            ),
                          ),
                          SizedBox(height: 12),
                          _InfoRow(
                            icon: Icons.local_shipping_rounded,
                            title: 'توصيل خلال 24-48 ساعة',
                          ),
                          _InfoRow(
                            icon: Icons.security_rounded,
                            title: 'ضمان واسترجاع خلال 7 أيام',
                          ),
                          _InfoRow(
                            icon: Icons.payment_rounded,
                            title: 'الدفع عند الاستلام أو الدفع الإلكتروني',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.all(Radius.circular(18)),
                        border: Border.fromBorderSide(
                          BorderSide(color: Color(0xFFE5E7EB)),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'مراجعات العملاء',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(Icons.star_rounded,
                                  color: Color(0xFFD4AF37), size: 18),
                              const SizedBox(width: 6),
                              Text(
                                _rating.hasRatings
                                    ? '${_rating.average.toStringAsFixed(1)} من 5 (${_rating.count})'
                                    : 'لا توجد تقييمات بعد',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _rating.hasRatings
                                ? 'شارك تجربتك بعد استلام المنتج.'
                                : 'كن أول من يقيّم هذا المنتج بعد تجربته.',
                            style: const TextStyle(
                              fontSize: 15,
                              color: Color(0xFF4B5563),
                              height: 1.8,
                            ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _showRatingDialog,
                            icon: const Icon(Icons.rate_review_outlined),
                            label: const Text('قيّم المنتج'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _buildPurchaseActions(context, product),
      ),
    );
  }

  Widget _buildUnitVariantPicker(int index) {
    final selection = _variantSelections[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'القطعة ${index + 1}',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
            ),
          ),
          if (_availableColors.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text('اللون', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: _availableColors
                  .map(
                    (color) => ProductColorSwatch(
                      name: color,
                      selected: selection.color == color,
                      onTap: () => _selectColor(color, selection: selection),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (_availableSizes.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text('المقاس', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: _availableSizes
                  .map(
                    (size) => ChoiceChip(
                      label: Text(size),
                      selected: selection.size == size,
                      onSelected: (_) => setState(() => selection.size = size),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPurchaseActions(BuildContext context, ProductModel product) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(22)),
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: AnimatedBuilder(
          animation: CartService.instance,
          builder: (context, _) {
            final alreadyInCart = productInCart(product);
            final cartButtonColor = cartActionColor(alreadyInCart);

            return Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      if (alreadyInCart) {
                        Navigator.of(context).push(
                          slideFadeRoute(page: const CartScreen()),
                        );
                        return;
                      }

                      if (!await confirmCartAddition(context, widget.product) ||
                          !context.mounted) {
                        return;
                      }
                      _addConfiguredProductToCart();
                      showCartAddedSnackBar(
                        context,
                        onOpenCart: () {
                          Navigator.of(context).push(
                            slideFadeRoute(page: const CartScreen()),
                          );
                        },
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cartButtonColor,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    icon: Icon(cartActionIcon(alreadyInCart)),
                    label: Text(
                      cartActionLabel(alreadyInCart),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 52,
                  height: 52,
                  child: AnimatedBuilder(
                    animation: WishlistService.instance,
                    builder: (context, _) {
                      final isFavorite =
                          WishlistService.instance.contains(product.id);
                      return OutlinedButton(
                        key: const ValueKey('product-detail-favorite'),
                        onPressed: () {
                          final isAdded =
                              WishlistService.instance.toggle(product);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                isAdded
                                    ? 'تمت إضافة المنتج إلى المفضلة'
                                    : 'تمت إزالة المنتج من المفضلة',
                              ),
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isFavorite
                              ? const Color(0xFFB91C1C)
                              : const Color(0xFF111827),
                          side: BorderSide(
                            color: isFavorite
                                ? const Color(0xFFB91C1C)
                                : const Color(0xFFD1D5DB),
                          ),
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Icon(
                          isFavorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 22,
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _productShareMessage(ProductModel product) {
    final productLink = Uri(
      scheme: 'https',
      host: 'she-m-8d0f5.web.app',
      path: '/product_details',
      queryParameters: {'id': product.id},
    ).toString();
    return 'اكتشف هذا المنتج الرائع من شيـم! '
        '${product.name}\n'
        '${product.formatPrice(product.priceIncludingVat)}\n'
        '$productLink';
  }

  Future<void> _showShareProductSheet() async {
    final product = widget.product;
    final shareMessage = _productShareMessage(product);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.56,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'مشاركة المنتج',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 76,
                        height: 76,
                        color: const Color(0xFFEFE7D2),
                        child: _buildImageContent(
                          product.imageUrl,
                          width: 76,
                          height: 76,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            product.formatPrice(product.priceIncludingVat),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                key: const ValueKey('share-product-action'),
                onPressed: () async {
                  try {
                    await SharePlus.instance.share(
                      ShareParams(text: shareMessage, subject: product.name),
                    );
                  } catch (error, stackTrace) {
                    debugPrint('Could not share product: $error');
                    debugPrintStack(stackTrace: stackTrace);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تعذرت مشاركة المنتج')),
                    );
                  }
                },
                icon: const Icon(Icons.share_rounded),
                label: const Text('مشاركة'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: TextButton.icon(
                  key: const ValueKey('copy-product-share-action'),
                  onPressed: () async {
                    try {
                      await Clipboard.setData(
                        ClipboardData(text: shareMessage),
                      );
                      if (!mounted || !sheetContext.mounted) return;
                      Navigator.of(sheetContext).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم نسخ رابط المنتج')),
                      );
                    } catch (error, stackTrace) {
                      debugPrint('Could not copy product link: $error');
                      debugPrintStack(stackTrace: stackTrace);
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تعذر نسخ رابط المنتج')),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('نسخ الرابط'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showRatingDialog() async {
    var selectedRating = 5.0;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('قيّم المنتج'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('اختر تقييمك من 1 إلى 5 نجوم'),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  final value = index + 1.0;
                  return IconButton(
                    onPressed: () =>
                        setDialogState(() => selectedRating = value),
                    icon: Icon(
                      value <= selectedRating
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color: const Color(0xFFD4AF37),
                    ),
                  );
                }),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                final profile = await AuthService().loadSession();
                final customerId = profile?.id.trim().isNotEmpty == true
                    ? profile!.id.trim()
                    : profile?.phone.trim() ?? '';
                final success = await RatingService().submitRating(
                  productId: widget.product.id,
                  customerId: customerId,
                  rating: selectedRating,
                );
                if (context.mounted) Navigator.of(context).pop(success);
              },
              child: const Text('حفظ التقييم'),
            ),
          ],
        ),
      ),
    );
    if (submitted == true) {
      await _loadRating();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ تقييمك')),
        );
      }
    }
  }
}

class _VideoPreviewMessage extends StatelessWidget {
  const _VideoPreviewMessage({
    required this.icon,
    required this.message,
    required this.action,
  });

  final IconData icon;
  final String message;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('product-video-preview'),
      width: double.infinity,
      height: 190,
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 32, color: Colors.white),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 8),
          action,
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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

class _ProductVariantSelection {
  _ProductVariantSelection({required this.color, required this.size});

  String color;
  String size;
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String title;

  const _InfoRow({
    required this.icon,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFFB69449).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: const Color(0xFFB69449)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF374151),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
