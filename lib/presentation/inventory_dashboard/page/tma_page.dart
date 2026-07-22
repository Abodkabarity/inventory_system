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
import '../widgets/tma_data_source.dart';

class TmaPage extends StatefulWidget {
  const TmaPage({super.key});

  @override
  State<TmaPage> createState() => _TmaPageState();
}

class _TmaPageState extends State<TmaPage> {
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    context.read<InventoryBloc>().add(LoadTma());
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
          previous.filteredTma != current.filteredTma ||
          previous.tmaSearch != current.tmaSearch ||
          previous.isLoading != current.isLoading ||
          previous.isImporting != current.isImporting ||
          previous.isExporting != current.isExporting ||
          previous.exportMessage != current.exportMessage,
      builder: (context, state) {
        return Stack(
          children: [
            Column(
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
            ),
            if (state.isExporting) _buildExportOverlay(state),
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
          colors: [
            AppColors.primaryColor,
            Color(0xFF79C8EA),
            Color(0xFFB6E5F8),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x66FFFFFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
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
                  Icons.medical_information_outlined,
                  color: AppColors.primaryColor,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TMA',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Manage temporary product activity, quantities, and effective dates.',
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ],
                ),
              ),
              _TmaMetric(label: 'Records', value: '${state.tma.length}'),
              const SizedBox(width: 8),
              _TmaMetric(
                label: 'Results',
                value: '${state.filteredTma.length}',
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
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText:
                          'Search branch, item code, item name, or duration',
                      filled: true,
                      fillColor: AppColors.card,
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: AppColors.primaryColor,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                      ),
                      border: _searchBorder(Colors.white),
                      enabledBorder: _searchBorder(Colors.white),
                      focusedBorder: _searchBorder(AppColors.secondaryColor),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: state.isImporting ? null : _showImportDialog,
                style: OutlinedButton.styleFrom(
                  backgroundColor: AppColors.secondaryColor,
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
                  backgroundColor: AppColors.secondaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                ),
                icon: const Icon(Icons.download_rounded),
                label: const Text('Export'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) context.read<InventoryBloc>().add(SearchTma(value));
    });
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
        child: const ImportProgressDialog(type: ImportType.tma),
      ),
    );
  }

  Widget _buildTable(InventoryState state) {
    if (state.isLoading && state.filteredTma.isEmpty && !state.isImporting) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.primaryColor),
            SizedBox(height: 10),
            Text('Loading TMA records...'),
          ],
        ),
      );
    }

    final source = TmaDataSource(
      data: state.filteredTma,
      onHistory: (entry) => context.read<InventoryBloc>().add(
        LoadTmaHistory(entry['item_code'], entry['branch_name']),
      ),
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
            headerColor: AppColors.headerBg,
            gridLineColor: AppColors.border,
            rowHoverColor: AppColors.rowHover,
            filterPopupBackgroundColor: AppColors.blueSoft,
            filterPopupTextStyle: const TextStyle(
              color: AppColors.text,
              fontSize: 14,
            ),
            filterPopupIconColor: AppColors.primaryColor,
            filterPopupCheckColor: Colors.white,
            filterPopupCheckboxFillColor: const WidgetStatePropertyAll(
              AppColors.primaryColor,
            ),
            filterPopupInputBorderColor: AppColors.primaryColor,
            filterPopupTopDividerColor: AppColors.border,
            filterPopupBottomDividerColor: AppColors.border,
            okFilteringLabelColor: Colors.white,
            okFilteringLabelButtonColor: AppColors.primaryColor,
            cancelFilteringLabelColor: AppColors.secondaryColor,
            cancelFilteringLabelButtonColor: Colors.transparent,
            searchAreaFocusedBorderColor: AppColors.primaryColor,
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
              _column('index', '#', width: 80.w, center: true),
              _column('branch', 'Branch', width: 190.w),
              _column('code', 'Item Code', width: 145.w),
              _column('name', 'Item Name', width: 500.w),
              _column('qty', 'Qty / Duration', width: 200.w, center: true),
              _column('start', 'Start', width: 145.w, center: true),
              _column('end', 'End', width: 145.w, center: true),
              _column('action', '', width: 78.w, center: true),
            ],
          ),
        ),
      ),
    );
  }

  GridColumn _column(
    String name,
    String title, {
    required double width,
    bool center = false,
  }) {
    return GridColumn(
      columnName: name,
      width: width,
      label: Container(
        alignment: center ? Alignment.center : Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
            color: AppColors.headerText,
          ),
        ),
      ),
    );
  }

  Widget _buildExportOverlay(InventoryState state) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: .32),
        child: Center(
          child: Container(
            width: 300,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primaryColor),
              boxShadow: const [
                BoxShadow(color: Color(0x220F172A), blurRadius: 24),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: AppColors.primaryColor),
                const SizedBox(height: 14),
                const Text(
                  'Preparing TMA export',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 5),
                Text(
                  state.exportMessage ?? 'Creating your Excel workbook...',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.subText),
                ),
              ],
            ),
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
          BlocProvider.value(value: bloc, child: const _TmaExportDialog()),
    );
  }
}

class _TmaMetric extends StatelessWidget {
  const _TmaMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 82),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black.withValues(alpha: .24)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: Colors.black, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _TmaExportDialog extends StatelessWidget {
  const _TmaExportDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
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
                          'Export TMA',
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
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _TmaExportOption(
                icon: Icons.table_chart_outlined,
                title: 'Current TMA records',
                subtitle: 'Exports the active TMA records shown in the system.',
                onTap: () {
                  Navigator.pop(context);
                  context.read<InventoryBloc>().add(ExportTmaCurrent());
                },
              ),
              const SizedBox(height: 10),
              _TmaExportOption(
                icon: Icons.history_rounded,
                title: 'Current records and history',
                subtitle:
                    'Exports active TMA records together with their history.',
                onTap: () {
                  Navigator.pop(context);
                  context.read<InventoryBloc>().add(ExportTmaWithHistory());
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TmaExportOption extends StatelessWidget {
  const _TmaExportOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
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
