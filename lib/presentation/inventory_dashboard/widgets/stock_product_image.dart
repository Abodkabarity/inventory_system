import 'dart:async';

import 'package:flutter/material.dart';

/// Shows lookup/download progress, then a tappable image; failures collapse.
class StockProductImage extends StatefulWidget {
  final String sku;
  final Future<String?> Function(String) resolve;
  const StockProductImage({
    super.key,
    required this.sku,
    required this.resolve,
  });

  @override
  State<StockProductImage> createState() => _StockProductImageState();
}

class _StockProductImageState extends State<StockProductImage> {
  late Future<String?> _image;
  Timer? _downloadTimer;
  bool _downloadTimedOut = false;

  Future<String?> _load() async {
    final sku = widget.sku;
    try {
      final url = await widget
          .resolve(sku)
          .timeout(const Duration(seconds: 12));
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
      _downloadTimer?.cancel();
      _downloadTimedOut = false;
      _image = _load();
    }
  }

  @override
  void dispose() {
    _downloadTimer?.cancel();
    super.dispose();
  }

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
        return const SizedBox.shrink();
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
          return const SizedBox.shrink();
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
                      url: snapshot.data!,
                      sku: widget.sku,
                    ),
                  ),
                  child: child,
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
  final String url;
  final String sku;
  const _ProductImageViewer({required this.url, required this.sku});

  @override
  State<_ProductImageViewer> createState() => _ProductImageViewerState();
}

class _ProductImageViewerState extends State<_ProductImageViewer> {
  final _transform = TransformationController();

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
                            widget.url,
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
