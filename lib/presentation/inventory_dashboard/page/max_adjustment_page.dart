import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import '../../../core/theme/app_colors.dart';
import '../bloc/inventory_bloc.dart';
import '../bloc/inventory_event.dart';
import '../bloc/inventory_state.dart';
import '../widgets/import_process_dialog.dart';
import '../widgets/max_adj_data_source.dart';
import '../widgets/max_adj_history_dialog.dart';

class MaxAdjustmentPage extends StatefulWidget {
  const MaxAdjustmentPage({super.key});

  @override
  State<MaxAdjustmentPage> createState() => _MaxAdjustmentPageState();
}

class _MaxAdjustmentPageState extends State<MaxAdjustmentPage> {
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    context.read<InventoryBloc>().add(LoadMaxAdjustment());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<InventoryBloc, InventoryState>(
      buildWhen: (previous, current) =>
          previous.filteredMaxAdjustment != current.filteredMaxAdjustment ||
          previous.maxAdjSearch != current.maxAdjSearch ||
          previous.maxAdjPage != current.maxAdjPage ||
          previous.maxAdjPageSize != current.maxAdjPageSize ||
          previous.maxAdjTotalRows != current.maxAdjTotalRows ||
          previous.maxAdjHasMore != current.maxAdjHasMore ||
          previous.isMaxAdjLoading != current.isMaxAdjLoading ||
          previous.isImporting != current.isImporting ||
          previous.isExporting != current.isExporting ||
          previous.exportMessage != current.exportMessage,
      builder: (context, state) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: _buildHeader(state),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  children: [
                    Expanded(child: _buildTable(state)),
                    const SizedBox(height: 10),
                    _buildPager(state),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(InventoryState state) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF97316), Color(0xFFEA580C), Color(0xFF9A3412)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x33FFFFFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .92),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.tune_rounded,
                  color: AppColors.primaryColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Max Adjustment',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Manage branch limits, adjustment reasons, and change history.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .9),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              _HeaderMetric(
                label: 'Records',
                value: '${state.maxAdjTotalRows}',
              ),
              const SizedBox(width: 8),
              _HeaderMetric(
                label: 'This page',
                value: '${state.filteredMaxAdjustment.length}',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: TextField(
                    onChanged: (value) {
                      _searchDebounce?.cancel();
                      _searchDebounce = Timer(
                        const Duration(milliseconds: 350),
                        () {
                          if (mounted) {
                            context.read<InventoryBloc>().add(
                              SearchMaxAdjustment(value),
                            );
                          }
                        },
                      );
                    },
                    decoration: InputDecoration(
                      hintText:
                          'Search branch, item code, item name, type, or reason',
                      filled: true,
                      fillColor: AppColors.bg,
                      prefixIcon: const Icon(Icons.search_rounded),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                      ),
                      border: _searchBorder(AppColors.border),
                      enabledBorder: _searchBorder(AppColors.border),
                      focusedBorder: _searchBorder(AppColors.primaryColor),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: state.isImporting ? null : _showImportDialog,
                style: OutlinedButton.styleFrom(
                  backgroundColor: AppColors.secondaryColor,
                  foregroundColor: AppColors.secondaryColor,
                  side: const BorderSide(color: Colors.white),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                ),
                icon: const Icon(
                  Icons.upload_file_rounded,
                  color: Colors.white,
                ),
                label: const Text(
                  'Import file',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: state.isExporting ? null : _showExportDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                ),
                icon: state.isExporting
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.download_rounded),
                label: Text(state.isExporting ? 'Preparing export' : 'Export'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  OutlineInputBorder _searchBorder(Color color) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color, width: 1.3),
    );
  }

  void _showImportDialog() {
    final bloc = context.read<InventoryBloc>();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => BlocProvider.value(
        value: bloc,
        child: const ImportProgressDialog(type: ImportType.maxAdj),
      ),
    );
  }

  Widget _buildTable(InventoryState state) {
    final data = state.filteredMaxAdjustment;
    if (state.isMaxAdjLoading && data.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.primaryColor),
            SizedBox(height: 10),
            Text('Loading max adjustments...'),
          ],
        ),
      );
    }

    final source = MaxAdjDataSource(
      data: data,
      pageOffset: state.maxAdjPage * state.maxAdjPageSize,
      onHistory: (entry) {
        context.read<InventoryBloc>().add(
          LoadMaxAdjustmentHistory(entry['item_code'], entry['branch_name']),
        );
        showDialog(
          context: context,
          builder: (_) => BlocProvider.value(
            value: context.read<InventoryBloc>(),
            child: const MaxAdjHistoryDialog(),
          ),
        );
      },
    );

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SfDataGridTheme(
          data: SfDataGridThemeData(
            headerColor: const Color(0xFFFFEBDD),
            gridLineColor: AppColors.border,
            rowHoverColor: const Color(0xFFFFF6F0),
            filterPopupBackgroundColor: const Color(0xFFFFF8F3),
            filterPopupTextStyle: const TextStyle(
              color: AppColors.text,
              fontSize: 14,
            ),
            filterPopupIconColor: const Color(0xFFF97316),
            filterPopupCheckColor: Colors.white,
            filterPopupCheckboxFillColor: WidgetStatePropertyAll(
              Color(0xFFF97316),
            ),
            filterPopupInputBorderColor: const Color(0xFFF97316),
            filterPopupTopDividerColor: AppColors.border,
            filterPopupBottomDividerColor: AppColors.border,
            okFilteringLabelColor: Colors.white,
            okFilteringLabelButtonColor: const Color(0xFFF97316),
            cancelFilteringLabelColor: AppColors.secondaryColor,
            cancelFilteringLabelButtonColor: Colors.transparent,
            searchAreaFocusedBorderColor: const Color(0xFFF97316),
          ),
          child: SfDataGrid(
            source: source,
            allowFiltering: true,
            allowSorting: true,
            allowColumnsResizing: true,
            showColumnHeaderIconOnHover: false,
            showSortNumbers: true,
            columnWidthMode: ColumnWidthMode.none,
            selectionMode: SelectionMode.single,
            headerRowHeight: 52,
            rowHeight: 52,
            gridLinesVisibility: GridLinesVisibility.both,
            headerGridLinesVisibility: GridLinesVisibility.both,
            columns: [
              _col('index', '#', width: 80.w, center: true),
              _col('branch', 'Branch', width: 180.w),
              _col('code', 'Item Code', width: 140.w),
              _col('name', 'Item Name', width: 400.w),
              _col('demand', 'Demand', width: 138.w, center: true),
              _col('max', 'Max Adj', width: 138.w, center: true),
              _col('type', 'Type', width: 120.w, center: true),
              _col('qty', 'Qty', width: 120.w, center: true),
              _col('reason', 'Reason', width: 280.w),
              _col('date', 'Date', width: 142.w, center: true),
              _col('added_by', 'Added By', width: 150.w, center: true),
              _col('action', '', width: 72.w, center: true),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPager(InventoryState state) {
    final totalPages = state.maxAdjTotalRows == 0
        ? 1
        : (state.maxAdjTotalRows / state.maxAdjPageSize).ceil();
    final currentPage = state.maxAdjPage + 1;
    final bloc = context.read<InventoryBloc>();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Text(
            'Page $currentPage of $totalPages',
            style: const TextStyle(
              color: AppColors.text,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 16),
          Text(
            '${state.maxAdjTotalRows} total / ${state.maxAdjPageSize} per page',
            style: const TextStyle(color: AppColors.subText),
          ),
          const Spacer(),
          if (state.isMaxAdjLoading)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: state.maxAdjPage == 0 || state.isMaxAdjLoading
                ? null
                : () => bloc.add(
                    LoadMaxAdjustment(
                      page: state.maxAdjPage - 1,
                      query: state.maxAdjSearch,
                    ),
                  ),
            icon: const Icon(Icons.chevron_left),
            label: const Text('Previous'),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: !state.maxAdjHasMore || state.isMaxAdjLoading
                ? null
                : () => bloc.add(
                    LoadMaxAdjustment(
                      page: state.maxAdjPage + 1,
                      query: state.maxAdjSearch,
                    ),
                  ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.chevron_right),
            label: const Text('Next'),
          ),
        ],
      ),
    );
  }

  GridColumn _col(
    String name,
    String title, {
    bool center = false,
    double? width,
  }) {
    return GridColumn(
      columnName: name,
      width: width ?? double.nan,
      label: Container(
        alignment: center ? Alignment.center : Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
            color: Color(0xFF9A3412),
          ),
        ),
      ),
    );
  }

  void _showExportDialog() {
    final bloc = context.read<InventoryBloc>();
    showDialog(
      context: context,
      builder: (_) =>
          BlocProvider.value(value: bloc, child: const _MaxAdjExportDialog()),
    );
  }
}

class _HeaderMetric extends StatelessWidget {
  const _HeaderMetric({required this.label, required this.value});

  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 82),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .19),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: .22)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .86),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _MaxAdjExportDialog extends StatelessWidget {
  const _MaxAdjExportDialog();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<InventoryBloc, InventoryState>(
      buildWhen: (previous, current) =>
          previous.isExporting != current.isExporting ||
          previous.exportMessage != current.exportMessage,
      builder: (context, state) {
        final exporting = state.isExporting;
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 510),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.blueSoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.file_download_outlined,
                          color: AppColors.primaryColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Export Max Adjustment',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Choose the Excel report you need.',
                              style: TextStyle(color: AppColors.subText),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: exporting
                            ? null
                            : () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _ExportOption(
                    icon: Icons.table_chart_outlined,
                    title: 'Current adjustments',
                    subtitle:
                        'Active records with Reason, Type, Demand, Max Adjustment, and dates.',
                    enabled: !exporting,
                    onTap: () => context.read<InventoryBloc>().add(
                      ExportMaxAdjCurrent(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _ExportOption(
                    icon: Icons.history_rounded,
                    title: 'Current adjustments and history',
                    subtitle:
                        'Includes historical changes in the same Excel workbook.',
                    enabled: !exporting,
                    onTap: () => context.read<InventoryBloc>().add(
                      ExportMaxAdjWithHistory(),
                    ),
                  ),
                  if (exporting) ...[
                    const SizedBox(height: 20),
                    const LinearProgressIndicator(
                      color: AppColors.primaryColor,
                    ),
                    const SizedBox(height: 9),
                    Text(
                      state.exportMessage ?? 'Preparing your Excel file...',
                      style: const TextStyle(
                        color: AppColors.subText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ExportOption extends StatelessWidget {
  const _ExportOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Icon(icon, color: AppColors.primaryColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.subText,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.subText),
            ],
          ),
        ),
      ),
    );
  }
}
