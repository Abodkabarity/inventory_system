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
import '../widgets/assortment_data_source.dart';
import '../widgets/import_process_dialog.dart';

class AssortmentPage extends StatefulWidget {
  const AssortmentPage({super.key});

  @override
  State<AssortmentPage> createState() => _AssortmentPageState();
}

class _AssortmentPageState extends State<AssortmentPage> {
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    context.read<InventoryBloc>().add(LoadAssortment());
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
          previous.filteredAssortment != current.filteredAssortment ||
          previous.assortmentSearch != current.assortmentSearch ||
          previous.isLoading != current.isLoading ||
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
                child: _buildTable(state),
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
          colors: [Color(0xFFE53935), Color(0xFFFF7043), Color(0xFFFFA056)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x33FFFFFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1AE53935),
            blurRadius: 18,
            offset: Offset(0, 7),
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
                  Icons.category_rounded,
                  color: Color(0xFFE53935),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Assortment',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Manage mandatory branch products, owners, reasons, and dates.',
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
                value: '${state.assortment.length}',
              ),
              const SizedBox(width: 8),
              _HeaderMetric(
                label: 'Results',
                value: '${state.filteredAssortment.length}',
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
                              SearchAssortment(value),
                            );
                          }
                        },
                      );
                    },
                    decoration: InputDecoration(
                      hintText:
                          'Search branch, item code, item name, owner, or reason',
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: Color(0xFFE53935),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                      ),
                      border: _searchBorder(Colors.white),
                      enabledBorder: _searchBorder(Colors.white),
                      focusedBorder: _searchBorder(AppColors.primaryColor),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: state.isImporting ? null : _showImportDialog,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                ),
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('Import file'),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: state.isExporting ? null : _showExportDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFFE53935),
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
                          color: Color(0xFFE53935),
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

  OutlineInputBorder _searchBorder(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: color, width: 1.3),
  );

  void _showImportDialog() {
    final bloc = context.read<InventoryBloc>();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => BlocProvider.value(
        value: bloc,
        child: const ImportProgressDialog(type: ImportType.assortment),
      ),
    );
  }

  Widget _buildTable(InventoryState state) {
    if (state.isLoading && !state.isImporting && state.assortment.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.primaryColor),
            SizedBox(height: 10),
            Text('Loading assortment...'),
          ],
        ),
      );
    }

    final source = AssortmentDataSource(
      data: state.filteredAssortment,
      onHistory: (entry) {
        context.read<InventoryBloc>().add(
          LoadAssortmentHistory(entry['item_code'], entry['branch_name']),
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
            headerColor: const Color(0xFFFFE7E1),
            gridLineColor: AppColors.border,
            rowHoverColor: const Color(0xFFFFF5F2),
            sortIconColor: const Color(0xFFE53935),
            filterIconColor: const Color(0xFFE53935),
            filterIconHoverColor: const Color(0xFFC62828),
            columnResizeIndicatorColor: const Color(0xFFE53935),
            filterPopupBackgroundColor: const Color(0xFFFFF8F6),
            filterPopupTextStyle: const TextStyle(
              color: AppColors.text,
              fontSize: 14,
            ),
            filterPopupIconColor: const Color(0xFFE53935),
            filterPopupCheckColor: Colors.white,
            filterPopupCheckboxFillColor: const WidgetStatePropertyAll(
              Color(0xFFE53935),
            ),
            filterPopupInputBorderColor: const Color(0xFFE53935),
            filterPopupTopDividerColor: AppColors.border,
            filterPopupBottomDividerColor: AppColors.border,
            okFilteringLabelColor: Colors.white,
            okFilteringLabelButtonColor: const Color(0xFFE53935),
            cancelFilteringLabelColor: const Color(0xFFE53935),
            cancelFilteringLabelButtonColor: Colors.transparent,
            searchAreaFocusedBorderColor: const Color(0xFFE53935),
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
              _col('branch', 'Branch', width: 190.w),
              _col('code', 'Item Code', width: 145.w),
              _col('name', 'Item Name', width: 400.w),
              _col('qty', 'Qty', width: 120.w, center: true),
              _col('by', 'Assortment By', width: 180.w, center: true),
              _col('reason', 'Reason', width: 280.w),
              _col('start', 'Start', width: 145.w, center: true),
              _col('end', 'End', width: 145.w, center: true),
              _col('action', '', width: 72.w, center: true),
            ],
          ),
        ),
      ),
    );
  }

  GridColumn _col(
    String name,
    String title, {
    bool center = false,
    double? width,
  }) => GridColumn(
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
          color: Color(0xFF8A1C1C),
        ),
      ),
    ),
  );

  void _showExportDialog() {
    final bloc = context.read<InventoryBloc>();
    showDialog(
      context: context,
      builder: (_) => BlocProvider.value(
        value: bloc,
        child: const _AssortmentExportDialog(),
      ),
    );
  }
}

class _HeaderMetric extends StatelessWidget {
  const _HeaderMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
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

class _AssortmentExportDialog extends StatelessWidget {
  const _AssortmentExportDialog();

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
                          color: const Color(0xFFFFECE8),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.file_download_outlined,
                          color: Color(0xFFE53935),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Export Assortment',
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
                    title: 'Current assortment',
                    subtitle:
                        'Current items with Assortment By, Reason, quantity, and dates.',
                    enabled: !exporting,
                    onTap: () => context.read<InventoryBloc>().add(
                      ExportAssortmentCurrent(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _ExportOption(
                    icon: Icons.history_rounded,
                    title: 'Current assortment and history',
                    subtitle:
                        'Includes changes history in the same Excel workbook.',
                    enabled: !exporting,
                    onTap: () => context.read<InventoryBloc>().add(
                      ExportAssortmentWithHistory(),
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
  Widget build(BuildContext context) => Material(
    color: AppColors.bg,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            const Icon(
              Icons.description_outlined,
              color: AppColors.primaryColor,
            ),
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
            Icon(icon, color: AppColors.primaryColor),
          ],
        ),
      ),
    ),
  );
}
