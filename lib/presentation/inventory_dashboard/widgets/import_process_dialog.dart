import 'package:daily_order/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../bloc/inventory_bloc.dart';
import '../bloc/inventory_event.dart';
import '../bloc/inventory_state.dart';

/// ===============================
/// 🔥 IMPORT TYPES
/// ===============================
enum ImportType { maxAdj, assortment, tma, formulary }

/// ===============================
/// 🔥 DIALOG
/// ===============================
class ImportProgressDialog extends StatefulWidget {
  final ImportType type;

  const ImportProgressDialog({super.key, required this.type});

  @override
  State<ImportProgressDialog> createState() => _ImportProgressDialogState();
}

class _ImportProgressDialogState extends State<ImportProgressDialog> {
  bool forceApply = false;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<InventoryBloc, InventoryState>(
      buildWhen: (previous, current) {
        return previous.importMessage != current.importMessage ||
            previous.importProgress != current.importProgress ||
            previous.isImporting != current.isImporting;
      },
      builder: (context, state) {
        return AlertDialog(
          backgroundColor: Colors.white,

          /// 🔥 TITLE DYNAMIC
          title: Text(_getTitle()),

          content: SizedBox(
            width: 400.w,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                /// 🔥 FORCE APPLY
                CheckboxListTile(
                  value: forceApply,
                  onChanged: state.isImporting
                      ? null
                      : (v) => setState(() => forceApply = v!),
                  title: const Text("Force Apply (Replace existing)"),
                  checkColor: AppColors.white,
                  activeColor: AppColors.primaryColor,
                ),

                const SizedBox(height: 10),

                /// 🔥 PROGRESS
                if (state.isImporting) ...[
                  LinearProgressIndicator(
                    value: state.importProgress,
                    color: AppColors.primaryColor,
                    backgroundColor: AppColors.primaryColor,
                  ),
                  const SizedBox(height: 10),
                  Text("${(state.importProgress * 100).toStringAsFixed(0)}%"),
                  const SizedBox(height: 10),
                ],

                /// 🔥 MESSAGE
                if (state.importMessage != null)
                  Text(
                    state.importMessage!,
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w500,
                      color: _getMessageColor(state),
                    ),
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),

          actions: [
            /// 🔥 TEMPLATE
            TextButton(
              onPressed: state.isImporting
                  ? null
                  : () => _onDownloadTemplate(context),
              child: const Text(
                "Download Template",
                style: TextStyle(color: AppColors.secondaryColor),
              ),
            ),

            /// 🔥 UPLOAD
            ElevatedButton(
              onPressed: state.isImporting ? null : () => _onUpload(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
              ),
              child: const Text(
                "Upload",
                style: TextStyle(color: Colors.white),
              ),
            ),

            /// 🔥 CLOSE
            if (!state.isImporting)
              TextButton(
                onPressed: () {
                  context.read<InventoryBloc>().add(ResetImportState());
                  Navigator.pop(context);
                },
                child: const Text("Close", style: TextStyle(color: Colors.red)),
              ),
          ],
        );
      },
    );
  }

  /// ===============================
  /// 🔥 UPLOAD HANDLER
  /// ===============================
  void _onUpload(BuildContext context) {
    final bloc = context.read<InventoryBloc>();

    switch (widget.type) {
      case ImportType.maxAdj:
        bloc.add(ImportMaxAdjExcel(forceApply: forceApply));
        break;

      case ImportType.assortment:
        bloc.add(ImportAssortmentExcel(forceApply: forceApply));
        break;

      case ImportType.tma:
        bloc.add(ImportTmaExcel(forceApply: forceApply));
        break;
      case ImportType.formulary:
        bloc.add(ImportFormularyExcel(forceApply: forceApply));
        break;
    }
  }

  /// ===============================
  /// 🔥 TEMPLATE HANDLER
  /// ===============================
  void _onDownloadTemplate(BuildContext context) {
    final bloc = context.read<InventoryBloc>();

    switch (widget.type) {
      case ImportType.maxAdj:
        bloc.add(ExportMaxAdjTemplate());
        break;

      case ImportType.assortment:
        bloc.add(ExportAssortmentTemplate());
        break;

      case ImportType.tma:
        bloc.add(ExportTmaTemplate());
        break;
      case ImportType.formulary:
        bloc.add(ExportFormularyTemplate());
        break;
    }
  }

  /// ===============================
  /// 🔥 TITLE
  /// ===============================
  String _getTitle() {
    switch (widget.type) {
      case ImportType.maxAdj:
        return "Import Max Adjustment";
      case ImportType.assortment:
        return "Import Assortment";
      case ImportType.tma:
        return "Import TMA";
      case ImportType.formulary:
        return "Import Formulary";
    }
  }

  /// ===============================
  /// 🔥 MESSAGE COLOR
  /// ===============================
  Color _getMessageColor(InventoryState state) {
    if (state.importSuccess == true) {
      return Colors.green;
    } else if (state.importSuccess == false) {
      return Colors.red;
    } else {
      return Colors.black;
    }
  }
}
