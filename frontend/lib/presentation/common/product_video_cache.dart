import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

class ProductVideoControllerLease {
  ProductVideoControllerLease._(this._entry);

  final _CachedProductVideo _entry;
  bool _released = false;

  VideoPlayerController get controller => _entry.controller;
}

class ProductVideoCache {
  ProductVideoCache._();

  static const int _maxCachedControllers = 3;
  static final LinkedHashMap<String, _CachedProductVideo> _entries =
      LinkedHashMap<String, _CachedProductVideo>();

  static ProductVideoControllerLease acquireNetwork(String url) {
    final normalizedUrl = url.trim();
    return _acquire(
      'network:$normalizedUrl',
      () => VideoPlayerController.networkUrl(Uri.parse(normalizedUrl)),
    );
  }

  static ProductVideoControllerLease acquireFile(String path) {
    final normalizedPath = path.trim();
    return _acquire(
      'file:$normalizedPath',
      () => VideoPlayerController.file(File(normalizedPath)),
    );
  }

  static ProductVideoControllerLease _acquire(
    String key,
    VideoPlayerController Function() createController,
  ) {
    var entry = _entries.remove(key);
    if (entry == null || entry.invalidated) {
      entry = _CachedProductVideo(key, createController());
    }
    entry.leaseCount++;
    _entries[key] = entry;
    _evictOverflow();
    return ProductVideoControllerLease._(entry);
  }

  static Future<void> release(ProductVideoControllerLease lease) async {
    if (lease._released) return;
    lease._released = true;
    final entry = lease._entry;
    try {
      if (entry.controller.value.isPlaying) {
        await entry.controller.pause();
      }
    } catch (error, stackTrace) {
      debugPrint('Could not pause cached product video: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    entry.leaseCount--;
    if (entry.invalidated && entry.leaseCount == 0) {
      _dispose(entry);
    } else {
      _evictOverflow();
    }
  }

  static void invalidate(ProductVideoControllerLease lease) {
    final entry = lease._entry;
    if (entry.invalidated) return;
    entry.invalidated = true;
    if (identical(_entries[entry.key], entry)) {
      _entries.remove(entry.key);
    }
    if (entry.leaseCount == 0) _dispose(entry);
  }

  static void _evictOverflow() {
    while (_entries.length > _maxCachedControllers) {
      String? keyToEvict;
      for (final entry in _entries.entries) {
        if (entry.value.leaseCount == 0) {
          keyToEvict = entry.key;
          break;
        }
      }
      if (keyToEvict == null) return;
      final entry = _entries.remove(keyToEvict)!;
      entry.invalidated = true;
      _dispose(entry);
    }
  }

  static void _dispose(_CachedProductVideo entry) {
    if (entry.disposed) return;
    entry.disposed = true;
    unawaited(_disposeController(entry.controller));
  }

  static Future<void> _disposeController(
    VideoPlayerController controller,
  ) async {
    try {
      await controller.dispose();
    } catch (error, stackTrace) {
      debugPrint('Could not dispose cached product video: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}

class _CachedProductVideo {
  _CachedProductVideo(this.key, this.controller);

  final String key;
  final VideoPlayerController controller;
  int leaseCount = 0;
  bool invalidated = false;
  bool disposed = false;
}
