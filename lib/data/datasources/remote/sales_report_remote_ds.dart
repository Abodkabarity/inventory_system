import 'package:supabase_flutter/supabase_flutter.dart';

class SalesReportRemoteDs {
  final SupabaseClient client;
  const SalesReportRemoteDs(this.client);

  Future<Map<String, dynamic>> fetch({
    List<String> months = const [],
    bool request = false,
  }) async {
    final data = await client.rpc(
      'get_sales_report',
      params: {'p_months': months, 'p_request': request},
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Uri> downloadUrl(List<String> months) async {
    // Revalidate the revision immediately before issuing a short-lived link.
    final state = await fetch(months: months);
    final job = state['job'] as Map?;
    if (state['awaiting_update'] == true ||
        job == null ||
        job['status'] != 'ready' ||
        job['is_current'] != true ||
        job['storage_path'] == null) {
      throw StateError('The source changed. Prepare the latest report first.');
    }
    final name =
        'Sales Report ${months.map((m) => m.replaceAll('/', '-')).join('_')}.csv';
    final url = await client.storage
        .from('sales-report-exports')
        .createSignedUrl(job['storage_path'] as String, 60);
    final uri = Uri.parse(url);
    return uri.replace(
      queryParameters: {...uri.queryParameters, 'download': name},
    );
  }

  Future<Map<String, dynamic>> fetchDaily({bool request = false}) async {
    final data = await client.rpc(
      'get_sales_45_report',
      params: {'p_request': request},
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Uri> downloadDailyUrl() async {
    final state = await fetchDaily();
    final job = state['job'] as Map?;
    if (state['awaiting_update'] == true ||
        job == null ||
        job['status'] != 'ready' ||
        job['is_current'] != true ||
        job['storage_path'] == null) {
      throw StateError(
        'The daily sales update is not ready. Refresh the report status.',
      );
    }
    final url = await client.storage
        .from('sales-report-exports')
        .createSignedUrl(job['storage_path'] as String, 60);
    final uri = Uri.parse(url);
    return uri.replace(
      queryParameters: {
        ...uri.queryParameters,
        'download':
            'Sales 45 Days ${state['period_from']}_to_${state['period_through']}.csv',
      },
    );
  }
}
