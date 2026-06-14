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
import '../widgets/formulary_data_source.dart';
import '../widgets/import_process_dialog.dart';

class FormularyPage extends StatefulWidget {
  const FormularyPage({super.key});

  @override
  State<FormularyPage> createState() => _FormularyPageState();
}

class _FormularyPageState extends State<FormularyPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  FormularyDataSource? _source;

  @override
  void initState() {
    super.initState();
    context.read<InventoryBloc>().add(LoadFormulary());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();

    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      context.read<InventoryBloc>().add(SearchFormulary(value));
    });
  }

  void _loadPage(int page) {
    final state = context.read<InventoryBloc>().state;

    context.read<InventoryBloc>().add(
      LoadFormulary(page: page, query: state.formularySearch),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<InventoryBloc, InventoryState>(
      builder: (context, state) {
        return Stack(
          children: [
            Container(
              color: const Color(0xffF4F7FB),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Header(
                    total: state.filteredFormulary.length,
                    page: state.formularyPage,
                    hasMore: state.formularyHasMore,
                    isLoading: state.isFormularyLoading,
                    onRefresh: () => context.read<InventoryBloc>().add(
                      LoadFormulary(
                        page: state.formularyPage,
                        query: state.formularySearch,
                      ),
                    ),
                  ),
                  _Toolbar(
                    controller: _searchCtrl,
                    isExporting: state.isExporting,
                    onSearch: _onSearchChanged,
                    onImport: () {
                      showDialog(
                        context: context,
                        builder: (_) => BlocProvider.value(
                          value: context.read<InventoryBloc>(),
                          child: const ImportProgressDialog(
                            type: ImportType.formulary,
                          ),
                        ),
                      );
                    },
                    onExport: _showExportDialog,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                      child: _buildTable(state),
                    ),
                  ),
                  _PagerBar(
                    page: state.formularyPage,
                    hasMore: state.formularyHasMore,
                    isLoading: state.isFormularyLoading,
                    totalRows: state.formularyTotalRows,
                    pageSize: state.formularyPageSize,

                    onPrev: state.formularyPage == 0
                        ? null
                        : () => _loadPage(state.formularyPage - 1),
                    onNext: !state.formularyHasMore
                        ? null
                        : () => _loadPage(state.formularyPage + 1),
                  ),
                ],
              ),
            ),
            if (state.isExporting)
              Container(
                color: Colors.black.withOpacity(0.30),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: AppColors.primaryColor),
                      SizedBox(height: 12),
                      Text(
                        'Exporting...',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildTable(InventoryState state) {
    if (state.isFormularyLoading && state.filteredFormulary.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryColor),
      );
    }

    final data = state.filteredFormulary;

    if (data.isEmpty) {
      return const _EmptyState();
    }

    _source = FormularyDataSource(
      data: data,
      pageOffset: state.formularyPage * state.formularyPageSize,
      onHistory: (e) {
        context.read<InventoryBloc>().add(
          LoadFormularyHistory(e['item_code'], e['branch_name']),
        );
      },
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xffE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SfDataGridTheme(
          data: SfDataGridThemeData(
            headerColor: const Color(0xffEAF6FC),
            gridLineColor: const Color(0xffE2E8F0),
          ),
          child: SfDataGrid(
            source: _source!,
            columnWidthMode: ColumnWidthMode.fill,
            allowSorting: true,
            allowColumnsResizing: true,
            gridLinesVisibility: GridLinesVisibility.horizontal,
            headerGridLinesVisibility: GridLinesVisibility.none,
            rowHeight: 54,
            headerRowHeight: 52,
            columns: [
              _col('index', '#', width: 70.w),
              _col('branch', 'Branch', width: 200.w),
              _col('code', 'Item Code', width: 150.w),
              _col('name', 'Item Name', width: 430.w, center: false),
              _col('status', 'Formulary', width: 140.w),
              _col('date', 'Revised Date', width: 150.w),
              _col('reason', 'Reason', width: 260.w, center: false),
              _col('action', '', width: 80.w),
            ],
          ),
        ),
      ),
    );
  }

  GridColumn _col(
    String name,
    String title, {
    bool center = true,
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
            fontWeight: FontWeight.w900,
            color: Color(0xff122d40),
          ),
        ),
      ),
    );
  }

  void _showExportDialog() {
    final bloc = context.read<InventoryBloc>();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Export Formulary'),
        backgroundColor: Colors.white,
        content: const Text('Choose export type'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              bloc.add(ExportFormularyCurrent());
            },
            child: const Text(
              'Export current',
              style: TextStyle(color: AppColors.primaryColor),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              bloc.add(ExportFormularyWithHistory());
            },
            child: const Text(
              'Export with history',
              style: TextStyle(color: AppColors.secondaryColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final int total;
  final int page;
  final bool hasMore;
  final bool isLoading;
  final VoidCallback onRefresh;

  const _Header({
    required this.total,
    required this.page,
    required this.hasMore,
    required this.isLoading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xffE2E8F0))),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primaryColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.list_alt_rounded,
              color: AppColors.primaryColor,
            ),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Formulary',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: AppColors.secondaryColor,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Fast server-side paging and search',
                style: TextStyle(color: Color(0xff64748B), fontSize: 12),
              ),
            ],
          ),
          const Spacer(),
          _InfoPill(label: 'Page', value: '${page + 1}'),
          const SizedBox(width: 10),
          _InfoPill(label: 'Loaded', value: '$total'),
          const SizedBox(width: 10),
          _InfoPill(label: 'More', value: hasMore ? 'Yes' : 'No'),
          const SizedBox(width: 8),
          IconButton(
            onPressed: isLoading ? null : onRefresh,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded, color: Color(0xff64748B)),
          ),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  final TextEditingController controller;
  final bool isExporting;
  final ValueChanged<String> onSearch;
  final VoidCallback onImport;
  final VoidCallback onExport;

  const _Toolbar({
    required this.controller,
    required this.isExporting,
    required this.onSearch,
    required this.onImport,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 46,
              child: TextField(
                controller: controller,
                onChanged: onSearch,
                decoration: InputDecoration(
                  hintText: 'Search item code, item name, or branch...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: const Color(0xffF1F5F9),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: onImport,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
              padding: EdgeInsets.symmetric(horizontal: 28.w, vertical: 13.h),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.upload_rounded, color: Colors.white),
            label: const Text('Import', style: TextStyle(color: Colors.white)),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: isExporting ? null : onExport,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.secondaryColor,
              padding: EdgeInsets.symmetric(horizontal: 28.w, vertical: 13.h),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.download_rounded, color: Colors.white),
            label: const Text('Export', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class _PagerBar extends StatelessWidget {
  final int page;
  final int totalRows;
  final int pageSize;
  final bool hasMore;
  final bool isLoading;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  const _PagerBar({
    required this.page,
    required this.totalRows,
    required this.pageSize,
    required this.hasMore,
    required this.isLoading,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final totalPages = totalRows == 0 ? 1 : (totalRows / pageSize).ceil();
    final from = totalRows == 0 ? 0 : (page * pageSize) + 1;
    final to = ((page + 1) * pageSize).clamp(0, totalRows);

    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xffE2E8F0))),
      ),
      child: Row(
        children: [
          Text(
            'Rows $from-$to of $totalRows',
            style: const TextStyle(
              color: Color(0xff64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 18),
          Text(
            'Page ${page + 1} of $totalPages',
            style: const TextStyle(
              color: AppColors.secondaryColor,
              fontWeight: FontWeight.w900,
            ),
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: isLoading ? null : onPrev,
            icon: const Icon(Icons.chevron_left_rounded),
            label: const Text('Previous'),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: isLoading ? null : onNext,
            style: ElevatedButton.styleFrom(
              backgroundColor: hasMore
                  ? AppColors.primaryColor
                  : const Color(0xffCBD5E1),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.chevron_right_rounded),
            label: const Text('Next'),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String label;
  final String value;

  const _InfoPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xffF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xffE2E8F0)),
      ),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: const TextStyle(color: Color(0xff64748B), fontSize: 12),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.secondaryColor,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'No formulary rows found',
        style: TextStyle(color: Color(0xff64748B), fontWeight: FontWeight.bold),
      ),
    );
  }
}
