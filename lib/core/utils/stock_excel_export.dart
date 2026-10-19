import 'stock_excel_report.dart';
import 'stock_excel_export_stub.dart'
    if (dart.library.html) 'stock_excel_export_web.dart'
    as platform;

Future<void> saveStockExcel(List<Map<String, dynamic>> rows, String fileName) =>
    platform.saveExcel(
      StockExcelReport(rows, fileName),
      StockExcelReport.fileName(fileName),
    );
