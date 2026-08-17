import 'package:daily_order/domain/entities/items_tracker_record.dart';
import 'package:daily_order/domain/repositories/items_tracker_repository.dart';
import 'package:daily_order/presentation/items_tracker/page/items_tracker_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpPage(
    WidgetTester tester, {
    required String role,
    ItemsTrackerRepository? repository,
  }) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ItemsTrackerPage(
            role: role,
            embedded: true,
            repository: repository ?? _FakeItemsTrackerRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('inventory sees the Add Item workflow', (tester) async {
    await pumpPage(tester, role: ItemsTrackerRoles.inventory);

    expect(find.text('Items Tracker'), findsOneWidget);
    expect(find.byKey(const ValueKey('itemsTrackerAddItem')), findsOneWidget);
    expect(find.byKey(const ValueKey('itemsTrackerExport')), findsOneWidget);
    expect(find.text('Start the Items Tracker'), findsOneWidget);
  });

  testWidgets('purchase sees the shared tracker without inventory editing', (
    tester,
  ) async {
    await pumpPage(tester, role: ItemsTrackerRoles.purchase);

    expect(find.text('Items Tracker'), findsOneWidget);
    expect(find.byKey(const ValueKey('itemsTrackerAddItem')), findsNothing);
    expect(
      find.text('Inventory has not added any tracked items yet.'),
      findsOneWidget,
    );
  });

  testWidgets('summary totals required value for pending records only', (
    tester,
  ) async {
    final records = [
      ItemsTrackerRecord.fromMap({
        'id': 'item-1',
        'escalated_date': '2026-08-14',
        'item_code': '16-02-12216',
        'item_name': 'Test item',
        'unit_cost_snapshot': 50.7717,
        'required_qty': 100,
        'follow_up_role': 'inventory',
        'case_status': 'pending',
        'created_at': '2026-08-14T08:00:00Z',
        'updated_at': '2026-08-14T08:00:00Z',
      }),
      ItemsTrackerRecord.fromMap({
        'id': 'item-2',
        'escalated_date': '2026-08-14',
        'item_code': '16-02-99999',
        'item_name': 'Completed item',
        'unit_cost_snapshot': 1000,
        'required_qty': 100,
        'follow_up_role': 'inventory',
        'case_status': 'done',
        'created_at': '2026-08-14T08:00:00Z',
        'updated_at': '2026-08-14T08:00:00Z',
      }),
    ];

    await pumpPage(
      tester,
      role: ItemsTrackerRoles.inventory,
      repository: _FakeItemsTrackerRepository(records: records),
    );

    expect(find.text('Total required value'), findsOneWidget);
    expect(find.text('AED 5,077.17'), findsOneWidget);
    expect(find.text('AED 105,077.17'), findsNothing);
  });
}

class _FakeItemsTrackerRepository implements ItemsTrackerRepository {
  final List<ItemsTrackerRecord> records;

  const _FakeItemsTrackerRepository({this.records = const []});

  @override
  Future<List<ItemsTrackerRecord>> fetchRecords() async => records;

  @override
  Future<List<String>> fetchItemStatuses() async => const [
    '1#NORMAL PURCHASE',
    '2#PR',
  ];

  @override
  Future<List<ItemsTrackerProduct>> searchProducts(String query) async =>
      const [];

  @override
  Future<List<ItemsTrackerTimelineEntry>> fetchTimeline(String itemId) async =>
      const [];

  @override
  Future<void> createRecord(CreateItemsTrackerRecord input) async {}

  @override
  Future<void> updateInventoryFields(UpdateItemsTrackerRecord input) async {}

  @override
  Future<void> updateStatusUpdatedTo(UpdateItemsTrackerStatus input) async {}

  @override
  Future<void> updateTrackerStatus(UpdateItemsTrackerCaseStatus input) async {}

  @override
  Future<void> addAction(AddItemsTrackerAction input) async {}

  @override
  Future<void> changeFollowUp(ChangeItemsTrackerFollowUp input) async {}

  @override
  Future<void> addComment({
    required String itemId,
    required String body,
  }) async {}

  @override
  Future<void> uploadAttachment({
    required String itemId,
    required ItemsTrackerUploadFile file,
  }) async {}

  @override
  Future<String> createAttachmentDownloadUrl(String storagePath) async =>
      'https://example.test/file';
}
