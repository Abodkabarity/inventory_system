import 'package:daily_order/domain/entities/items_tracker_email.dart';
import 'package:daily_order/domain/entities/items_tracker_record.dart';
import 'package:daily_order/domain/repositories/items_tracker_repository.dart';
import 'package:daily_order/presentation/items_tracker/widgets/items_tracker_email_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';

ItemsTrackerEmailDraft draft({
  String status = 'draft',
  DateTime? openedAt,
  String role = 'category',
  String scope = 'product',
  String? reason,
}) => ItemsTrackerEmailDraft(
  id: 'email-1',
  status: status,
  scope: scope,
  company: 'Company & Co',
  followUpRole: role,
  openedAt: openedAt,
  products: [
    ItemsTrackerEmailProduct(
      id: 'item-1',
      name: 'Product #1 + cream',
      reason: reason ?? 'Slow moving & near expiry\nReturn 12 pcs',
      followUpRole: role,
      code: 'P001',
      company: 'Company & Co',
      supplier: 'Supplier',
      quantity: 12,
      cost: 3.5,
      total: 42,
      status: '1#NORMAL PURCHASE',
    ),
  ],
);

class _EmailRepository implements ItemsTrackerRepository {
  List<ItemsTrackerEmailDraft> drafts;
  int opens = 0, confirms = 0, releases = 0;
  bool confirmFails = false, prepareFails = false, openAllowed = true;
  List<String>? requestedIds;
  String? requestedCompany;
  _EmailRepository(this.drafts);
  @override
  Future<List<ItemsTrackerEmailDraft>> prepareEmails(
    List<String> itemIds, {
    String? company,
    bool exactSelection = false,
  }) async {
    requestedIds = itemIds;
    requestedCompany = company;
    if (prepareFails) throw StateError('Connection unavailable');
    return drafts;
  }

  @override
  Future<bool> openEmailDraft(String emailId, {bool reopen = false}) async {
    opens++;
    return openAllowed;
  }

  @override
  Future<void> releaseEmailDraft(String emailId) async {
    releases++;
  }

  @override
  Future<void> confirmEmailSent(String emailId) async {
    confirms++;
    if (confirmFails) throw StateError('Confirmation could not be saved');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() async {
    final root = Platform.environment['TRACKER_FONT_ROOT'];
    if (root == null) return;
    final font = FontLoader('Roboto');
    for (final name in ['roboto-regular.ttf', 'roboto-bold.ttf']) {
      font.addFont(
        Future.value(
          ByteData.sublistView(File('$root/$name').readAsBytesSync()),
        ),
      );
    }
    await font.load();
    await (FontLoader('MaterialIcons')..addFont(
          Future.value(
            ByteData.sublistView(
              File('$root/MaterialIcons-Regular.otf').readAsBytesSync(),
            ),
          ),
        ))
        .load();
  });
  test('formatted table includes prices and escapes product data', () {
    final email = draft(reason: '<script>bad()</script> & سبب\nSecond line');
    expect(email.htmlBody, contains('<table'));
    expect(email.htmlBody, contains('Cost (AED)'));
    expect(email.htmlBody, contains('42.00'));
    expect(email.htmlBody, contains('Qty'));
    expect(email.htmlBody, contains('&lt;script&gt;bad()&lt;&#47;script&gt;'));
    expect(email.htmlBody, isNot(contains('<script>')));
    expect(email.body, contains('Qty: 12'));
    expect(email.body, contains('Cost (AED): 3.50'));
    expect(email.totalLabel, 'Total: AED 42.00');
  });

  test(
    'EML preserves UTF-8 table, plain fallback and folded header limits',
    () {
      final email = draft(reason: 'تفاصيل المنتج & السعر');
      final eml = email.eml;
      expect(eml, contains('X-Unsent: 1\r\n'));
      final encodedWords = RegExp(
        r'=\?UTF-8\?B\?([^?]+)\?=',
      ).allMatches(eml).toList();
      expect(
        encodedWords.map((m) => utf8.decode(base64.decode(m[1]!))).join(),
        email.subject,
      );
      expect(encodedWords.every((m) => m[0]!.length <= 75), isTrue);
      final payloads = RegExp(
        r'Content-Transfer-Encoding: base64\r\n\r\n([\s\S]*?)\r\n--',
      ).allMatches(eml).toList();
      expect(payloads, hasLength(2));
      final decoded = payloads
          .map(
            (m) =>
                utf8.decode(base64.decode(m[1]!.replaceAll(RegExp(r'\s'), ''))),
          )
          .toList();
      expect(decoded, [email.body, email.htmlBody]);
    },
  );

  test('legacy draft costs remain unavailable instead of invented', () {
    final email = ItemsTrackerEmailDraft.fromMap({
      'id': 'old',
      'status': 'draft',
      'scope': 'product',
      'follow_up_role': 'purchase',
      'products': [
        {'id': 'old-item', 'name': 'Old product', 'reason': 'Review'},
      ],
    });
    expect(email.products.single.quantity, isNull);
    expect(email.products.single.cost, isNull);
    expect(email.products.single.cells, contains('—'));
    expect(email.hasCompleteTotal, isFalse);
    expect(email.body, contains('some costs are unavailable'));
  });
  test('exact To and CC department routing', () {
    final category = ItemsTrackerEmailRecipients.forRole(' CATEGORY ');
    expect(category.to, [
      'doaa.hassan@alain-pharmacy.com',
      'Saria.Bahaa@alain-pharmacy.com',
    ]);
    expect(category.cc, [
      'Inventory@alain-pharmacy.com',
      'ahmad.alkouz@alain-pharmacy.com',
    ]);
    final purchase = ItemsTrackerEmailRecipients.forRole('purchase');
    expect(purchase.to, ['a.altamimi@alain-pharmacy.com']);
    expect(purchase.cc, [
      'Inventory@alain-pharmacy.com',
      'ahmad.alkouz@alain-pharmacy.com',
      'a.bittar@alain-pharmacy.com',
    ]);
    final inventory = ItemsTrackerEmailRecipients.forRole('inventory');
    expect(inventory.to, ['Inventory@alain-pharmacy.com']);
    expect(inventory.cc, ['ahmad.alkouz@alain-pharmacy.com']);
    expect(
      () => ItemsTrackerEmailRecipients.forRole('invalid'),
      throwsArgumentError,
    );
  });
  test(
    'Outlook URI preserves names, reasons, newlines and special characters',
    () {
      final email = draft(scope: 'company');
      final uri = email.outlookUri();
      expect(uri.scheme, 'mailto');
      expect(uri.path, email.recipients.to.join(';'));
      expect(uri.queryParameters['cc'], email.recipients.cc.join(';'));
      expect(uri.queryParameters['subject'], email.subject);
      expect(uri.queryParameters['body'], email.body);
      expect(email.body, contains('Company: Company & Co'));
      expect(email.body, contains('Product: Product #1 + cream'));
      expect(
        email.body,
        contains('Reason: Slow moving & near expiry\nReturn 12 pcs'),
      );
      expect(
        email
            .outlookUri(includeBody: false)
            .queryParameters
            .containsKey('body'),
        isFalse,
      );
    },
  );
  test('only confirmed sent state disables record email', () {
    for (final status in ['', 'draft', 'sent']) {
      final record = ItemsTrackerRecord.fromMap({
        'id': 'item-1',
        'email_status': status,
      });
      expect(record.emailSent, status == 'sent');
      expect(record.canSendEmail, status != 'sent');
    }
  });

  Future<void> pumpEmail(
    WidgetTester tester,
    _EmailRepository repository,
    Future<bool> Function(Uri) launcher, {
    String? company,
    Future<bool> Function(ItemsTrackerEmailDraft)? downloader,
    GlobalKey? boundary,
  }) async {
    tester.view.physicalSize = const Size(1100, 1050);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            fontFamily: Platform.environment['TRACKER_FONT_ROOT'] == null
                ? null
                : 'Roboto',
          ),
          home: Scaffold(
            body: ItemsTrackerEmailDialog(
              repository: repository,
              itemIds: const ['item-1'],
              company: company,
              outlookLauncher: launcher,
              draftDownloader: downloader,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('opening Outlook never marks sent, confirmation does', (
    tester,
  ) async {
    final repository = _EmailRepository([draft()]);
    final launched = <Uri>[];
    await pumpEmail(tester, repository, (uri) async {
      launched.add(uri);
      return true;
    });
    expect(repository.requestedIds, ['item-1']);
    expect(repository.opens, 0);
    expect(repository.confirms, 0);
    expect(find.text('Confirm sent'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('openEmail:email-1')));
    await tester.pumpAndSettle();
    expect(launched.single.queryParameters['body'], draft().body);
    expect(repository.confirms, 0);
    expect(find.text('Awaiting confirmation'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('confirmEmail:email-1')));
    await tester.pumpAndSettle();
    expect(repository.confirms, 1);
    expect(find.text('Email sent ✓'), findsOneWidget);
    expect(find.byKey(const ValueKey('openEmail:email-1')), findsNothing);
    expect(find.byKey(const ValueKey('confirmEmail:email-1')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'formatted download reserves the full draft and never marks it sent',
    (tester) async {
      final repository = _EmailRepository([draft()]);
      ItemsTrackerEmailDraft? downloaded;
      await pumpEmail(
        tester,
        repository,
        (_) async => throw StateError('No mailto launch'),
        downloader: (email) async {
          downloaded = email;
          return true;
        },
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('downloadEmail:email-1')),
      );
      await tester.tap(find.byKey(const ValueKey('downloadEmail:email-1')));
      await tester.pumpAndSettle();
      expect(downloaded!.eml, contains('multipart/alternative'));
      expect(repository.opens, 1);
      expect(repository.confirms, 0);
      expect(find.text('Confirm sent'), findsOneWidget);
      expect(find.textContaining('Outlook draft downloaded'), findsOneWidget);
    },
  );
  testWidgets('cancelled draft download releases the reservation', (
    tester,
  ) async {
    final repository = _EmailRepository([draft()]);
    await pumpEmail(
      tester,
      repository,
      (_) async => true,
      downloader: (_) async => false,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('downloadEmail:email-1')),
    );
    await tester.tap(find.byKey(const ValueKey('downloadEmail:email-1')));
    await tester.pumpAndSettle();
    expect(repository.releases, 1);
    expect(repository.confirms, 0);
    expect(find.text('Confirm sent'), findsNothing);
  });
  testWidgets(
    'failed Outlook launch releases handoff and retains unsent state',
    (tester) async {
      final repository = _EmailRepository([draft()]);
      await pumpEmail(tester, repository, (_) async => false);
      await tester.tap(find.byKey(const ValueKey('openEmail:email-1')));
      await tester.pumpAndSettle();
      expect(repository.releases, 1);
      expect(repository.confirms, 0);
      expect(find.textContaining('Could not open Outlook'), findsOneWidget);
      expect(find.byKey(const ValueKey('openEmail:email-1')), findsOneWidget);
      expect(find.text('Confirm sent'), findsNothing);
    },
  );
  testWidgets(
    'recovered opened draft requires confirmation without another launch',
    (tester) async {
      final repository = _EmailRepository([
        draft(openedAt: DateTime(2026, 10, 6)),
      ]);
      var launches = 0;
      await pumpEmail(tester, repository, (_) async {
        launches++;
        return true;
      });
      expect(launches, 0);
      expect(find.text('Confirm sent'), findsOneWidget);
      expect(find.text('Reopen unsent draft'), findsOneWidget);
      expect(find.text('Open in Outlook'), findsNothing);
    },
  );
  testWidgets('already sent email has no launch, cancel or confirm buttons', (
    tester,
  ) async {
    final repository = _EmailRepository([draft(status: 'sent')]);
    await pumpEmail(
      tester,
      repository,
      (_) async => throw StateError('Must not launch'),
    );
    expect(find.text('Email sent ✓'), findsOneWidget);
    for (final label in [
      'Open in Outlook',
      'Confirm sent',
      'Discard unsent draft',
    ]) {
      expect(find.text(label), findsNothing);
    }
    expect(repository.opens, 0);
  });
  testWidgets('failed confirmation never displays sent and can be retried', (
    tester,
  ) async {
    final repository = _EmailRepository([
      draft(openedAt: DateTime(2026, 10, 6)),
    ])..confirmFails = true;
    await pumpEmail(tester, repository, (_) async => true);
    await tester.tap(find.byKey(const ValueKey('confirmEmail:email-1')));
    await tester.pumpAndSettle();
    expect(find.text('Email sent ✓'), findsNothing);
    expect(find.text('Confirmation could not be saved'), findsOneWidget);
    repository.confirmFails = false;
    await tester.tap(find.byKey(const ValueKey('confirmEmail:email-1')));
    await tester.pumpAndSettle();
    expect(find.text('Email sent ✓'), findsOneWidget);
  });
  testWidgets(
    'long company email copies full text and opens bounded recipients URI',
    (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final email = draft(
        scope: 'company',
        reason: List.filled(100, 'سبب طويل مع كل التفاصيل &').join('\n'),
      );
      final repository = _EmailRepository([email]);
      Uri? launched;
      await pumpEmail(tester, repository, (uri) async {
        launched = uri;
        return true;
      }, company: email.company);
      await tester.ensureVisible(
        find.byKey(const ValueKey('openEmail:email-1')),
      );
      await tester.tap(find.byKey(const ValueKey('openEmail:email-1')));
      await tester.pumpAndSettle();
      expect(copied, email.body);
      expect(launched!.toString().length, lessThan(1800));
      expect(launched!.queryParameters.containsKey('body'), isFalse);
      expect(repository.requestedCompany, email.company);
      expect(find.textContaining('Full email text copied.'), findsOneWidget);
      expect(repository.confirms, 0);
    },
  );
  testWidgets('another user opening the same draft prevents another handoff', (
    tester,
  ) async {
    final repository = _EmailRepository([draft()])..openAllowed = false;
    var launches = 0;
    await pumpEmail(tester, repository, (_) async {
      launches++;
      return true;
    });
    repository.drafts = [draft(openedAt: DateTime(2026, 10, 6))];
    await tester.tap(find.byKey(const ValueKey('openEmail:email-1')));
    await tester.pumpAndSettle();
    expect(launches, 0);
    expect(repository.confirms, 0);
    expect(find.text('Confirm sent'), findsOneWidget);
  });

  testWidgets(
    'formatted preview is responsive and includes the full email table',
    (tester) async {
      final email = ItemsTrackerEmailDraft(
        id: 'preview-1',
        status: 'draft',
        scope: 'company',
        company: 'Example Healthcare',
        followUpRole: 'category',
        products: [
          const ItemsTrackerEmailProduct(
            id: 'p1',
            name: 'Hydrating Cream 100 ML',
            code: '16-01-00123',
            company: 'Example Healthcare',
            supplier: 'Example Supplier',
            category: 'COSMETICS',
            reason: 'Review excess stock and arrange supplier return.',
            followUpRole: 'category',
            quantity: 24,
            cost: 18.5,
            total: 444,
            status: '1#NORMAL PURCHASE',
          ),
          const ItemsTrackerEmailProduct(
            id: 'p2',
            name: 'Daily Face Wash 150 ML',
            code: '16-01-00456',
            company: 'Example Healthcare',
            reason: 'Confirm the next delivery date and update availability.',
            followUpRole: 'category',
            quantity: 12,
            cost: 22,
            total: 264,
            status: '2#PR',
          ),
        ],
      );
      final boundary = GlobalKey();
      await pumpEmail(
        tester,
        _EmailRepository([email]),
        (_) async => true,
        company: email.company,
        boundary: boundary,
      );
      expect(find.text('Total: AED 708.00'), findsOneWidget);
      expect(find.text('Cost (AED)'), findsOneWidget);
      Future<void> capture(String name) async {
        if (Platform.environment['UPDATE_TRACKER_EMAIL_PREVIEW'] != '1') return;
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final picture = await render.toImage();
          final bytes = await picture.toByteData(
            format: ui.ImageByteFormat.png,
          );
          await Directory('validation').create();
          await File(
            'validation/$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          picture.dispose();
        });
      }

      await capture('items_tracker_email_preview');
      tester.view.physicalSize = const Size(430, 800);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture('items_tracker_email_compact');
      if (Platform.environment['UPDATE_TRACKER_EMAIL_PREVIEW'] == '1') {
        await tester.runAsync(() async {
          await File(
            'validation/items_tracker_email_example.html',
          ).writeAsString(email.htmlBody);
          await File(
            'validation/items_tracker_email_example.eml',
          ).writeAsString(email.eml);
        });
      }
    },
  );
}
