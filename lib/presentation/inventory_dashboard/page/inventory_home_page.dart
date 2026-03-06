import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../bloc/inventory_orders_bloc.dart';
import '../bloc/inventory_orders_event.dart';
import '../bloc/inventory_orders_state.dart';
import '../inventory_order_details/page/inventory_order_details_page.dart';

class InventoryHomePage extends StatelessWidget {
  const InventoryHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _InventoryView();
  }
}

class _InventoryView extends StatelessWidget {
  const _InventoryView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: BlocBuilder<InventoryOrdersBloc, InventoryOrdersState>(
            builder: (context, s) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Inventory Dashboard',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      _DateButton(
                        date: s.runDate,
                        onPick: (d) => context.read<InventoryOrdersBloc>().add(
                          SetRunDate(d),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: s.status == InventoryOrdersStatus.generating
                            ? null
                            : () => context.read<InventoryOrdersBloc>().add(
                                const GenerateAll(),
                              ),
                        icon: const Icon(Icons.bolt),
                        label: const Text('Orders Generate (All Branches)'),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => InventoryOrderDetailsPage(
                                branchName: '__ALL__',
                                runDate: s.runDate,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.table_view),
                        label: const Text('View All'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (s.status == InventoryOrdersStatus.generating) ...[
                    LinearProgressIndicator(value: s.progress / 100.0),
                    const SizedBox(height: 6),
                    Text(
                      '${s.progress}% ${s.progressMessage ?? ""} (${s.doneBranches}/${s.totalBranches})',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                  ],

                  if (s.status == InventoryOrdersStatus.failure &&
                      s.error != null)
                    Text(s.error!, style: const TextStyle(color: Colors.red)),

                  const SizedBox(height: 10),

                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          _Pager(
                            pageIndex: s.pageIndex,
                            onPrev: () {
                              if (s.pageIndex <= 0) return;
                              context.read<InventoryOrdersBloc>().add(
                                LoadHeaders(pageIndex: s.pageIndex - 1),
                              );
                            },
                            onNext: () {
                              context.read<InventoryOrdersBloc>().add(
                                LoadHeaders(pageIndex: s.pageIndex + 1),
                              );
                            },
                          ),
                          const Divider(height: 1),
                          Expanded(
                            child:
                                s.status == InventoryOrdersStatus.loading &&
                                    s.headers.isEmpty
                                ? const Center(
                                    child: CircularProgressIndicator(
                                      color: AppColors.primaryColor,
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: s.headers.length,
                                    separatorBuilder: (_, __) =>
                                        const Divider(height: 1),
                                    itemBuilder: (_, i) {
                                      final h = s.headers[i];

                                      final branchName =
                                          (h['branch_name'] ??
                                                  h['branch'] ??
                                                  '')
                                              .toString();

                                      final branchId = (h['branch_id'] ?? '')
                                          .toString();

                                      final dateFromRow =
                                          (h['order_date'] ??
                                                  h['order_date'] ??
                                                  '')
                                              .toString();
                                      final shownDate = dateFromRow.isNotEmpty
                                          ? dateFromRow
                                          : s.runDate;

                                      final totalItems =
                                          (h['total_items'] ?? '').toString();

                                      return ListTile(
                                        title: Text(
                                          branchName.isEmpty ? '-' : branchName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        subtitle: Text(
                                          totalItems.isEmpty
                                              ? 'Date: $shownDate'
                                              : 'Date: $shownDate   Items: $totalItems',
                                        ),
                                        trailing: const Icon(
                                          Icons.chevron_right,
                                        ),
                                        onTap: branchId.isEmpty
                                            ? null
                                            : () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        InventoryOrderDetailsPage(
                                                          branchName: '__ALL__',
                                                          runDate: s.runDate,
                                                        ),
                                                  ),
                                                );
                                              },
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Pager extends StatelessWidget {
  final int pageIndex;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _Pager({
    required this.pageIndex,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Text(
            'Page: ${pageIndex + 1}',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left),
            label: const Text('Prev'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
            label: const Text('Next'),
          ),
        ],
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  final String date;
  final ValueChanged<String> onPick;

  const _DateButton({required this.date, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.calendar_today),
      label: Text(date),
      onPressed: () async {
        final now = DateTime.tryParse(date) ?? DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: now,
          firstDate: DateTime(2024),
          lastDate: DateTime(2035),
        );
        if (picked == null) return;

        final d =
            '${picked.year.toString().padLeft(4, '0')}-'
            '${picked.month.toString().padLeft(2, '0')}-'
            '${picked.day.toString().padLeft(2, '0')}';

        onPick(d);
      },
    );
  }
}
