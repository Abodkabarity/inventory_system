import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/inventory_bloc.dart';
import '../bloc/inventory_event.dart';
import '../bloc/inventory_state.dart';

class ImportProgressDialog extends StatefulWidget {
  const ImportProgressDialog({super.key});

  @override
  State<ImportProgressDialog> createState() => _ImportProgressDialogState();
}

class _ImportProgressDialogState extends State<ImportProgressDialog> {
  bool forceApply = false;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<InventoryBloc, InventoryState>(
      builder: (context, state) {
        return AlertDialog(
          title: const Text("Import Excel"),

          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(
                value: forceApply,
                onChanged: state.isImporting
                    ? null
                    : (v) => setState(() => forceApply = v!),
                title: const Text("Force Apply (Replace existing)"),
              ),

              const SizedBox(height: 10),

              if (state.isImporting) ...[
                LinearProgressIndicator(value: state.importProgress),
                const SizedBox(height: 10),
                Text("${(state.importProgress * 100).toStringAsFixed(0)}%"),
                const SizedBox(height: 10),
              ],

              if (state.importMessage != null) Text(state.importMessage!),
            ],
          ),

          actions: [
            TextButton(
              onPressed: state.isImporting
                  ? null
                  : () {
                      context.read<InventoryBloc>().add(ExportMaxAdjTemplate());
                    },
              child: const Text("Template"),
            ),

            /// Upload
            ElevatedButton(
              onPressed: state.isImporting
                  ? null
                  : () {
                      context.read<InventoryBloc>().add(
                        ImportMaxAdjExcel(forceApply: forceApply),
                      );
                    },
              child: const Text("Upload"),
            ),

            /// Close
            if (!state.isImporting)
              TextButton(
                onPressed: () {
                  context.read<InventoryBloc>().add(ResetImportState());
                  Navigator.pop(context);
                },
                child: const Text("Close"),
              ),
          ],
        );
      },
    );
  }
}
