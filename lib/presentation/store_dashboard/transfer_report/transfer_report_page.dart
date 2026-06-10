import 'package:daily_order/presentation/store_dashboard/transfer_report/widget/transfer_report_grid.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/transfer_report_excel_exporter.dart';
import 'bloc/transfer_report_bloc.dart';
import 'bloc/transfer_report_event.dart';
import 'bloc/transfer_report_state.dart';

class TransferReportPage extends StatelessWidget {
  final String runDate;

  const TransferReportPage({super.key, required this.runDate});

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: Scaffold(
        backgroundColor: const Color(0xffF4F7FB),

        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          title: const Text(
            'Transfer Reconciliation Report',
            style: TextStyle(
              color: Color(0xff243B53),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),

        body: BlocBuilder<TransferReportBloc, TransferReportState>(
          builder: (context, state) {
            return Stack(
              children: [
                Column(
                  children: [
                    const SizedBox(height: 20),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xff243B53),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 14,
                              ),
                            ),
                            onPressed: () async {
                              final file = await FilePicker.platform.pickFiles(
                                type: FileType.custom,
                                allowedExtensions: ['csv'],
                                withData: true,
                              );

                              if (file == null) {
                                return;
                              }

                              context.read<TransferReportBloc>().add(
                                ImportTransferFile(
                                  bytes: file.files.first.bytes!,
                                  runDate: runDate,
                                ),
                              );
                            },
                            icon: const Icon(Icons.upload_file),
                            label: const Text('Upload CSV'),
                          ),
                          const SizedBox(width: 12),

                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 14,
                              ),
                            ),
                            onPressed: state.rows.isEmpty
                                ? null
                                : () {
                                    TransferReportExcelExporter.export(
                                      state.filteredRows,
                                    );
                                  },
                            icon: const Icon(Icons.download),
                            label: const Text('Export'),
                          ),

                          const SizedBox(width: 16),

                          _filterChip(context, 'ALL', state.filter),

                          const SizedBox(width: 8),

                          _filterChip(context, 'COMPLETE', state.filter),

                          const SizedBox(width: 8),

                          _filterChip(context, 'PARTIAL', state.filter),

                          const SizedBox(width: 8),

                          _filterChip(context, 'MISSING', state.filter),

                          const SizedBox(width: 8),

                          _filterChip(context, 'EXTRA', state.filter),
                          const SizedBox(width: 8),

                          _filterChip(
                            context,
                            'NOT_IN_DAILY_ORDER',
                            state.filter,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        children: [
                          Expanded(
                            child: _summaryCard(
                              title: 'Complete',
                              value: state.complete.toString(),
                              color: const Color(0xff2ECC71),
                            ),
                          ),

                          const SizedBox(width: 12),

                          Expanded(
                            child: _summaryCard(
                              title: 'Partial',
                              value: state.partial.toString(),
                              color: const Color(0xffF39C12),
                            ),
                          ),

                          const SizedBox(width: 12),

                          Expanded(
                            child: _summaryCard(
                              title: 'Missing',
                              value: state.missing.toString(),
                              color: const Color(0xffE74C3C),
                            ),
                          ),

                          const SizedBox(width: 12),

                          Expanded(
                            child: _summaryCard(
                              title: 'Extra',
                              value: state.extra.toString(),
                              color: const Color(0xff3498DB),
                            ),
                          ),
                          const SizedBox(width: 12),

                          Expanded(
                            child: _summaryCard(
                              title: 'Not In Daily Order',
                              value: state.notInDailyOrder.toString(),
                              color: const Color(0xffC0392B),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: TransferReportGrid(rows: state.filteredRows),
                      ),
                    ),
                  ],
                ),

                if (state.loading)
                  Container(
                    color: Colors.black26,
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primaryColor,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _filterChip(BuildContext context, String value, String selected) {
    final active = selected.toUpperCase() == value.toUpperCase();

    return InkWell(
      onTap: () {
        context.read<TransferReportBloc>().add(ChangeStatusFilter(value));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: active ? const Color(0xff243B53) : Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          value,
          style: TextStyle(
            color: active ? Colors.white : Colors.black,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _summaryCard({
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      height: 110,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: const TextStyle(fontSize: 15, color: Colors.grey)),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
