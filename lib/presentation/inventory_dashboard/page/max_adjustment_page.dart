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
  @override
  void initState() {
    super.initState();
    context.read<InventoryBloc>().add(LoadMaxAdjustment());
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<InventoryBloc, InventoryState>(
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),

            /// 🔥 HEADER
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: const Text(
                "Max Adjustment",
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              ),
            ),

            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (v) {
                        context.read<InventoryBloc>().add(
                          SearchMaxAdjustment(v),
                        );
                      },
                      decoration: InputDecoration(
                        hintText: "Search item...",
                        filled: true,
                        fillColor: AppColors.backgroundWidget,
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: AppColors.primaryColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: AppColors.primaryColor),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: AppColors.primaryColor),
                        ),
                      ),
                    ),
                  ),

                  Spacer(),

                  ElevatedButton.icon(
                    onPressed: () {
                      final bloc = context.read<InventoryBloc>();

                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => BlocProvider.value(
                          value: bloc,
                          child: const ImportProgressDialog(
                            type: ImportType.maxAdj,
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

                  ElevatedButton.icon(
                    onPressed: _showExportDialog,
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

            /// TABLE
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _buildTable(state),
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
    if (state.isLoading) {
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
    final data = state.filteredMaxAdjustment;

    final source = MaxAdjDataSource(
      data: data,
      onHistory: (e) {
        context.read<InventoryBloc>().add(
          LoadMaxAdjustmentHistory(e['item_code'], e['branch_name']),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300, width: 1),
      ),

      /// 🔥 THEME
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
              _col('branch', 'Branch', width: 150.w),
              _col('code', 'Item Code', width: 140.w),
              _col('name', 'Item Name', width: 300.w),
              _col('demand', 'Demand', width: 120.w, center: true),
              _col('max', 'Max Adj', width: 120.w, center: true),
              _col('type', 'Type', width: 130.w, center: true),
              _col('qty', 'Qty', width: 100.w, center: true),
              _col('added_by', 'Added By', width: 130.w, center: true),
              _col('date', 'Date', width: 110.w, center: true),
              _col('action', '', width: 100.w),
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
              Navigator.pop(context);
              context.read<InventoryBloc>().add(ExportMaxAdjCurrent());
            },
            child: const Text("Export current Max Adjustment"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<InventoryBloc>().add(ExportMaxAdjWithHistory());
            },
            child: const Text("Export Current and History"),
          ),
        ],
      ),
    );
  }
}
