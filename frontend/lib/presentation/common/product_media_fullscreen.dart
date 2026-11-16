import 'dart:async';

import 'package:flutter/material.dart';
import 'package:she_m_app/presentation/common/product_video_cache.dart';
import 'package:video_player/video_player.dart';

Future<void> showProductImageFullscreen(
  BuildContext context,
  ImageProvider<Object> imageProvider,
) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black,
    builder: (_) => _ProductMediaFullscreen(imageProvider: imageProvider),
  );
}

Future<void> showProductVideoFullscreen(
  BuildContext context, {
  VideoPlayerController? controller,
  String? videoUrl,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black,
    builder: (_) => _ProductMediaFullscreen(
      controller: controller,
      videoUrl: videoUrl,
    ),
  );
}

class _ProductMediaFullscreen extends StatefulWidget {
  const _ProductMediaFullscreen({
    this.imageProvider,
    this.controller,
    this.videoUrl,
  });

  final ImageProvider<Object>? imageProvider;
  final VideoPlayerController? controller;
  final String? videoUrl;

  @override
  State<_ProductMediaFullscreen> createState() =>
      _ProductMediaFullscreenState();
}

class _ProductMediaFullscreenState extends State<_ProductMediaFullscreen> {
  final TransformationController _transformationController =
      TransformationController();
  VideoPlayerController? _videoController;
  ProductVideoControllerLease? _videoLease;
  String? _videoError;

  @override
  void initState() {
    super.initState();
    _videoController = widget.controller;
    if (_videoController == null && widget.videoUrl != null) {
      final uri = Uri.tryParse(widget.videoUrl!.trim());
      if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
        _videoError = 'رابط الفيديو غير صالح';
        return;
      }
      _videoLease = ProductVideoCache.acquireNetwork(widget.videoUrl!);
      _videoController = _videoLease!.controller;
      _initializeVideo(_videoController!);
    }
  }

  Future<void> _initializeVideo(VideoPlayerController controller) async {
    try {
      if (!controller.value.isInitialized) {
        await controller.initialize();
      }
      if (!controller.value.isLooping) await controller.setLooping(true);
      if (mounted) setState(() {});
    } catch (error, stackTrace) {
      debugPrint('Could not initialize fullscreen product video: $error');
      debugPrintStack(stackTrace: stackTrace);
      final lease = _videoLease;
      if (lease != null) ProductVideoCache.invalidate(lease);
      if (mounted) setState(() => _videoError = 'تعذر تشغيل الفيديو');
    }
  }

  void _zoom(double factor) {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    final nextScale = (currentScale * factor).clamp(0.8, 5.0).toDouble();
    _transformationController.value = Matrix4.identity()
      ..scaleByDouble(nextScale, nextScale, nextScale, 1);
  }

  Future<void> _toggleVideo() async {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
    if (mounted) setState(() {});
  }

  Future<void> _close() async {
    final controller = _videoController;
    if (controller?.value.isPlaying == true) await controller!.pause();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    final lease = _videoLease;
    if (lease != null) {
      unawaited(ProductVideoCache.release(lease));
    }
    super.dispose();
  }

  Widget _buildMedia() {
    final imageProvider = widget.imageProvider;
    if (imageProvider != null) {
      return Image(
        image: imageProvider,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Icon(
          Icons.broken_image_outlined,
          color: Colors.white,
          size: 64,
        ),
      );
    }

    final controller = _videoController;
    if (_videoError != null) {
      return Center(
        child: Text(
          _videoError!,
          style: const TextStyle(color: Colors.white),
        ),
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    final aspectRatio = controller.value.aspectRatio > 0
        ? controller.value.aspectRatio
        : 16 / 9;
    return Center(
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: VideoPlayer(controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _videoController;
    final isVideo = widget.imageProvider == null;
    final videoReady = controller?.value.isInitialized == true;

    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                transformationController: _transformationController,
                minScale: 0.8,
                maxScale: 5,
                child: _buildMedia(),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                tooltip: 'إغلاق العرض',
                onPressed: _close,
                color: Colors.white,
                icon: const Icon(Icons.close_rounded),
              ),
            ),
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filledTonal(
                    tooltip: 'تصغير',
                    onPressed: () => _zoom(0.8),
                    icon: const Icon(Icons.zoom_out_rounded),
                  ),
                  const SizedBox(width: 12),
                  IconButton.filledTonal(
                    tooltip: 'تكبير',
                    onPressed: () => _zoom(1.25),
                    icon: const Icon(Icons.zoom_in_rounded),
                  ),
                  if (isVideo && videoReady) ...[
                    const SizedBox(width: 20),
                    IconButton.filledTonal(
                      tooltip: controller!.value.isPlaying
                          ? 'إيقاف مؤقت'
                          : 'تشغيل الفيديو',
                      onPressed: _toggleVideo,
                      icon: Icon(
                        controller.value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    ),
                    SizedBox(
                      width: 120,
                      child: VideoProgressIndicator(
                        controller,
                        allowScrubbing: true,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        colors: const VideoProgressColors(
                          playedColor: Color(0xFFD4AF37),
                          bufferedColor: Color(0x99FFFFFF),
                          backgroundColor: Color(0x55FFFFFF),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
