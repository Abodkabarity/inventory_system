import 'package:daily_order/domain/entities/items_tracker_record.dart';
import 'package:daily_order/domain/entities/items_tracker_action_import.dart';
import 'package:daily_order/domain/entities/items_tracker_email.dart';
import 'package:daily_order/core/utils/items_tracker_excel_importer.dart';
import 'package:daily_order/presentation/items_tracker/widgets/items_tracker_import_dialog.dart';
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
    expect(find.byKey(const ValueKey('itemsTrackerImport')), findsOneWidget);
    expect(find.text('Start the Items Tracker'), findsOneWidget);
  });

  testWidgets(
    'column filters combine, cancel safely and stay editable with no matches',
    (tester) async {
      final repository = _FakeItemsTrackerRepository(
        records: [
          for (var i = 1; i <= 3; i++)
            ItemsTrackerRecord.fromMap({
              'id': 'filter-$i',
              'item_name': 'Filter product $i',
              'category': 'MEDICINE',
              'unit_cost_snapshot': i * 10,
              'required_qty': i * 5,
              'inventory_note': i == 3 ? 'Return stock' : 'Slow moving',
              'follow_up_role': i == 1 ? 'inventory' : 'category',
            }),
        ],
      );
      await pumpPage(tester, role: 'inventory', repository: repository);
      await tester.tap(find.byKey(const ValueKey('columnFilter:reason')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('columnFilterValue:Return stock')),
      );
      await tester.tap(find.byKey(const ValueKey('columnFilterApply')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('itemCard:filter-3')), findsNothing);
      expect(find.byKey(const ValueKey('itemCard:filter-1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('columnFilter:cost')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('columnFilterMin')),
        '15',
      );
      await tester.tap(find.byKey(const ValueKey('columnFilterApply')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('itemCard:filter-1')), findsNothing);
      expect(find.byKey(const ValueKey('itemCard:filter-2')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('columnFilter:cost')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('columnFilterMin')),
        '30',
      );
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('itemCard:filter-2')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('columnFilter:cost')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('columnFilterMin')),
        '100',
      );
      await tester.tap(find.byKey(const ValueKey('columnFilterApply')));
      await tester.pumpAndSettle();
      expect(find.text('No matching items'), findsOneWidget);
      expect(find.byKey(const ValueKey('columnFilter:cost')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('columnFilter:cost')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('columnFilterClear')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('itemCard:filter-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('itemCard:filter-3')), findsNothing);
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('itemCard:filter-3')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('searching column values can select only results', (
    tester,
  ) async {
    final repository = _FakeItemsTrackerRepository(
      records: [
        for (var i = 1; i <= 2; i++)
          ItemsTrackerRecord.fromMap({
            'id': 'search-$i',
            'item_name': 'Product $i',
            'category': 'MEDICINE',
            'latest_comment': i == 1 ? 'Call supplier' : 'Return approved',
          }),
      ],
    );
    await pumpPage(tester, role: 'inventory', repository: repository);
    await tester.tap(find.byKey(const ValueKey('columnFilter:comment')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('columnFilterSearch:comment')),
      'call',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('columnFilterValue:Return approved')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('columnFilterOnlyResults')));
    await tester.tap(find.byKey(const ValueKey('columnFilterApply')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('itemCard:search-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('itemCard:search-2')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  Future<void> openCompany(
    WidgetTester tester,
    _FakeItemsTrackerRepository repository,
  ) async {
    await pumpPage(
      tester,
      role: ItemsTrackerRoles.inventory,
      repository: repository,
    );
    await tester.tap(find.byKey(const ValueKey('itemsTrackerAddItem')));
    await tester.pumpAndSettle();
    expect(find.text('Single product'), findsOneWidget);
    await tester.tap(find.text('Company products'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('companyOption:Example Company')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('company saves selected products and optional costs', (
    tester,
  ) async {
    final repository = _FakeItemsTrackerRepository();
    await openCompany(tester, repository);
    expect(find.text('3 selected · 3 products'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('companyCost:0')))
          .controller!
          .text,
      isEmpty,
    );
    await tester.enterText(
      find.byKey(const ValueKey('companyCost:0')),
      '12.50',
    );
    await tester.enterText(find.byKey(const ValueKey('companyQty:0')), '4');
    await tester.enterText(
      find.byKey(const ValueKey('companyEntryReason')),
      'Company stock review',
    );
    await tester.tap(find.byKey(const ValueKey('companySelect:2')));
    await tester.tap(find.byKey(const ValueKey('companyEntrySave')));
    await tester.pumpAndSettle();
    final inputs = repository.batches.single;
    expect(inputs.map((r) => r.itemCode), ['A-1', 'A-2']);
    expect(inputs.first.unitCost, 12.5);
    expect(inputs.first.requiredQty, 4);
    expect(inputs.last.unitCost, isNull);
    expect(inputs.last.followUpRole, 'purchase');
    expect(
      inputs.every((r) => r.inventoryNote == 'Company stock review'),
      isTrue,
    );
    expect(inputs.every((r) => r.manualProduct == null), isTrue);
  });

  testWidgets('new company accepts manual product without code or cost', (
    tester,
  ) async {
    final repository = _FakeItemsTrackerRepository();
    await pumpPage(
      tester,
      role: ItemsTrackerRoles.inventory,
      repository: repository,
    );
    await tester.tap(find.byKey(const ValueKey('itemsTrackerAddItem')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Company products'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('companyEntrySearch')),
      'New Company',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('companyEntryUseName')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('companyEntryManual')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('manualProductName')),
      'Missing product',
    );
    await tester.enterText(
      find.byKey(const ValueKey('manualProductCategory')),
      'medicine',
    );
    await tester.tap(find.byKey(const ValueKey('manualProductAdd')));
    await tester.pumpAndSettle();
    expect(find.text('MANUAL PRODUCT'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('companyEntrySave')));
    await tester.pumpAndSettle();
    final input = repository.batches.single.single;
    expect(input.itemCode, isEmpty);
    expect(input.manualProduct!.itemName, 'Missing product');
    expect(input.manualProduct!.company, 'New Company');
    expect(input.manualProduct!.category, 'MEDICINE');
    expect(input.unitCost, isNull);
    expect(input.followUpRole, 'purchase');
  });

  testWidgets('company validates cost and retains entries after failed save', (
    tester,
  ) async {
    final repository = _FakeItemsTrackerRepository()..failBatch = true;
    await openCompany(tester, repository);
    await tester.enterText(
      find.byKey(const ValueKey('companyCost:0')),
      'invalid',
    );
    await tester.tap(find.byKey(const ValueKey('companyEntrySave')));
    await tester.pumpAndSettle();
    expect(find.textContaining('cost must be a valid'), findsOneWidget);
    expect(repository.batches, isEmpty);
    await tester.enterText(find.byKey(const ValueKey('companyCost:0')), '0');
    await tester.tap(find.byKey(const ValueKey('companyEntrySave')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Your entries are kept'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('companyCost:0')))
          .controller!
          .text,
      '0',
    );
    repository.failBatch = false;
    await tester.tap(find.byKey(const ValueKey('companyEntrySave')));
    await tester.pumpAndSettle();
    expect(repository.batches.single.first.unitCost, 0);
    expect(repository.batches.single.last.unitCost, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('single product choice retains catalog editor', (tester) async {
    await pumpPage(tester, role: ItemsTrackerRoles.inventory);
    await tester.tap(find.byKey(const ValueKey('itemsTrackerAddItem')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Single product'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('itemsTrackerProductSearch')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('itemsTrackerUnitCost')), findsOneWidget);
    expect(find.byKey(const ValueKey('itemEmailOnAdd')), findsOneWidget);
  });

  testWidgets(
    'single product can prepare email only after successful addition',
    (tester) async {
      final repository = _FakeItemsTrackerRepository(
        products: const [
          ItemsTrackerProduct(
            itemCode: 'SAMPLE',
            itemName: 'Sample product',
            category: 'COSMETICS',
            supplier: 'Supplier',
            company: 'Company',
            itemStatus: '1#NORMAL PURCHASE',
            retailPrice: null,
          ),
        ],
      );
      await pumpPage(
        tester,
        role: ItemsTrackerRoles.inventory,
        repository: repository,
      );
      await tester.tap(find.byKey(const ValueKey('itemsTrackerAddItem')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Single product'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('itemsTrackerProductSearch')),
        'Sample',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Sample product'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('itemsTrackerRequiredQty')),
        '12',
      );
      await tester.enterText(
        find.byKey(const ValueKey('itemsTrackerInventoryNote')),
        'Return excess stock',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('itemEmailOnAdd')));
      await tester.tap(find.byKey(const ValueKey('itemEmailOnAdd')));
      await tester.pumpAndSettle();
      expect(repository.emailRequests, isEmpty);
      await tester.tap(find.byKey(const ValueKey('itemsTrackerDialogSave')));
      await tester.pumpAndSettle();
      expect(
        repository.createdRecords.single.inventoryNote,
        'Return excess stock',
      );
      expect(repository.emailRequests.single, ['new-item']);
      expect(repository.emailCompanies.single, isNull);
      expect(find.text('Send email with Outlook'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(repository.createdRecords, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'company email failure keeps saved products and does not create them again',
    (tester) async {
      final repository = _FakeItemsTrackerRepository()
        ..failEmailPreparation = true;
      await openCompany(tester, repository);
      await tester.tap(find.byKey(const ValueKey('companyEmailOnAdd')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('companyEntrySave')));
      await tester.pumpAndSettle();
      expect(repository.batches, hasLength(1));
      expect(repository.emailRequests.single, [
        'new-item-0',
        'new-item-1',
        'new-item-2',
      ]);
      expect(repository.emailCompanies.single, 'Example Company');
      expect(find.text('Send email with Outlook'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(repository.batches, hasLength(1));
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Add company products'), findsNothing);
      expect(repository.batches, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'email buttons belong only to Inventory including other assigned teams',
    (tester) async {
      final records = [
        ItemsTrackerRecord.fromMap({
          'id': 'category-product',
          'item_name': 'Assigned to category',
          'category': 'MEDICINE',
          'follow_up_role': 'category',
        }),
        ItemsTrackerRecord.fromMap({
          'id': 'already-sent',
          'item_name': 'Already emailed',
          'category': 'MEDICINE',
          'follow_up_role': 'purchase',
          'email_status': 'sent',
        }),
        ItemsTrackerRecord.fromMap({
          'id': 'saved-draft',
          'item_name': 'Existing draft',
          'category': 'MEDICINE',
          'follow_up_role': 'inventory',
          'email_status': 'draft',
        }),
        for (var i = 1; i <= 2; i++)
          ItemsTrackerRecord.fromMap({
            'id': 'company-$i',
            'item_name': 'Grouped $i',
            'company': 'Mail company',
            'category': 'COSMETICS',
            'follow_up_role': 'category',
          }),
      ];
      final repository = _FakeItemsTrackerRepository(records: records);
      for (final role in ItemsTrackerRoles.allowed) {
        await tester.pumpWidget(const SizedBox.shrink());
        await pumpPage(tester, role: role, repository: repository);
        expect(
          find.byKey(const ValueKey('productEmail:category-product')),
          role == 'inventory' ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const ValueKey('companyEmail:mail company:category')),
          role == 'inventory' ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const ValueKey('productEmail:already-sent')),
          findsNothing,
        );
        expect(
          find.text('Sent'),
          role == 'inventory' ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const ValueKey('productEmail:saved-draft')),
          role == 'inventory' ? findsOneWidget : findsNothing,
        );
      }
    },
  );

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

  ItemsTrackerActionFile importFile({bool empty = false}) =>
      ItemsTrackerActionFile(
        blankRows: 1,
        issues: const [],
        rows: empty
            ? []
            : [
                const ItemsTrackerActionImport(
                  excelRow: 6,
                  itemId: '11111111-1111-4111-8111-111111111111',
                  itemCode: 'A',
                  itemName: 'Ready product',
                  body: 'New action from Excel',
                  actionDate: null,
                  expectedVersion: 7,
                  importToken: '11111111-1111-4111-8111-222222222222',
                ),
                const ItemsTrackerActionImport(
                  excelRow: 7,
                  itemId: '22222222-2222-4222-8222-222222222222',
                  itemCode: 'B',
                  itemName: 'Changed inside system',
                  body: 'Stale file action',
                  actionDate: null,
                  expectedVersion: 2,
                  importToken: '22222222-2222-4222-8222-333333333333',
                ),
              ],
      );

  Future<void> pumpImport(
    WidgetTester tester,
    _FakeItemsTrackerRepository repository, {
    bool empty = false,
  }) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ItemsTrackerImportDialog(
            repository: repository,
            file: importFile(empty: empty),
            fileName: 'Actions.xlsx',
            role: 'purchase',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'import preview saves only ready actions and skips system conflicts',
    (tester) async {
      final repository = _FakeItemsTrackerRepository()
        ..importStatuses[7] = 'conflict';
      await pumpImport(tester, repository);
      expect(find.text('1 ready'), findsOneWidget);
      expect(find.text('1 blank actions ignored'), findsOneWidget);
      expect(find.text('System changed'), findsOneWidget);
      expect(repository.importedActions, isEmpty);
      await tester.tap(find.byKey(const ValueKey('itemsTrackerConfirmImport')));
      await tester.pumpAndSettle();
      expect(repository.importedActions.single.single.itemCode, 'A');
      expect(
        repository.importedActions.single.single.body,
        'New action from Excel',
      );
      expect(find.text('1 imported'), findsOneWidget);
      expect(find.text('System changed'), findsOneWidget);
    },
  );

  testWidgets(
    'changes during import remain conflicts instead of being overwritten',
    (tester) async {
      final repository = _FakeItemsTrackerRepository()
        ..importStatuses[7] = 'conflict'
        ..importConflictDuringSave = true;
      await pumpImport(tester, repository);
      await tester.tap(find.byKey(const ValueKey('itemsTrackerConfirmImport')));
      await tester.pumpAndSettle();
      expect(find.text('0 imported'), findsOneWidget);
      expect(find.text('System changed'), findsNWidgets(2));
      expect(repository.importedActions.single.single.expectedVersion, 7);
    },
  );

  testWidgets('blank file has no import operation', (tester) async {
    final repository = _FakeItemsTrackerRepository();
    await pumpImport(tester, repository, empty: true);
    expect(
      find.text(
        'No written actions found. All current system data will be kept.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('itemsTrackerConfirmImport')),
          )
          .onPressed,
      isNull,
    );
    expect(repository.importedActions, isEmpty);
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
        'follow_up_role': 'purchase',
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
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('itemCard:item-2'))).dy,
      greaterThan(
        tester.getTopLeft(find.byKey(const ValueKey('itemCard:item-1'))).dy,
      ),
    );
  });

  testWidgets('shows personal tracker notifications from the bell', (
    tester,
  ) async {
    final notification = ItemsTrackerNotification(
      id: 1,
      itemId: 'item-1',
      activityType: 'comment',
      actorName: 'Sarah',
      actorRole: 'category',
      itemCode: '16-02-12216',
      itemName: 'Test item',
      title: 'Sarah added a comment',
      preview: 'Please confirm the supplier.',
      createdAt: DateTime(2026, 8, 24),
      readAt: null,
    );

    await pumpPage(
      tester,
      role: ItemsTrackerRoles.inventory,
      repository: _FakeItemsTrackerRepository(notifications: [notification]),
    );

    await tester.tap(find.byKey(const ValueKey('itemsTrackerNotifications')));
    await tester.pumpAndSettle();

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Sarah added a comment'), findsOneWidget);
    expect(find.text('16-02-12216 · Test item'), findsOneWidget);
  });

  testWidgets('groups products by company and opens product details', (
    tester,
  ) async {
    final records = [
      for (var i = 1; i <= 2; i++)
        ItemsTrackerRecord.fromMap({
          'id': 'item-$i',
          'item_code': 'CODE-$i',
          'item_name': 'Product $i',
          'company': 'Acme',
          'supplier': 'Supplier $i',
          'inventory_note': 'Reason $i',
          'case_status': i == 1 ? 'done' : 'pending',
          'required_qty': i * 10,
          'unit_cost_snapshot': 5,
          'follow_up_role': 'inventory',
          'created_at': '2026-08-14T08:00:00Z',
        }),
    ];
    await pumpPage(
      tester,
      role: ItemsTrackerRoles.inventory,
      repository: _FakeItemsTrackerRepository(records: records),
    );

    expect(
      find.byKey(const ValueKey('company:acme:inventory')),
      findsOneWidget,
    );
    await tester.tap(find.text('Acme'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('itemCard:item-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('itemCard:item-2')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('itemCard:item-1'))).dy,
      greaterThan(
        tester.getTopLeft(find.byKey(const ValueKey('itemCard:item-2'))).dy,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('itemCard:item-1')));
    await tester.pumpAndSettle();
    expect(find.text('Supplier 1'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('itemDetailsPanel:item-1')),
      findsOneWidget,
    );
    expect(find.text('Quantity'), findsNothing);
  });

  testWidgets('company action writes a scoped entry to every product', (
    tester,
  ) async {
    final repository = _FakeItemsTrackerRepository(
      records: [
        for (var i = 1; i <= 2; i++)
          ItemsTrackerRecord.fromMap({
            'id': 'item-$i',
            'item_code': 'CODE-$i',
            'item_name': 'Product $i',
            'company': 'Acme',
            'follow_up_role': 'inventory',
            'created_at': '2026-08-14T08:00:00Z',
          }),
        ItemsTrackerRecord.fromMap({
          'id': 'medicine',
          'item_name': 'Medicine product',
          'company': 'Acme',
          'category': ' medicine ',
          'follow_up_role': 'inventory',
          'created_at': '2026-08-14T08:00:00Z',
        }),
        for (var i = 1; i <= 2; i++)
          ItemsTrackerRecord.fromMap({
            'id': 'category-$i',
            'item_name': 'Category product $i',
            'company': 'Acme',
            'category': 'COSMETICS',
            'follow_up_role': 'category',
            'created_at': '2026-08-14T08:00:00Z',
          }),
      ],
    );
    await pumpPage(
      tester,
      role: ItemsTrackerRoles.inventory,
      repository: repository,
    );
    expect(
      find.byKey(const ValueKey('company:acme:inventory')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('company:acme:category')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('companyAction:acme:category')),
      findsNothing,
    );
    await tester.tap(
      find.byKey(const ValueKey('companyAction:acme:inventory')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Called supplier');
    await tester.tap(find.text('Save company action'));
    await tester.pumpAndSettle();
    expect(repository.actions, hasLength(2));
    expect(
      repository.actions.every(
        (action) =>
            action.body ==
            '[Company action: Acme | Follow up by: Inventory | Non-medicine products] Called supplier',
      ),
      isTrue,
    );
    expect(
      repository.actions.any((action) => action.itemId == 'medicine'),
      isFalse,
    );
    expect(
      repository.actions.every((action) => action.itemId.startsWith('item-')),
      isTrue,
    );
  });

  testWidgets(
    'company grouping separates teams and keeps a lone team product independent',
    (tester) async {
      final records = [
        ItemsTrackerRecord.fromMap({
          'id': 'inventory-single',
          'item_name': 'Inventory product',
          'company': 'Acme',
          'category': 'COSMETICS',
          'follow_up_role': 'inventory',
          'created_at': '2026-08-14T08:00:00Z',
        }),
        for (var i = 1; i <= 2; i++)
          ItemsTrackerRecord.fromMap({
            'id': 'category-$i',
            'item_name': 'Category product $i',
            'company': i == 1 ? 'Acme' : ' ACME ',
            'category': 'COSMETICS',
            'follow_up_role': i == 1 ? 'category' : ' CATEGORY ',
            'created_at': '2026-08-14T08:00:00Z',
          }),
      ];
      await pumpPage(
        tester,
        role: ItemsTrackerRoles.inventory,
        repository: _FakeItemsTrackerRepository(records: records),
      );
      final group = find.byKey(const ValueKey('company:acme:category'));
      expect(group, findsOneWidget);
      expect(
        find.byKey(const ValueKey('company:acme:inventory')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('itemCard:inventory-single')),
        findsOneWidget,
      );
      await tester.tap(find.text('Acme'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: group,
          matching: find.byKey(const ValueKey('itemCard:inventory-single')),
        ),
        findsNothing,
      );
      for (var i = 1; i <= 2; i++) {
        expect(
          find.descendant(
            of: group,
            matching: find.byKey(ValueKey('itemCard:category-$i')),
          ),
          findsOneWidget,
        );
      }
      expect(find.text('2 products'), findsOneWidget);
    },
  );

  testWidgets('single products and medicine stay as independent rows', (
    tester,
  ) async {
    final repository = _FakeItemsTrackerRepository(
      records: [
        ItemsTrackerRecord.fromMap({
          'id': 'single',
          'item_name': 'Single product',
          'company': 'Only one',
          'category': 'COSMETICS',
          'required_qty': 35,
          'unit_cost_snapshot': 12.5,
          'inventory_note': 'Restock branches',
          'latest_activity_body': 'Supplier confirmed',
          'latest_activity_by_name': 'Sarah',
          'latest_comment': 'Supplier asked for the batch details',
          'comment_by_name': 'Huda',
          'comment_count': 2,
          'supplier': 'Hidden supplier',
          'follow_up_role': 'inventory',
          'created_at': '2026-08-14T08:00:00Z',
        }),
        for (var i = 1; i <= 2; i++)
          ItemsTrackerRecord.fromMap({
            'id': 'med-$i',
            'item_name': 'Medicine $i',
            'company': 'Medicine company',
            'category': i == 1 ? 'MEDICINE' : ' medicine ',
            'follow_up_role': i == 1 ? 'purchase' : 'category',
            'latest_activity_body': i == 1 ? 'Follow-up: Created ->' : '',
            'created_at': '2026-08-14T08:00:00Z',
          }),
        for (var i = 1; i <= 2; i++)
          ItemsTrackerRecord.fromMap({
            'id': 'mixed-$i',
            'item_name': 'Mixed company product $i',
            'company': 'Mixed company',
            'category': i == 1 ? 'COSMETICS' : 'MEDICINE',
            'follow_up_role': 'inventory',
            'created_at': '2026-08-14T08:00:00Z',
          }),
      ],
    );
    await pumpPage(
      tester,
      role: ItemsTrackerRoles.inventory,
      repository: repository,
    );
    expect(
      find.byKey(const ValueKey('company:only one:inventory')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('company:mixed company:inventory')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('company:medicine company:purchase')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('company:medicine company:category')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('itemCard:single')), findsOneWidget);
    expect(find.byKey(const ValueKey('itemCard:med-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('itemCard:med-2')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('followUpBy:med-1')),
        matching: find.text('Purchase'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('followUpBy:med-2')),
        matching: find.text('Category'),
      ),
      findsOneWidget,
    );
    expect(find.text('Follow-up: Created ->'), findsNothing);
    expect(find.text('Awaiting first action'), findsWidgets);
    for (final title in [
      'COST',
      'QUANTITY',
      'REASON',
      'ACTION',
      'ACTION BY',
      'COMMENT',
      'COMMENT BY',
      'FOLLOW UP BY',
    ]) {
      expect(find.text(title), findsOneWidget);
    }
    for (final value in [
      'AED 12.50',
      '35',
      'Restock branches',
      'Supplier confirmed',
      'Sarah',
      'Supplier asked for the batch details',
      'Huda',
    ]) {
      expect(find.text(value), findsOneWidget);
    }
    expect(find.text('Hidden supplier'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('followUpBy:single')),
        matching: find.text('Inventory'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('itemCard:single')));
    await tester.pumpAndSettle();
    final panel = find.byKey(const ValueKey('itemDetailsPanel:single'));
    expect(tester.getRect(panel).right, 1920);
    expect(tester.getSize(panel).width, 480);
    expect(find.text('Hidden supplier'), findsOneWidget);
  });
}

class _FakeItemsTrackerRepository implements ItemsTrackerRepository {
  final List<ItemsTrackerRecord> records;
  final List<ItemsTrackerNotification> notifications;
  final List<ItemsTrackerProduct> products;
  final List<CreateItemsTrackerRecord> createdRecords = [];
  final List<AddItemsTrackerAction> actions = [];
  final List<List<CreateItemsTrackerRecord>> batches = [];
  bool failBatch = false;
  final Map<int, String> importStatuses = {};
  final List<List<ItemsTrackerActionImport>> importedActions = [];
  bool importConflictDuringSave = false;
  bool failEmailPreparation = false;
  final List<List<String>> emailRequests = [];
  final List<String?> emailCompanies = [];

  _FakeItemsTrackerRepository({
    this.records = const [],
    this.notifications = const [],
    this.products = const [],
  });

  @override
  Future<List<ItemsTrackerRecord>> fetchRecords() async => records;

  @override
  Future<List<String>> fetchItemStatuses() async => const [
    '1#NORMAL PURCHASE',
    '2#PR',
  ];

  @override
  Future<List<ItemsTrackerNotification>> fetchNotifications() async =>
      notifications;

  @override
  Future<void> markNotificationRead(int notificationId) async {}

  @override
  Future<void> markAllNotificationsRead() async {}

  @override
  Future<List<ItemsTrackerProduct>> searchProducts(String query) async =>
      products;

  @override
  Future<List<ItemsTrackerTimelineEntry>> fetchTimeline(String itemId) async =>
      const [];

  @override
  Future<String> createRecord(CreateItemsTrackerRecord input) async {
    createdRecords.add(input);
    return 'new-item';
  }

  @override
  Future<List<String>> createRecords(
    List<CreateItemsTrackerRecord> inputs,
  ) async {
    if (failBatch) throw StateError('Save failed');
    batches.add(inputs);
    return List.generate(inputs.length, (index) => 'new-item-$index');
  }

  @override
  Future<List<ItemsTrackerEmailDraft>> prepareEmails(
    List<String> itemIds, {
    String? company,
  }) async {
    emailRequests.add(itemIds);
    emailCompanies.add(company);
    if (failEmailPreparation) throw StateError('Could not prepare email');
    return [];
  }

  @override
  Future<bool> openEmailDraft(String emailId, {bool reopen = false}) async =>
      true;
  @override
  Future<void> releaseEmailDraft(String emailId) async {}
  @override
  Future<void> confirmEmailSent(String emailId) async {}
  @override
  Future<void> cancelEmailDraft(String emailId) async {}

  @override
  Future<List<ItemsTrackerActionImportResult>> importActions(
    List<ItemsTrackerActionImport> rows, {
    required String fileName,
    bool apply = false,
  }) async {
    if (apply) importedActions.add(rows);
    return rows
        .map(
          (row) => ItemsTrackerActionImportResult(
            excelRow: row.excelRow,
            status: apply
                ? (importConflictDuringSave ? 'conflict' : 'imported')
                : (importStatuses[row.excelRow] ?? 'ready'),
            message: 'System data kept for conflicting rows.',
          ),
        )
        .toList();
  }

  @override
  Future<List<ItemsTrackerCompany>> searchCompanies(String query) async =>
      'Example Company'.toLowerCase().contains(query.trim().toLowerCase())
      ? [const ItemsTrackerCompany(name: 'Example Company', productCount: 3)]
      : [];

  @override
  Future<List<ItemsTrackerProduct>> fetchCompanyProducts(
    String company,
  ) async => company == 'Example Company'
      ? List.generate(
          3,
          (i) => ItemsTrackerProduct(
            itemCode: 'A-${i + 1}',
            itemName: 'Example product ${i + 1}',
            category: i == 1 ? 'MEDICINE' : 'COSMETICS',
            supplier: 'Supplier',
            company: company,
            itemStatus: '1#NORMAL PURCHASE',
            retailPrice: 99,
          ),
        )
      : [];

  @override
  Future<void> updateInventoryFields(UpdateItemsTrackerRecord input) async {}

  @override
  Future<void> updateStatusUpdatedTo(UpdateItemsTrackerStatus input) async {}

  @override
  Future<void> updateTrackerStatus(UpdateItemsTrackerCaseStatus input) async {}

  @override
  Future<void> addAction(AddItemsTrackerAction input) async {
    actions.add(input);
  }

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
