import 'dart:async';
import 'dart:io';

import 'package:daily_order/core/utils/store_branch_identity_registry.dart';
import 'package:daily_order/data/datasources/remote/sales_report_remote_ds.dart';
import 'package:daily_order/presentation/inventory_dashboard/page/sales_report_page.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/sales_report_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _ReportRemote extends SalesReportRemoteDs {
  _ReportRemote({this.zonal = false})
    : super(
        SupabaseClient(
          'https://example.supabase.co',
          'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  final List<List<String>> requests = [];
  final bool zonal;
  bool ready = false;
  bool stale = false;
  bool awaitingDaily = false;
  bool dailyFailed = false;
  bool currentAvailable = false;
  bool include2025 = false;
  bool monthlyFailed = false;
  Completer<void>? nextMonthlyFetch;
  Completer<void>? nextDailyFetch;
  final List<List<String>> downloadedSelections = [];
  int dailyFetches = 0;
  int monthlyFetches = 0;
  int dailyRequests = 0;
  int dailyDownloads = 0;
  int monthlyDownloads = 0;
  Completer<Uri>? monthlyUrl;
  Completer<Uri>? dailyUrl;

  @override
  Future<Uri> downloadUrl(List<String> months) async {
    monthlyDownloads++;
    downloadedSelections.add(List.of(months));
    if (monthlyUrl != null) return monthlyUrl!.future;
    throw StateError('Test monthly download revalidation');
  }

  @override
  Future<Uri> downloadDailyUrl() async {
    dailyDownloads++;
    if (dailyUrl != null) return dailyUrl!.future;
    throw StateError("Test download revalidation");
  }

  @override
  Future<Map<String, dynamic>> fetchDaily({bool request = false}) async {
    dailyFetches++;
    final gate = nextDailyFetch;
    nextDailyFetch = null;
    if (gate != null) await gate.future;
    if (request) dailyRequests++;
    final from = DateTime(2026, 9, 18);
    return {
      'report_kind': 'daily45',
      'scope_kind': zonal ? 'zone' : 'inventory',
      'scope_label': zonal ? 'Zone1 + Zone2' : null,
      'metadata_current': true,
      'awaiting_update': awaitingDaily,
      'period_from': '2026-09-18',
      'period_through': '2026-11-01',
      'expected_through': '2026-11-01',
      'days': List.generate(
        45,
        (i) => from.add(Duration(days: i)).toIso8601String().substring(0, 10),
      ),
      'job': dailyRequests == 0
          ? null
          : {
              'status': dailyFailed
                  ? 'failed'
                  : ready
                  ? 'ready'
                  : 'uploading',
              'is_current': !stale,
              'byte_size': 1200000,
              'uploaded_bytes': ready ? 1200000 : 3000,
              'prepared_at': '2026-11-02T08:00:00Z',
            },
    };
  }

  @override
  Future<Map<String, dynamic>> fetch({
    List<String> months = const [],
    bool request = false,
  }) async {
    monthlyFetches++;
    final gate = nextMonthlyFetch;
    nextMonthlyFetch = null;
    if (gate != null) await gate.future;
    if (request) requests.add(List.of(months));
    return {
      'metadata_current': true,
      'scope_kind': zonal ? 'zone' : 'inventory',
      'scope_label': zonal ? 'Zone1 + Zone2' : null,
      'current_month': currentAvailable ? '11/2026' : null,
      'current_month_last_day': currentAvailable ? '2026-11-02' : null,
      'awaiting_update': months.contains('11/2026') && awaitingDaily,
      'months': [
        if (include2025) ...[
          {'month': '01/2025'},
          {'month': '12/2025'},
        ],
        if (currentAvailable) {'month': '11/2026', 'source': 'daily'},
        {'month': '01/2026', 'row_count': 3},
        {'month': '02/2026', 'row_count': 4},
      ],
      'job': requests.isEmpty || months.isEmpty
          ? null
          : {
              'status': monthlyFailed
                  ? 'failed'
                  : ready
                  ? 'ready'
                  : 'uploading',
              'is_current': !stale,
              'row_count': 7,
              'byte_size': 10000,
              'uploaded_bytes': ready ? 10000 : 3000,
              'prepared_at': '2026-11-02T08:00:00Z',
              'storage_path': ready && !stale ? 'report.csv' : null,
            },
    };
  }
}

List<String> _mockBrowserDownloads(WidgetTester tester) {
  final urls = <String>[];
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
    call,
  ) async {
    expectSync(call.method, 'launch');
    urls.add((call.arguments as Map)['url'] as String);
    return true;
  });
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    ),
  );
  return urls;
}

void main() {
  setUpAll(() async {
    final root = Platform.environment['FLUTTER_ROOT'] ?? 'C:/flutter';
    final directory = '$root/bin/cache/artifacts/material_fonts';
    for (final entry in {
      'Roboto': 'Roboto-Regular.ttf',
      'Ahem': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      final file = File('$directory/${entry.value}');
      if (file.existsSync()) {
        await (FontLoader(entry.key)..addFont(
              file.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
            ))
            .load();
      }
    }
  });
  test('server branch export examples match the shared Dart registry', () {
    const groups = {'ALPHA': '71', 'BETA': 'APG', '71 GAMMA': '71'};
    expect(
      StoreBranchIdentityRegistry.displayName('Alpha', groups),
      '71 Alpha',
    );
    expect(StoreBranchIdentityRegistry.displayName('Beta', groups), 'Beta');
    expect(
      StoreBranchIdentityRegistry.displayName('71 Gamma', groups),
      '71 Gamma',
    );
  });

  testWidgets(
    'multiple months request one server CSV; stale files disable download',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final remote = _ReportRemote();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SalesReportPage(dataSource: remote)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sales-month-01/2026')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sales-month-02/2026')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download CSV'));
      await tester.pump();
      expect(remote.requests, [
        ['01/2026', '02/2026'],
      ]);
      expect(find.text('Preparing your file'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('sales-report-primary-action')),
            )
            .onPressed,
        isNull,
      );
      remote.ready = true;
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Ready to download'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('sales-report-primary-action')),
            )
            .onPressed,
        isNotNull,
      );
      remote.stale = true;
      await tester.tap(find.byTooltip('Refresh status'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Update available'), findsOneWidget);
      expect(find.text('Download CSV'), findsOneWidget);
      expect(remote.monthlyDownloads, 1);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('sales-report-primary-action')),
            )
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final daily in [false, true]) {
    testWidgets(
      '${daily ? 'daily' : 'monthly'} download paints loading through delayed signing and browser handoff',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final remote = _ReportRemote()..ready = true;
        final url = Completer<Uri>();
        if (daily) {
          remote.dailyRequests = 1;
          remote.dailyUrl = url;
        } else {
          remote.requests.add(['01/2026']);
          remote.monthlyUrl = url;
        }
        final launched = Completer<bool>();
        var launches = 0;
        const channel = MethodChannel('plugins.flutter.io/url_launcher');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            expectSync(call.method, 'launch');
            launches++;
            return launched.future;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: SalesReportPage(dataSource: remote)),
          ),
        );
        await tester.pumpAndSettle();
        if (!daily) {
          await tester.tap(find.byKey(const ValueKey('sales-month-01/2026')));
          await tester.pumpAndSettle();
        }
        final button = find.byKey(
          ValueKey(
            daily ? 'sales-daily-download' : 'sales-report-primary-action',
          ),
        );
        await tester.tap(button);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          find.byKey(const ValueKey('sales-download-loading')),
          findsOneWidget,
        );
        expect(find.text('Starting your download'), findsOneWidget);
        expect(tester.widget<FilledButton>(button).onPressed, isNull);
        expect(daily ? remote.dailyDownloads : remote.monthlyDownloads, 1);
        await tester.pump(const Duration(seconds: 5));
        expect(
          find.byKey(const ValueKey('sales-download-loading')),
          findsOneWidget,
        );
        expect(launches, 0);
        url.complete(Uri.parse('https://example.com/report.csv'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(launches, 1);
        expect(
          find.byKey(const ValueKey('sales-download-loading')),
          findsOneWidget,
        );
        launched.complete(true);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('sales-download-loading')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('sales-download-requested')),
          findsOneWidget,
        );
        expect(
          find.textContaining("Check your browser's downloads"),
          findsOneWidget,
        );
        await tester.pump(const Duration(seconds: 20));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('sales-download-requested')),
          findsOneWidget,
        );
        expect(launches, 1);
        await tester.tap(find.byTooltip('Dismiss download notice'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('sales-download-requested')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'failed signing closes loading and allows another download attempt',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final remote = _ReportRemote()
        ..ready = true
        ..monthlyUrl = Completer<Uri>();
      remote.requests.add(['01/2026']);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SalesReportPage(dataSource: remote)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sales-month-01/2026')));
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('sales-report-primary-action'));
      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.byKey(const ValueKey('sales-download-loading')),
        findsOneWidget,
      );
      remote.monthlyUrl!.completeError(
        StateError('The source changed. Refresh and try again.'),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('sales-download-loading')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('sales-download-requested')),
        findsNothing,
      );
      expect(
        find.text('Unable to update the report. Please refresh and try again.'),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'one monthly click prepares all selected months and launches exactly once when ready',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final urls = _mockBrowserDownloads(tester);
      final remote = _ReportRemote()..monthlyUrl = Completer<Uri>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SalesReportPage(dataSource: remote)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('All months'));
      await tester.pumpAndSettle();
      expect(find.text('Prepare CSV'), findsNothing);
      final button = find.byKey(const ValueKey('sales-report-primary-action'));
      await tester.tap(button);
      await tester.pump(const Duration(milliseconds: 200));
      expect(remote.requests, [
        ['01/2026', '02/2026'],
      ]);
      expect(
        find.text(
          'Your download will start automatically. Keep this page open.',
        ),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      expect(remote.monthlyDownloads, 0);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 200));
      expect(remote.requests, hasLength(1));
      expect(urls, isEmpty);
      remote.ready = true;
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 200));
      expect(remote.monthlyDownloads, 1);
      expect(
        find.byKey(const ValueKey('sales-download-loading')),
        findsOneWidget,
      );
      remote.monthlyUrl!.complete(
        Uri.parse('https://example.com/combined.csv'),
      );
      await tester.pumpAndSettle();
      expect(urls, ['https://example.com/combined.csv']);
      expect(remote.downloadedSelections, [
        ['01/2026', '02/2026'],
      ]);
      await tester.pump(const Duration(seconds: 20));
      await tester.pumpAndSettle();
      expect(urls, hasLength(1));
      expect(remote.requests, hasLength(1));
      expect(
        find.byKey(const ValueKey('sales-download-requested')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'monthly click during a manual status refresh still sends its preparation request',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final urls = _mockBrowserDownloads(tester);
      final remote = _ReportRemote()
        ..monthlyUrl = (Completer<Uri>()
          ..complete(Uri.parse('https://example.com/report.csv')));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SalesReportPage(dataSource: remote)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sales-month-01/2026')));
      await tester.pumpAndSettle();
      final click = tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('sales-report-primary-action')),
          )
          .onPressed!;
      final poll = Completer<void>();
      remote.nextMonthlyFetch = poll;
      await tester.tap(find.byTooltip('Refresh status'));
      await tester.pump(const Duration(milliseconds: 100));
      click();
      await tester.pump(const Duration(milliseconds: 100));
      expect(remote.requests, isEmpty);
      poll.complete();
      await tester.pump(const Duration(milliseconds: 200));
      expect(remote.requests, [
        ['01/2026'],
      ]);
      remote.ready = true;
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(urls, hasLength(1));
      expect(remote.requests, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'changing month selection cancels the previous automatic download',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final urls = _mockBrowserDownloads(tester);
      final remote = _ReportRemote()
        ..monthlyUrl = (Completer<Uri>()
          ..complete(Uri.parse('https://example.com/new-selection.csv')));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SalesReportPage(dataSource: remote)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sales-month-01/2026')));
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('sales-report-primary-action'));
      await tester.tap(button);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byKey(const ValueKey('sales-month-02/2026')));
      await tester.pump(const Duration(milliseconds: 200));
      remote.ready = true;
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(remote.monthlyDownloads, 0);
      expect(urls, isEmpty);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(remote.downloadedSelections, [
        ['01/2026', '02/2026'],
      ]);
      expect(urls, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'failed monthly preparation releases the button and a retry still downloads automatically',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final urls = _mockBrowserDownloads(tester);
      final remote = _ReportRemote()
        ..monthlyFailed = true
        ..monthlyUrl = (Completer<Uri>()
          ..complete(Uri.parse('https://example.com/retry.csv')));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SalesReportPage(dataSource: remote)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sales-month-01/2026')));
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('sales-report-primary-action'));
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('Preparation interrupted'), findsOneWidget);
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(remote.requests, hasLength(1));
      expect(urls, isEmpty);
      remote.monthlyFailed = false;
      await tester.tap(button);
      await tester.pump(const Duration(milliseconds: 200));
      expect(remote.requests, hasLength(2));
      remote.ready = true;
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(urls, ['https://example.com/retry.csv']);
      expect(remote.monthlyDownloads, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final daily in [false, true]) {
    testWidgets(
      '${daily ? 'daily' : 'monthly'} stays idle until clicked, checks freshness and prepares a newer file in one click',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final urls = _mockBrowserDownloads(tester);
        final remote = _ReportRemote()
          ..ready = true
          ..dailyRequests = 1;
        remote.requests.add(['01/2026']);
        final file = Completer<Uri>()
          ..complete(Uri.parse('https://example.com/latest.csv'));
        if (daily) {
          remote.dailyUrl = file;
        } else {
          remote.monthlyUrl = file;
        }
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: SalesReportPage(dataSource: remote)),
          ),
        );
        await tester.pumpAndSettle();
        if (!daily) {
          await tester.tap(find.byKey(const ValueKey('sales-month-01/2026')));
          await tester.pumpAndSettle();
        }
        final reads = [remote.monthlyFetches, remote.dailyFetches];
        final button = find.byKey(
          ValueKey(
            daily ? 'sales-daily-download' : 'sales-report-primary-action',
          ),
        );
        final size = tester.getSize(button);
        await tester.pump(const Duration(minutes: 30));
        await tester.pumpAndSettle();
        expect([remote.monthlyFetches, remote.dailyFetches], reads);
        expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
        expect(tester.getSize(button), size);
        remote.ready = false;
        remote.stale = true;
        final check = Completer<void>();
        if (daily) {
          remote.nextDailyFetch = check;
        } else {
          remote.nextMonthlyFetch = check;
        }
        await tester.tap(button);
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Checking for updates…'), findsWidgets);
        expect(tester.widget<FilledButton>(button).onPressed, isNull);
        expect(urls, isEmpty);
        check.complete();
        await tester.pump(const Duration(milliseconds: 200));
        expect(daily ? remote.dailyDownloads : remote.monthlyDownloads, 0);
        expect(daily ? remote.dailyRequests : remote.requests.length, 2);
        final duringPreparation = daily
            ? remote.dailyFetches
            : remote.monthlyFetches;
        await tester.pump(const Duration(seconds: 5));
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          daily ? remote.dailyFetches : remote.monthlyFetches,
          greaterThan(duringPreparation),
        );
        expect(daily ? remote.dailyRequests : remote.requests.length, 2);
        remote.stale = false;
        remote.ready = true;
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(urls, ['https://example.com/latest.csv']);
        final finishedReads = [remote.monthlyFetches, remote.dailyFetches];
        await tester.pump(const Duration(minutes: 30));
        await tester.pumpAndSettle();
        expect([remote.monthlyFetches, remote.dailyFetches], finishedReads);
        expect(urls, hasLength(1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('daily click is retained while a manual refresh is in flight', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final urls = _mockBrowserDownloads(tester);
    final remote = _ReportRemote()
      ..dailyRequests = 1
      ..dailyUrl = (Completer<Uri>()
        ..complete(Uri.parse('https://example.com/daily.csv')));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SalesReportPage(dataSource: remote)),
      ),
    );
    await tester.pumpAndSettle();
    final poll = Completer<void>();
    remote.nextDailyFetch = poll;
    await tester.tap(find.byTooltip('Refresh status'));
    await tester.pump(const Duration(milliseconds: 100));
    final button = find.byKey(const ValueKey('sales-daily-download'));
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    await tester.tap(button);
    await tester.pump(const Duration(milliseconds: 100));
    expect(remote.dailyRequests, 1);
    poll.complete();
    await tester.pump(const Duration(milliseconds: 200));
    expect(remote.dailyRequests, 2);
    remote.ready = true;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(urls, ['https://example.com/daily.csv']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  const counts = [
    90693,
    85140,
    91425,
    89784,
    95708,
    93224,
    91997,
    89135,
    92891,
    92580,
  ];
  List<Map<String, dynamic>> previewMonths() => [
    for (var i = 0; i < counts.length; i++)
      {
        'month': '${(i + 1).toString().padLeft(2, '0')}/2026',
        'row_count': counts[i],
      },
  ];
  Widget preview({
    bool ready = false,
    String? currentMonth,
    String? lastDay,
    bool zonal = false,
    bool daily = false,
    bool awaiting = false,
    bool currentAvailable = false,
    bool archive2025 = false,
    bool monthlyWaiting = false,
    SalesReportDownloadPhase downloadPhase = SalesReportDownloadPhase.idle,
  }) => MaterialApp(
    theme: ThemeData(fontFamily: 'Roboto'),
    home: Scaffold(
      body: SalesReportWorkspace(
        downloadPhase: downloadPhase,
        onDismissDownloadNotice: () {},
        months: [
          if (archive2025)
            for (var month = 1; month <= 12; month++)
              {'month': '${month.toString().padLeft(2, '0')}/2025'},
          ...previewMonths(),
          if (currentAvailable && currentMonth != null)
            {'month': currentMonth, 'source': 'daily'},
        ],
        awaitingMonthlyUpdate: monthlyWaiting,
        selected: ready ? {'09/2026', '10/2026'} : {},
        job: ready
            ? {
                'status': 'ready',
                'is_current': true,
                'row_count': 185471,
                'byte_size': 26067955,
                'uploaded_bytes': 26067955,
                'prepared_at': '2026-11-02T08:00:00Z',
              }
            : null,
        loading: false,
        busy: false,
        metadataCurrent: true,
        error: null,
        onDailyDownload: () {},
        dailyJob: daily ? {'status': 'ready', 'is_current': true} : null,
        awaitingUpdate: awaiting,
        dailyFrom: '2026-09-18',
        dailyThrough: '2026-11-01',
        zonal: zonal,
        scopeLabel: zonal ? 'Zone1 + Zone2' : null,
        currentMonth: currentMonth,
        currentMonthLastDay: lastDay,
        onToggle: (_) {},
        onPreset: (_) {},
        onRefresh: () {},
        onDownload: () {},
      ),
    ),
  );

  testWidgets('desktop workspace stays at the top and matches the app theme', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(preview());
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Sales Report')).dy, lessThan(80));
    expect(
      find.textContaining(RegExp(r'rows|records', caseSensitive: false)),
      findsNothing,
    );
    await expectLater(
      find.byType(SalesReportWorkspace),
      matchesGoldenFile('goldens/sales_report_empty_desktop.png'),
    );
    await tester.pumpWidget(preview(ready: true));
    await tester.pumpAndSettle();
    expect(find.text('Sep — Oct 2026'), findsOneWidget);
    expect(
      find.textContaining(RegExp(r'rows|records', caseSensitive: false)),
      findsNothing,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('sales-report-primary-action')),
          )
          .style
          ?.backgroundColor
          ?.resolve({}),
      const Color(0xFF4EB0DE),
    );
    await expectLater(
      find.byType(SalesReportWorkspace),
      matchesGoldenFile('goldens/sales_report_desktop.png'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('calendar presets preserve a single combined request', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final remote = _ReportRemote();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SalesReportPage(dataSource: remote)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('All months'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
    await tester.tap(find.text('Download CSV'));
    await tester.pump();
    expect(remote.requests, [
      ['01/2026', '02/2026'],
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('narrow layout remains scrollable without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(preview(ready: true));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(
      find.byKey(const ValueKey('sales-report-primary-action')),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'current month shows its actual last sale day and keeps unavailable exports disabled',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1050);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        preview(currentMonth: '11/2026', lastDay: '2026-11-01'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Latest sale: 01 Nov'), findsOneWidget);
      expect(find.text('Export not available yet'), findsOneWidget);
      final november = find.byKey(const ValueKey('sales-month-11/2026'));
      expect(
        tester
            .widget<InkWell>(
              find.descendant(of: november, matching: find.byType(InkWell)),
            )
            .onTap,
        isNull,
      );
      await expectLater(
        find.byType(SalesReportWorkspace),
        matchesGoldenFile('goldens/sales_report_current_month.png'),
      );
      await tester.pumpWidget(
        preview(currentMonth: '11/2026', lastDay: '2026-10-31'),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Latest sale:'), findsNothing);
      await tester.pumpWidget(
        preview(currentMonth: '01/2027', lastDay: '2027-01-02'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Latest sale: 02 Jan'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'current daily month combines with history and only its selection waits for the morning import',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final remote = _ReportRemote(zonal: true)..currentAvailable = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SalesReportPage(dataSource: remote, zonal: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final november = find.byKey(const ValueKey('sales-month-11/2026'));
      expect(
        tester
            .widget<InkWell>(
              find.descendant(of: november, matching: find.byType(InkWell)),
            )
            .onTap,
        isNotNull,
      );
      expect(find.text('Latest sale: 02 Nov'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sales-month-02/2026')));
      await tester.pumpAndSettle();
      await tester.tap(november);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Retail and sales value are unavailable'),
        findsOneWidget,
      );
      await tester.tap(find.text('Download CSV'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(remote.requests, [
        ['02/2026', '11/2026'],
      ]);
      remote.ready = true;
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Download CSV'), findsOneWidget);
      remote.awaitingDaily = true;
      await tester.tap(find.byTooltip('Refresh status'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('sales-report-primary-action')),
            )
            .onPressed,
        isNull,
      );
      expect(find.text("Waiting for yesterday's sales"), findsOneWidget);
      await tester.tap(november);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('sales-report-primary-action')),
            )
            .onPressed,
        isNotNull,
      );
      expect(find.text('1 selected'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        preview(
          currentMonth: '11/2026',
          lastDay: '2026-11-02',
          currentAvailable: true,
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(SalesReportWorkspace),
        matchesGoldenFile('goldens/sales_report_current_month_available.png'),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'zonal page shares the design and submits one scoped month selection',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final remote = _ReportRemote(zonal: true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SalesReportPage(dataSource: remote, zonal: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('ZONE / REPORTS'), findsOneWidget);
      expect(
        find.text('Zone1 + Zone2 · Sales from your assigned branches only.'),
        findsOneWidget,
      );
      await tester.tap(find.text('All months'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download CSV'));
      await tester.pump();
      expect(remote.requests, [
        ['01/2026', '02/2026'],
      ]);
      await tester.pumpWidget(preview(ready: true, zonal: true));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(SalesReportWorkspace),
        matchesGoldenFile('goldens/sales_report_zonal_desktop.png'),
      );
      expect(
        find.textContaining(RegExp(r'rows|records', caseSensitive: false)),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'one daily button preserves month selection, starts a complete download and gates morning updates',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final remote = _ReportRemote(zonal: true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SalesReportPage(dataSource: remote, zonal: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sales-month-01/2026')));
      await tester.pumpAndSettle();
      expect(remote.dailyFetches, greaterThan(0));
      expect(find.byKey(const ValueKey('sales-month-01/2026')), findsOneWidget);
      expect(find.byKey(const ValueKey('sales-mode-daily')), findsNothing);
      expect(
        find.textContaining('01 Nov 2026 · Invoice dates included'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('sales-daily-download')));
      await tester.pump();
      expect(remote.dailyRequests, 1);
      expect(remote.requests, isEmpty);
      remote.dailyFailed = true;
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('sales-daily-download')),
            )
            .onPressed,
        isNotNull,
      );
      remote.dailyFailed = false;
      await tester.tap(find.byKey(const ValueKey('sales-daily-download')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(remote.dailyRequests, 2);
      remote.ready = true;
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(remote.dailyDownloads, 1);
      remote.awaitingDaily = true;
      await tester.tap(find.byTooltip('Refresh status'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(
        find.textContaining("Waiting for the daily sales update"),
        findsOneWidget,
      );
      expect(find.text('Download CSV'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('sales-daily-download')),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.byKey(const ValueKey('sales-month-01/2026')), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('sales-report-primary-action')),
            )
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'daily desktop and pending-update layouts match the shared theme',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(preview(ready: true, daily: true, zonal: true));
      await tester.pumpAndSettle();
      expect(find.text('Download Sales 45 Days'), findsOneWidget);
      expect(find.byKey(const ValueKey('sales-mode-daily')), findsNothing);
      expect(
        find.textContaining(RegExp(r'rows|records', caseSensitive: false)),
        findsNothing,
      );
      await expectLater(
        find.byType(SalesReportWorkspace),
        matchesGoldenFile('goldens/sales_report_daily_desktop.png'),
      );
      await tester.pumpWidget(
        preview(ready: true, daily: true, awaiting: true),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('sales-daily-download')),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(390, 1000);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(
        find.byKey(const ValueKey('sales-report-primary-action')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('download feedback matches the app theme on desktop and mobile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      preview(ready: true, downloadPhase: SalesReportDownloadPhase.starting),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(SalesReportWorkspace),
      matchesGoldenFile('goldens/sales_report_download_loading.png'),
    );
    tester.view.physicalSize = const Size(390, 850);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      preview(ready: true, downloadPhase: SalesReportDownloadPhase.requested),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(SalesReportWorkspace),
      matchesGoldenFile('goldens/sales_report_download_requested_mobile.png'),
    );
  });
  testWidgets(
    '2025 year selector preserves a cross-year request and scopes presets to the displayed year',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final urls = _mockBrowserDownloads(tester);
      final remote = _ReportRemote()
        ..include2025 = true
        ..ready = true
        ..monthlyUrl = (Completer<Uri>()
          ..complete(Uri.parse('https://example.com/cross-year.csv')));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SalesReportPage(dataSource: remote)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sales-month-01/2026')), findsOneWidget);
      expect(find.byKey(const ValueKey('sales-month-12/2025')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('sales-month-01/2026')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '2025'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sales-month-12/2025')));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      expect(find.text('Dec 2025 — Jan 2026'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('sales-report-primary-action')),
      );
      await tester.pumpAndSettle();
      expect(remote.requests.last, ['12/2025', '01/2026']);
      expect(remote.downloadedSelections, [
        ['12/2025', '01/2026'],
      ]);
      expect(urls, hasLength(1));
      await tester.tap(find.byTooltip('Dismiss download notice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All months'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('sales-report-primary-action')),
      );
      await tester.pumpAndSettle();
      expect(remote.requests.last, ['01/2025', '12/2025']);
      expect(remote.downloadedSelections.last, ['01/2025', '12/2025']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        preview(
          archive2025: true,
          currentMonth: '11/2026',
          lastDay: '2026-11-02',
          currentAvailable: true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '2025'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(SalesReportWorkspace),
        matchesGoldenFile('goldens/sales_report_2025_desktop.png'),
      );
      tester.view.physicalSize = const Size(390, 1000);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
