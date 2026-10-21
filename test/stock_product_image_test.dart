import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:daily_order/data/datasources/remote/stock_product_image_service.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_product_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ImageClient implements HttpClient {
  @override
  bool autoUncompress = true;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _ImageRequest();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ImageRequest implements HttpClientRequest {
  static Future<HttpClientResponse>? response;
  @override
  Future<HttpClientResponse> close() async => response ?? _ImageResponse();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ImageResponse extends Stream<List<int>> implements HttpClientResponse {
  static late List<int> bytes;
  @override
  int get statusCode => 200;
  @override
  int get contentLength => bytes.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const sku = '16-02-07700';
  const image =
      'https://alainpharmacy-ae.gumlet.io/media/catalog/product/1/6/16-02-07700__1_.jpg';
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _ImageRequest.response = null;
  });

  testWidgets(
    'search and download progress, enlarge, zoom, reset and close on a small screen',
    (tester) async {
      final lookup = Completer<String?>();
      final download = Completer<HttpClientResponse>();
      _ImageRequest.response = download.future;
      await HttpOverrides.runZoned(() async {
        debugNetworkImageHttpClientProvider = () => _ImageClient();
        addTearDown(() => debugNetworkImageHttpClientProvider = null);
        await tester.runAsync(() async {
          final recorder = ui.PictureRecorder();
          Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
          final picture = recorder.endRecording();
          final bitmap = await picture.toImage(8, 8);
          _ImageResponse.bytes = (await bitmap.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List();
          bitmap.dispose();
          picture.dispose();
          await tester.pumpWidget(
            MaterialApp(
              home: Center(
                child: SizedBox(
                  width: 320,
                  child: Row(
                    children: [
                      StockProductImage(
                        sku: sku,
                        resolve: (_) => lookup.future,
                      ),
                      const Expanded(child: Text('Product details')),
                    ],
                  ),
                ),
              ),
            ),
          );
        });
        expect(find.text('Searching…'), findsOneWidget);
        expect(find.text('Product details'), findsOneWidget);
        await tester.runAsync(() async {
          lookup.complete(image);
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pump();
        expect(find.text('Loading image…'), findsOneWidget);
        await tester.runAsync(() async {
          download.complete(_ImageResponse());
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byType(StockProductImage)),
          const Size(90, 76),
        );
        expect(find.text('Product details'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('enlarge-product-image')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('product-image-viewer')),
          findsOneWidget,
        );
        expect(find.text('100%'), findsOneWidget);
        await tester.tap(find.byTooltip('Zoom in'));
        await tester.pump();
        expect(find.text('150%'), findsOneWidget);
        await tester.tap(find.byTooltip('Zoom out'));
        await tester.pump();
        expect(find.text('100%'), findsOneWidget);
        for (var i = 0; i < 8; i++) {
          await tester.tap(find.byTooltip('Zoom in'));
          await tester.pump();
        }
        expect(find.text('600%'), findsOneWidget);
        await tester.tap(find.byTooltip('Reset zoom'));
        await tester.pump();
        expect(find.text('100%'), findsOneWidget);
        await tester.tap(find.byTooltip('Close image'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('product-image-viewer')),
          findsNothing,
        );
        expect(find.text('Product details'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }, createHttpClient: (_) => _ImageClient());
      debugNetworkImageHttpClientProvider = null;
    },
  );

  test(
    'deduplicates lookups and persists a matched image across service instances',
    () async {
      var calls = 0;
      final result = Completer<Map<String, dynamic>>();
      final service = StockProductImageService(
        lookup: (_) {
          calls++;
          return result.future;
        },
      );
      final first = service.resolve(sku);
      final second = service.resolve(sku);
      result.complete({'sku': sku, 'image_url': image, 'status': 'found'});
      expect(await first, image);
      expect(await second, image);
      expect(await service.resolve(sku), image);
      expect(calls, 1);
      await Future<void>.delayed(Duration.zero);
      final restored = StockProductImageService(
        lookup: (_) async => throw StateError('Must use saved image'),
      );
      expect(await restored.resolve(sku), image);
    },
  );

  test(
    'missing products are cached and mismatched SKU or hosts never display',
    () async {
      var calls = 0;
      final service = StockProductImageService(
        lookup: (code) async {
          calls++;
          return {'sku': code, 'image_url': null, 'status': 'not_found'};
        },
      );
      expect(await service.resolve(sku), isNull);
      expect(await service.resolve(sku), isNull);
      expect(calls, 1);
      final mismatch = StockProductImageService(
        lookup: (_) async => {
          'sku': 'other',
          'image_url': image,
          'status': 'found',
        },
      );
      expect(await mismatch.resolve(sku), isNull);
      expect(
        StockProductImageService.validImage('https://example.com/image.jpg'),
        isFalse,
      );
    },
  );

  testWidgets(
    'lookup timeout clears progress and switching SKU ignores old lookup',
    (tester) async {
      final first = Completer<String?>();
      final second = Completer<String?>();
      Future<void> open(String code, Completer<String?> pending) =>
          tester.pumpWidget(
            MaterialApp(
              home: Row(
                children: [
                  StockProductImage(sku: code, resolve: (_) => pending.future),
                  const Expanded(child: Text('Product details')),
                ],
              ),
            ),
          );
      await open(sku, first);
      expect(find.text('Searching…'), findsOneWidget);
      await open('16-02-12900', second);
      first.complete(image);
      await tester.pump();
      expect(find.text('Searching…'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      await tester.pump(const Duration(seconds: 13));
      expect(find.byKey(const ValueKey('product-image-loading')), findsNothing);
      expect(tester.getSize(find.byType(StockProductImage)), Size.zero);
      expect(find.text('Product details'), findsOneWidget);
      second.complete(null);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'stalled image download clears progress without blocking details',
    (tester) async {
      final download = Completer<HttpClientResponse>();
      _ImageRequest.response = download.future;
      debugNetworkImageHttpClientProvider = () => _ImageClient();
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Row(
              children: [
                StockProductImage(
                  sku: sku,
                  resolve: (_) async => '$image?timeout-test',
                ),
                const Expanded(child: Text('Product details')),
              ],
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(find.text('Loading image…'), findsOneWidget);
        await tester.pump(const Duration(seconds: 16));
        expect(
          find.byKey(const ValueKey('product-image-loading')),
          findsNothing,
        );
        expect(tester.getSize(find.byType(StockProductImage)), Size.zero);
        expect(find.text('Product details'), findsOneWidget);
        download.completeError(const SocketException('Offline'));
        await tester.pump();
        expect(tester.takeException(), isNull);
      } finally {
        debugNetworkImageHttpClientProvider = null;
      }
    },
  );

  testWidgets(
    'pending lookup shows progress; missing and failed lookup collapse without blocking details',
    (tester) async {
      final pending = Completer<String?>();
      await tester.pumpWidget(
        MaterialApp(
          home: Row(
            children: [
              StockProductImage(sku: sku, resolve: (_) => pending.future),
              const Expanded(child: Text('Product details')),
            ],
          ),
        ),
      );
      expect(find.text('Product details'), findsOneWidget);
      expect(find.text('Searching…'), findsOneWidget);
      expect(
        tester.getSize(find.byType(StockProductImage)),
        const Size(90, 76),
      );
      pending.complete(null);
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(StockProductImage)), Size.zero);
      await tester.pumpWidget(
        MaterialApp(
          home: Row(
            children: [
              StockProductImage(
                key: const ValueKey('failed'),
                sku: sku,
                resolve: (_) async => throw StateError('Offline'),
              ),
              const Expanded(child: Text('Product details')),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(StockProductImage)), Size.zero);
      expect(tester.takeException(), isNull);
    },
  );
}
