import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_colors.dart';
import '../bloc/inventory_bloc.dart';
import '../bloc/inventory_event.dart';
import '../bloc/inventory_state.dart';
import '../widgets/additional_analysis/additional_analysis_header.dart';
import '../widgets/additional_analysis/additional_insights_section.dart';
import '../widgets/additional_analysis/top_branches_card.dart';
import '../widgets/additional_analysis/top_products_card.dart';

class AdditionalOrderAnalysisPage extends StatefulWidget {
  const AdditionalOrderAnalysisPage({super.key});

  @override
  State<AdditionalOrderAnalysisPage> createState() =>
      _AdditionalOrderAnalysisPageState();
}

class _AdditionalOrderAnalysisPageState
    extends State<AdditionalOrderAnalysisPage> {
  late DateTime _from;
  late DateTime _to;
  bool _isAnalysisLoading = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    // Default: current month
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    _load();
  }

  void _load() {
    setState(() => _isAnalysisLoading = true);
    context.read<InventoryBloc>().add(
      LoadAdditionalOrderAnalysis(from: _from, to: _to),
    );
  }

  Future<void> _pickDateRange() async {
    final lastAllowedDate = DateTime.now().add(const Duration(days: 1));
    final safeEnd = _to.isAfter(lastAllowedDate) ? lastAllowedDate : _to;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime(2035, 12, 31),
      initialDateRange: DateTimeRange(start: _from, end: safeEnd),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xff06B6D4),
            onPrimary: Colors.white,
            surface: Color(0xff1F2937),
          ),
        ),
        child: child!,
      ),
    );

    if (picked != null) {
      setState(() {
        _from = picked.start;
        _to = DateTime(
          picked.end.year,
          picked.end.month,
          picked.end.day,
          23,
          59,
          59,
        );
      });
      _load();
    }
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return BlocListener<InventoryBloc, InventoryState>(
      listenWhen: (prev, curr) =>
          prev.additionalAnalysis != curr.additionalAnalysis,
      listener: (_, __) => setState(() => _isAnalysisLoading = false),
      child: Container(
        color: Colors.white,
        child: Column(
          children: [
            // ── TOP BAR ─────────────────────────────────────────────
            _buildTopBar(),

            // ── CONTENT ─────────────────────────────────────────────
            Expanded(
              child: BlocBuilder<InventoryBloc, InventoryState>(
                builder: (context, state) {
                  if (_isAnalysisLoading) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xff06B6D4),
                      ),
                    );
                  }

                  final data = state.additionalAnalysis;

                  if (data.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.analytics_outlined,
                            color: Colors.white24,
                            size: 64,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No data for the selected period',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextButton.icon(
                            onPressed: _load,
                            icon: const Icon(
                              Icons.refresh,
                              color: Color(0xff06B6D4),
                            ),
                            label: const Text(
                              'Reload',
                              style: TextStyle(color: Color(0xff06B6D4)),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final branches = List<Map<String, dynamic>>.from(
                    data['top_branches'] ?? [],
                  );
                  final products = List<Map<String, dynamic>>.from(
                    data['top_products'] ?? [],
                  );

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // KPI cards
                        AdditionalKpiCards(data: data),

                        const SizedBox(height: 24),

                        // Top Branches + Top Products
                        SizedBox(
                          height: 480,
                          child: Row(
                            children: [
                              Expanded(
                                child: TopBranchesCard(branches: branches),
                              ),
                              const SizedBox(width: 24),
                              Expanded(
                                child: TopProductsCard(products: products),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Additional insights
                        AdditionalInsightsSection(data: data),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: AppColors.secondaryColor,
        border: Border(bottom: BorderSide(color: Color(0xff1F2937))),
      ),
      child: Row(
        children: [
          const Icon(Icons.analytics, color: Color(0xff06B6D4)),
          const SizedBox(width: 12),
          const Text(
            'Additional Order Analysis',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          // Date badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xff1F2937),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xff374151)),
            ),
            child: Text(
              '${_formatDate(_from)}  →  ${_formatDate(_to)}',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _pickDateRange,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xff06B6D4),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.date_range, size: 18),
            label: const Text('Date Range'),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _load,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, color: Colors.white54),
          ),
        ],
      ),
    );
  }
}
