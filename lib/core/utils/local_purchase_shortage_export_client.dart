import 'dart:convert';
import 'dart:html' as html;

class LocalPurchaseShortageExportClient {
  static const String _baseUrl = 'http://127.0.0.1:8765';

  static Future<String> export({required String runDate}) async {
    final url = '$_baseUrl/export?run_date=${Uri.encodeComponent(runDate)}';

    try {
      final response = await html.HttpRequest.request(
        url,
        method: 'GET',
        responseType: 'text',
      );

      final status = response.status ?? 0;
      final body = response.responseText ?? '';

      if (status < 200 || status >= 300) {
        throw Exception('HTTP $status: $body');
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Invalid helper response');
      }

      if (decoded['ok'] != true) {
        throw Exception(decoded['error']?.toString() ?? 'Export failed');
      }

      return decoded['path']?.toString() ?? '';
    } catch (e) {
      throw Exception(
        'Local Python export helper is not running or could not finish. '
        'Start scripts\\start_purchase_shortage_export_server.bat and try again. '
        'Details: $e',
      );
    }
  }
}
