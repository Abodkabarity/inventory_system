import 'dart:io';
import 'dart:typed_data';

import 'package:daily_order/core/utils/print_additional_service.dart';
import 'package:daily_order/core/utils/store_branch_identity_registry.dart';
import 'package:daily_order/domain/entities/store_additional_request_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:printing/src/interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CapturingPrinter extends PrintingPlatform {
  Uint8List? bytes;
  bool accepted = true;
  bool fail = false;
  @override
  Future<bool> layoutPdf(
    Printer? printer,
    LayoutCallback onLayout,
    String name,
    PdfPageFormat format,
    bool dynamicLayout,
    bool usePrinterSettings,
    OutputType outputType,
    bool forceCustomPrintPaper,
    bool windowsModernDialog,
  ) async {
    if (fail) throw StateError('Print unavailable');
    bytes = await onLayout(format);
    return accepted;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final originalPlatform = PrintingPlatform.instance;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'test-key',
      debug: false,
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  tearDown(() {
    PrintingPlatform.instance = originalPlatform;
    StoreBranchIdentityRegistry.groups.value = const {};
  });

  test(
    'real PDF contains the selected pending line and preserves print result',
    () async {
      final printer = CapturingPrinter();
      PrintingPlatform.instance = printer;
      StoreBranchIdentityRegistry.groups.value = {
        'MODERN': '71',
        'CITY': 'APG',
      };
      final items = [
        {
          'id': 'done',
          'branch_name': 'MODERN',
          'item_name': 'COMPLETED MUST NOT PRINT',
          'status': 'done',
          'inventory_qty': 1,
        },
        {
          'id': 'pending',
          'branch_name': 'MODERN',
          'item_code': '16-02-07749',
          'item_name': 'LA ROCHE POSAY RETINOL B3 SERUM 30 ML',
          'status': 'sent_to_store',
          'inventory_qty': 1,
          'supplier': 'Sample supplier',
        },
      ];
      final selected = StoreAdditionalRequestStatus(items).printable;
      expect(
        await PrintAdditionalService.printBatch({'MODERN': selected}),
        true,
      );
      expect(printer.bytes, isNotNull);
      expect(printer.bytes!.length, greaterThan(1000));
      Directory('tmp/pdfs').createSync(recursive: true);
      File(
        'tmp/pdfs/store_additional_pending.pdf',
      ).writeAsBytesSync(printer.bytes!);
      printer.accepted = false;
      expect(
        await PrintAdditionalService.printBatch({'MODERN': selected}),
        false,
      );
      printer.fail = true;
      await expectLater(
        PrintAdditionalService.printBatch({'MODERN': selected}),
        throwsStateError,
      );
    },
  );
}
