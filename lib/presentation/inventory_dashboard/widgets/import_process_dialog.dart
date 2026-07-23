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
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<InventoryBloc, InventoryState>(
      buildWhen: (previous, current) {
        return previous.importMessage != current.importMessage ||
            previous.importProgress != current.importProgress ||
            previous.isImporting != current.isImporting ||
            previous.importDuplicateCount != current.importDuplicateCount ||
            previous.importDuplicateSource != current.importDuplicateSource;
      },
      builder: (context, state) {
        final hasDuplicates =
            state.importDuplicateCount > 0 &&
            state.importDuplicateSource == _duplicateSource;
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
                if (hasDuplicates) _duplicateDecision(state),

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
            if (!hasDuplicates)
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
            if (!hasDuplicates)
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
        bloc.add(ImportMaxAdjExcel(forceApply: false));
        break;

      case ImportType.assortment:
        bloc.add(ImportAssortmentExcel(forceApply: false));
        break;

      case ImportType.tma:
        bloc.add(ImportTmaExcel(forceApply: false));
        break;
      case ImportType.formulary:
        bloc.add(ImportFormularyExcel(forceApply: false));
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

  String get _duplicateSource => switch (widget.type) {
    ImportType.maxAdj => 'max_adjustment',
    ImportType.assortment => 'assortment',
    ImportType.tma => 'tma',
    ImportType.formulary => 'formulary',
  };

  Widget _duplicateDecision(InventoryState state) {
    final bloc = context.read<InventoryBloc>();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.blueSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.primaryColor.withValues(alpha: .35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.content_copy_rounded,
                color: AppColors.primaryColor,
              ),
              const SizedBox(width: 8),
              Text(
                '${state.importDuplicateCount} duplicate item(s) found',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 7),
          const Text(
            'Choose whether to keep existing items or update them from this file.',
            style: TextStyle(color: AppColors.subText, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => bloc.add(
                  ResolveImportDuplicates(
                    ImportDuplicateAction.applyWithoutDuplicates,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  backgroundColor: AppColors.secondaryColor,
                ),
                child: const Text(
                  'Apply without duplicates',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              ElevatedButton(
                onPressed: () => bloc.add(
                  ResolveImportDuplicates(
                    ImportDuplicateAction.applyWithDuplicates,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Apply with duplicates'),
              ),
              TextButton.icon(
                onPressed: () => bloc.add(
                  ResolveImportDuplicates(ImportDuplicateAction.download),
                ),
                icon: const Icon(
                  Icons.download_rounded,
                  color: AppColors.secondaryColor,
                ),
                label: const Text(
                  'Download duplicates',
                  style: TextStyle(color: AppColors.secondaryColor),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
