import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/app_colors.dart';
import '../bloc/inventory_bloc.dart';
import '../bloc/inventory_event.dart';
import '../bloc/inventory_state.dart';
import '../widgets/mismatch_review_workspace.dart';

/// Inventory's live review workspace; original Excel exports remain available.
class MismatchPage extends StatelessWidget {
  const MismatchPage({super.key});

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<InventoryBloc, InventoryState>(
        buildWhen: (previous, current) =>
            previous.isExporting != current.isExporting,
        builder: (context, state) => MismatchReviewWorkspace(
          exportInProgress: state.isExporting,
          onLegacyExport: (_, _) {
            final bloc = context.read<InventoryBloc>();
            showDialog<void>(
              context: context,
              builder: (_) => BlocProvider.value(
                value: bloc,
                child: const _MismatchExportDialog(),
              ),
            );
          },
        ),
      );
}

class _MismatchExportDialog extends StatelessWidget {
  const _MismatchExportDialog();

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
                              'Export Mismatch Report',
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
                  _MismatchExportOption(
                    icon: Icons.table_chart_outlined,
                    title: 'Current mismatch records',
                    subtitle:
                        'Exports all original active mismatch records, without review filters.',
                    enabled: !exporting,
                    onTap: () => context.read<InventoryBloc>().add(
                      ExportMismatchCurrent(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _MismatchExportOption(
                    icon: Icons.history_rounded,
                    title: 'Current records and history',
                    subtitle:
                        'Exports all original records and their update history, without review filters.',
                    enabled: !exporting,
                    onTap: () => context.read<InventoryBloc>().add(
                      ExportMismatchWithHistory(),
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

class _MismatchExportOption extends StatelessWidget {
  const _MismatchExportOption({
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
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.subText,
                        fontSize: 12,
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
