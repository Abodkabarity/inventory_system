import 'dart:async';
import 'package:daily_order/core/utils/stock_image_preload_queue.dart';
import 'package:daily_order/domain/entities/stock_catalog.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_catalog_grid.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'stock_catalog_test.dart' as catalog;

void main() {
  test(
    'warms every distinct image with two downloads, then cancels queued work on close',
    () async {
      final pending = <String, Completer<void>>{};
      final queue = StockImagePreloadQueue(
        load: (url) {
          final task = Completer<void>();
          pending[url] = task;
          return task.future;
        },
      );
      queue.add(['a', 'b', 'c', 'a', 'd']);
      expect(pending.keys, ['a', 'b']);
      pending['a']!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(pending.keys, ['a', 'b', 'c']);
      queue.dispose();
      pending['b']!.complete();
      pending['c']!.complete();
      await Future<void>.delayed(Duration.zero);
      queue.add(['e']);
      expect(pending.containsKey('d'), false);
      expect(pending.containsKey('e'), false);
    },
  );
  test(
    'a broken image does not prevent warming remaining gallery images',
    () async {
      final calls = <String>[];
      final queue = StockImagePreloadQueue(
        load: (url) async {
          calls.add(url);
          if (url == 'broken') throw StateError('404');
        },
      );
      queue.add(['first', 'broken', 'third', 'fourth']);
      await Future<void>.delayed(Duration.zero);
      expect(calls.toSet(), {'first', 'broken', 'third', 'fourth'});
      queue.dispose();
    },
  );
  testWidgets(
    'hover waits for a stable row and cancels brief or abandoned hovers',
    (tester) async {
      final hovers = <String>[];
      final base = catalog.fixture().data;
      final a = StockCatalogItem({
        ...base,
        'item_code': 'A',
        'item_name': 'PREFETCH A',
      });
      final b = StockCatalogItem({
        ...base,
        'item_code': 'B',
        'item_name': 'PREFETCH B',
      });
      await catalog.app(
        tester,
        StockCatalogGrid(
          items: [a, b],
          onOpen: (_) {},
          onImageHover: (item) => hovers.add(item.code),
        ),
        size: const Size(1500, 650),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('PREFETCH A')));
      await tester.pump(const Duration(milliseconds: 150));
      expect(hovers, isEmpty);
      await mouse.moveTo(tester.getCenter(find.text('PREFETCH B')));
      await tester.pump(const Duration(milliseconds: 360));
      expect(hovers, ['B']);
      await mouse.moveTo(tester.getCenter(find.text('PREFETCH A')));
      await tester.pump(const Duration(milliseconds: 100));
      await mouse.moveTo(Offset.zero);
      await tester.pump(const Duration(milliseconds: 400));
      expect(hovers, ['B']);
      expect(tester.takeException(), isNull);
    },
  );
}
