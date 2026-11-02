import 'dart:async';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import '../../../core/utils/stock_image_preload_queue.dart';

import 'package:flutter/material.dart';

/// Shows lookup/download progress, then a tappable image; failures collapse.
class StockProductImage extends StatefulWidget {
  final String sku;
  final Future<String?> Function(String) resolve;
  final Future<List<String>> Function(String)? resolveGallery;
  final Future<List<String>> Function(String, Uint8List)? uploadImage;
  const StockProductImage({
    super.key,
    required this.sku,
    required this.resolve,
    this.resolveGallery,
    this.uploadImage,
  });

  @override
  State<StockProductImage> createState() => _StockProductImageState();
}

class _StockProductImageState extends State<StockProductImage> {
  late Future<String?> _image;
  Timer? _downloadTimer;
  bool _downloadTimedOut = false;
  List<String> _gallery = const [];
  bool _uploading = false;
  StockImagePreloadQueue? _preloader;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _preloader ??= _newPreloader();
  }

  StockImagePreloadQueue _newPreloader() => StockImagePreloadQueue(
    load: (url) => precacheImage(
      NetworkImage(
        url,
        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
      ),
      context,
      onError: (_, _) {},
    ),
  );

  void _warmGallery(List<String> images, String sku) {
    // Let the visible primary image start first; secondary images never delay it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.sku == sku) _preloader?.add(images.skip(1));
    });
  }

  Future<String?> _load() async {
    final sku = widget.sku;
    try {
      final gallery = widget.resolveGallery;
      final images = gallery != null
          ? await gallery(sku).timeout(const Duration(seconds: 35))
          : [?await widget.resolve(sku).timeout(const Duration(seconds: 12))];
      if (!mounted || widget.sku != sku) return null;
      _gallery = images;
      _warmGallery(images, sku);
      final url = images.isEmpty ? null : images.first;
      if (mounted && widget.sku == sku && url != null) {
        _downloadTimer = Timer(const Duration(seconds: 15), () {
          if (mounted) setState(() => _downloadTimedOut = true);
        });
      }
      return url;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _image = _load();
  }

  @override
  void didUpdateWidget(covariant StockProductImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sku != widget.sku) {
      _preloader?.dispose();
      _preloader = _newPreloader();
      _downloadTimer?.cancel();
      _gallery = const [];
      _downloadTimedOut = false;
      _image = _load();
    }
  }

  @override
  void dispose() {
    _preloader?.dispose();
    _downloadTimer?.cancel();
    super.dispose();
  }

  Future<void> _addImage() async {
    if (_uploading || widget.uploadImage == null) return;
    final sku = widget.sku;
    setState(() => _uploading = true);
    try {
      final selected = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'gif', 'avif'],
        withData: true,
      );
      if (selected == null || !mounted || widget.sku != sku) return;
      final file = selected.files.single;
      if (file.size > 10 * 1024 * 1024 || file.bytes == null) {
        throw StateError('Choose an image under 10 MB.');
      }
      final images = await widget.uploadImage!(sku, file.bytes!);
      if (!mounted || widget.sku != sku) return;
      _downloadTimer?.cancel();
      _warmGallery(images, sku);
      setState(() {
        _gallery = images;
        _downloadTimedOut = false;
        _image = Future.value(images.first);
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not add image. Choose a valid image under 10 MB and retry.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Widget _missing() => widget.uploadImage == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(right: 14),
          child: SizedBox(
            width: 76,
            height: 76,
            child: OutlinedButton(
              key: const ValueKey('add-product-image'),
              onPressed: _uploading ? null : _addImage,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
                padding: const EdgeInsets.all(6),
              ),
              child: _uploading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined),
                        SizedBox(height: 4),
                        Text('Add image', style: TextStyle(fontSize: 11)),
                      ],
                    ),
            ),
          ),
        );

  Widget _progress(String label) => Padding(
    padding: const EdgeInsets.only(right: 14),
    child: Container(
      key: const ValueKey('product-image-loading'),
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 19,
            height: 19,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10, color: Colors.white),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: _image,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return _progress('Searching…');
      }
      if (snapshot.data == null || _downloadTimedOut) {
        return _missing();
      }
      return Image.network(
        snapshot.data!,
        key: ValueKey('${widget.sku}:${snapshot.data}'),
        width: 76,
        height: 76,
        fit: BoxFit.contain,
        semanticLabel: 'Product image ${widget.sku}',
        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
        errorBuilder: (_, _, _) {
          _downloadTimer?.cancel();
          return _missing();
        },
        frameBuilder: (context, child, frame, synchronous) {
          if (!synchronous && frame == null) return _progress('Loading image…');
          _downloadTimer?.cancel();
          return Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Tooltip(
              message: 'Enlarge product image',
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: const ValueKey('enlarge-product-image'),
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (_) => _ProductImageViewer(
                      urls: _gallery.isEmpty ? [snapshot.data!] : _gallery,
                      sku: widget.sku,
                    ),
                  ),
                  child: Stack(
                    children: [
                      child,
                      if (_gallery.length > 1)
                        Positioned(
                          right: 3,
                          bottom: 3,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              '${_gallery.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

class _ProductImageViewer extends StatefulWidget {
  final List<String> urls;
  final String sku;
  const _ProductImageViewer({required this.urls, required this.sku});

  @override
  State<_ProductImageViewer> createState() => _ProductImageViewerState();
}

class _ProductImageViewerState extends State<_ProductImageViewer> {
  final _transform = TransformationController();
  int _index = 0;
  void _select(int index) => setState(() {
    _index = index;
    _transform.value = Matrix4.identity();
  });

  void _zoom(double factor, Size viewport) {
    final current = _transform.value;
    final scale = current.getMaxScaleOnAxis();
    final next = (scale * factor).clamp(1.0, 6.0);
    if (next == 1) {
      _transform.value = Matrix4.identity();
      return;
    }
    final ratio = next / scale;
    final center = viewport.center(Offset.zero);
    _transform.value = Matrix4.identity()
      ..setEntry(0, 0, next)
      ..setEntry(1, 1, next)
      ..setEntry(0, 3, center.dx - (center.dx - current.storage[12]) * ratio)
      ..setEntry(1, 3, center.dy - (center.dy - current.storage[13]) * ratio);
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    key: const ValueKey('product-image-viewer'),
    insetPadding: const EdgeInsets.all(16),
    clipBehavior: Clip.antiAlias,
    backgroundColor: Colors.white,
    child: SizedBox(
      width: 1000,
      height: MediaQuery.sizeOf(context).height * .85,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Product image · ${widget.sku}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Close image',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final viewport = constraints.biggest;
                return Column(
                  children: [
                    Expanded(
                      child: InteractiveViewer(
                        transformationController: _transform,
                        minScale: 1,
                        maxScale: 6,
                        child: SizedBox.expand(
                          child: Image.network(
                            widget.urls[_index],
                            fit: BoxFit.contain,
                            semanticLabel: 'Product image ${widget.sku}',
                            webHtmlElementStrategy:
                                WebHtmlElementStrategy.fallback,
                            errorBuilder: (_, _, _) =>
                                const Center(child: Text('Image unavailable')),
                            frameBuilder: (_, child, frame, synchronous) =>
                                synchronous || frame != null
                                ? child
                                : const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                          ),
                        ),
                      ),
                    ),
                    ValueListenableBuilder<Matrix4>(
                      valueListenable: _transform,
                      builder: (context, matrix, _) {
                        final scale = matrix.getMaxScaleOnAxis();
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              tooltip: 'Zoom out',
                              onPressed: scale > 1
                                  ? () => _zoom(1 / 1.5, viewport)
                                  : null,
                              icon: const Icon(Icons.remove),
                            ),
                            SizedBox(
                              width: 54,
                              child: Text(
                                '${(scale * 100).round()}%',
                                textAlign: TextAlign.center,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Zoom in',
                              onPressed: scale < 6
                                  ? () => _zoom(1.5, viewport)
                                  : null,
                              icon: const Icon(Icons.add),
                            ),
                            IconButton(
                              tooltip: 'Reset zoom',
                              onPressed: () =>
                                  _transform.value = Matrix4.identity(),
                              icon: const Icon(Icons.fit_screen),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ),
          if (widget.urls.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Previous image',
                    onPressed: _index > 0 ? () => _select(_index - 1) : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text('${_index + 1} / ${widget.urls.length}'),
                  IconButton(
                    tooltip: 'Next image',
                    onPressed: _index < widget.urls.length - 1
                        ? () => _select(_index + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'Pinch or scroll to zoom · Drag to move',
              style: TextStyle(fontSize: 12, color: Colors.blueGrey),
            ),
          ),
        ],
      ),
    ),
  );
}
