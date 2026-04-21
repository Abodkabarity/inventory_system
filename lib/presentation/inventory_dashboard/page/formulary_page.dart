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
  FormularyDataSource? _source;

  @override
  void initState() {
    super.initState();
    context.read<InventoryBloc>().add(LoadFormulary());
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<InventoryBloc, InventoryState>(
      builder: (context, state) {
        return Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),

                /// 🔥 TITLE
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    "Formulary",
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                ),

                const SizedBox(height: 20),

                /// 🔥 SEARCH + BUTTONS
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          onChanged: (v) {
                            context.read<InventoryBloc>().add(
                              SearchFormulary(v),
                            );
                          },
                          decoration: InputDecoration(
                            hintText: "Search item...",
                            filled: true,
                            fillColor: AppColors.backgroundWidget,
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: AppColors.primaryColor,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: AppColors.primaryColor,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: AppColors.primaryColor,
                              ),
                            ),
                          ),
                        ),
                      ),

                      const Spacer(),

                      /// 🔥 IMPORT
                      ElevatedButton.icon(
                        onPressed: () {
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
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryColor,
                          padding: EdgeInsets.symmetric(
                            horizontal: 35.w,
                            vertical: 12.h,
                          ),
                        ),
                        icon: const Icon(Icons.upload, color: Colors.white),
                        label: const Text(
                          "Import",
                          style: TextStyle(color: Colors.white),
                        ),
                      ),

                      const SizedBox(width: 10),

                      /// 🔥 EXPORT
                      ElevatedButton.icon(
                        onPressed: state.isExporting ? null : _showExportDialog,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryColor,
                          padding: EdgeInsets.symmetric(
                            horizontal: 35.w,
                            vertical: 12.h,
                          ),
                        ),
                        icon: const Icon(Icons.download, color: Colors.white),
                        label: const Text(
                          "Export",
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),

                /// 🔥 TABLE
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _buildTable(state),
                  ),
                ),
              ],
            ),

            /// 🔥 EXPORT LOADING
            if (state.isExporting)
              Container(
                color: Colors.black.withOpacity(0.3),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: AppColors.primaryColor),
                      SizedBox(height: 12),
                      Text(
                        "Exporting...",
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

  /// ===============================
  /// 🔥 TABLE + PAGINATION
  /// ===============================
  Widget _buildTable(InventoryState state) {
    if (state.isLoading && !state.isImporting) {
      return const Center(child: CircularProgressIndicator());
    }

    final data = state.filteredFormulary;

    if (data.isEmpty) {
      return const Center(child: Text("No data available"));
    }

    if (_source == null || _source!.totalRows != data.length) {
      _source = FormularyDataSource(
        data: data,
        onHistory: (e) {
          context.read<InventoryBloc>().add(
            LoadFormularyHistory(e['item_code'], e['branch_name']),
          );
        },
      );
    }

    return Column(
      children: [
        /// 🔥 TABLE
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: SfDataGridTheme(
              data: SfDataGridThemeData(
                headerColor: AppColors.backgroundWidget,
                gridLineColor: Colors.grey.shade300,
              ),
              child: SfDataGrid(
                source: _source!,
                columnWidthMode: ColumnWidthMode.fill,
                allowSorting: true,
                allowFiltering: true,
                allowColumnsResizing: true,

                /// 🔥 BORDER
                gridLinesVisibility: GridLinesVisibility.both,
                headerGridLinesVisibility: GridLinesVisibility.both,

                columns: [
                  _col('index', '#', width: 70.w),
                  _col('branch', 'Branch', width: 200.w),
                  _col('code', 'Item Code', width: 140.w),
                  _col('name', 'Item Name', width: 430.w),
                  _col('status', 'Formulary', width: 140),
                  _col('date', 'Revised Date', width: 150.w),
                  _col('reason', 'Reason', width: 250.w),
                  _col('action', '', width: 70.w),
                ],
              ),
            ),
          ),
        ),

        /// 🔥 PAGINATION
        if (_source!.totalPages > 0)
          SfDataPager(
            delegate: _source!,
            pageCount: _source!.totalPages.toDouble(),
            visibleItemsCount: 5,
            onPageNavigationStart: (pageIndex) {
              _source!.handlePageChange(0, pageIndex);
            },
          ),
      ],
    );
  }

  /// ===============================
  /// 🔥 COLUMN
  /// ===============================
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
        padding: const EdgeInsets.all(8),
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  /// ===============================
  /// 🔥 EXPORT DIALOG
  /// ===============================
  void _showExportDialog() {
    final bloc = context.read<InventoryBloc>();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Export Formulary"),
        backgroundColor: Colors.white,
        content: const Text("Choose export type"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              bloc.add(ExportFormularyCurrent());
            },
            child: const Text(
              "Export current",
              style: TextStyle(color: AppColors.primaryColor),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              bloc.add(ExportFormularyWithHistory());
            },
            child: const Text(
              "Export with history",
              style: TextStyle(color: AppColors.secondaryColor),
            ),
          ),
        ],
      ),
    );
  }
}
