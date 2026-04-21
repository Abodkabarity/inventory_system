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
  @override
  void initState() {
    super.initState();
    context.read<InventoryBloc>().add(LoadAssortment());
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

                /// 🔥 HEADER
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    "Assortment",
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                ),

                const SizedBox(height: 20),

                /// 🔥 SEARCH BAR
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          onChanged: (v) {
                            context.read<InventoryBloc>().add(
                              SearchAssortment(v),
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
                            focusedBorder: OutlineInputBorder(
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
                          ),
                        ),
                      ),

                      const Spacer(),

                      ElevatedButton.icon(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (dialogContext) {
                              return BlocProvider.value(
                                value: context.read<InventoryBloc>(),
                                child: const ImportProgressDialog(
                                  type: ImportType.assortment,
                                ),
                              );
                            },
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
            if (state.isExporting)
              Container(
                color: Colors.black.withValues(alpha: 0.3),
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
  /// TABLE
  /// ===============================
  Widget _buildTable(InventoryState state) {
    if (state.isLoading && !state.isImporting) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.primaryColor),
            SizedBox(height: 10),
            Text("Loading data..."),
          ],
        ),
      );
    }

    final data = state.filteredAssortment;

    final source = AssortmentDataSource(
      data: data,
      onHistory: (e) {
        context.read<InventoryBloc>().add(
          LoadAssortmentHistory(e['item_code'], e['branch_name']),
        );
      },
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300, width: 1),
      ),

      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),

        child: SfDataGridTheme(
          data: SfDataGridThemeData(
            headerColor: AppColors.backgroundWidget,
            gridLineColor: Colors.grey.shade300,
          ),

          child: SfDataGrid(
            source: source,
            allowFiltering: true,
            showColumnHeaderIconOnHover: false,
            columnWidthMode: ColumnWidthMode.fill,
            showSortNumbers: true,
            allowSorting: true,
            allowColumnsResizing: true,
            selectionMode: SelectionMode.single,
            headerRowHeight: 55,
            rowHeight: 48,
            gridLinesVisibility: GridLinesVisibility.both,
            headerGridLinesVisibility: GridLinesVisibility.both,

            columns: [
              _col('index', '#', width: 70.w, center: true),
              _col('branch', 'Branch', width: 150.w, center: true),
              _col('code', 'Item Code', width: 140.w, center: true),
              _col('name', 'Item Name', width: 300.w, center: true),
              _col('qty', 'Qty', width: 120.w, center: true),
              _col('by', 'Added By', width: 140.w, center: true),
              _col('start', 'Start', width: 130.w, center: true),
              _col('end', 'End', width: 130.w, center: true),
              _col('action', '', width: 100.w, center: true),
            ],
          ),
        ),
      ),
    );
  }

  /// ===============================
  /// COLUMN BUILDER
  /// ===============================
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
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }

  void _showExportDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Export"),
        content: const Text("Choose export type"),
        actions: [
          TextButton(
            onPressed: () {
              final bloc = context.read<InventoryBloc>();

              Navigator.of(context).pop();

              Future.microtask(() {
                bloc.add(ExportAssortmentCurrent());
              });
            },
            child: const Text("Export current Assortment"),
          ),
          TextButton(
            onPressed: () {
              final bloc = context.read<InventoryBloc>();

              Navigator.pop(context);

              bloc.add(ExportAssortmentWithHistory());
            },
            child: const Text("Export Current and History"),
          ),
        ],
      ),
    );
  }
}
