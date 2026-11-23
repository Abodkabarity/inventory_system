import 'package:daily_order/data/datasources/remote/stock_catalog_remote_ds.dart';
import 'package:daily_order/data/datasources/remote/stock_management_remote_ds.dart';
import 'package:daily_order/data/datasources/remote/stock_expiry_remote_ds.dart';
import 'package:daily_order/domain/entities/stock_catalog.dart';
import 'package:daily_order/domain/entities/stock_management.dart';
import 'package:daily_order/domain/entities/stock_expiry.dart';
import 'package:daily_order/domain/entities/inventory_page.dart';
import 'package:daily_order/presentation/zone_manager/widgets/zone_stock_workspace.dart';
import 'package:daily_order/presentation/inventory_dashboard/page/stock_catalog_page.dart';
import 'package:daily_order/presentation/inventory_dashboard/page/stock_management_page.dart';
import 'package:daily_order/presentation/inventory_dashboard/page/stock_expiry_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Catalog extends StockCatalogDataSource {
  int loads = 0;
  @override
  Future<StockCatalogResult> fetchPage(StockCatalogQuery query) async {
    loads++;
    return const StockCatalogResult(rows: [], summary: {'items': 0}, meta: {});
  }

  @override
  Future<Map<String, dynamic>?> refreshState() async => null;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Mrn extends StockManagementDataSource {
  @override
  Future<StockManagementResult> fetchPage(StockManagementQuery query) async =>
      const StockManagementResult(rows: [], summary: {'items': 0}, meta: {});
  @override
  Future<Map<String, dynamic>?> refreshState() async => null;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Expiry extends StockExpiryDataSource {
  @override
  Future<StockExpiryResult> fetchPage(StockExpiryQuery query) async =>
      const StockExpiryResult(rows: [], total: 0, summary: {}, meta: {});
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  testWidgets(
    'server authorization gates all stock pages and revocation removes data',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final catalog = _Catalog();
      Widget app(bool allowed) => MaterialApp(
        home: Scaffold(
          body: ZoneStockWorkspace(
            authorized: allowed,
            catalogSource: catalog,
            mrnSource: _Mrn(),
            cdSource: _Mrn(),
            expirySource: _Expiry(),
          ),
        ),
      );
      await tester.pumpWidget(app(false));
      await tester.pumpAndSettle();
      expect(catalog.loads, 0);
      expect(find.byType(StockCatalogPage), findsNothing);
      await tester.pumpWidget(app(true));
      await tester.pumpAndSettle();
      expect(catalog.loads, greaterThan(0));
      expect(
        tester.widget<StockCatalogPage>(find.byType(StockCatalogPage)).readOnly,
        isTrue,
      );
      expect(find.text('All branches · Read only'), findsOneWidget);
      expect(ZoneStockWorkspace.pages, [
        InventoryPageType.stockManagement,
        InventoryPageType.mrnOverview,
        InventoryPageType.mrnCdOverview,
        InventoryPageType.nearExpiry,
      ]);
      for (final label in ['MRN Overview', 'MRN CD Overview', 'Near Expiry']) {
        await tester.tap(find.widgetWithText(ChoiceChip, label));
        await tester.pumpAndSettle();
        if (label == 'Near Expiry') {
          expect(
            tester
                .widget<StockExpiryPage>(find.byType(StockExpiryPage))
                .readOnly,
            isTrue,
          );
        } else {
          expect(
            tester
                .widget<StockManagementPage>(find.byType(StockManagementPage))
                .cd,
            label == 'MRN CD Overview',
          );
        }
        expect(find.text('Online Overview'), findsNothing);
        expect(find.text('Save note'), findsNothing);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(app(false));
      await tester.pumpAndSettle();
      expect(find.byType(StockCatalogPage), findsNothing);
      expect(find.byType(StockExpiryPage), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
    },
  );
}
