import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/branch_order_excel_exporter.dart';
import 'bloc/branch_order_bloc.dart';
import 'bloc/branch_order_event.dart';
import 'bloc/branch_order_state.dart';

class BranchOrderPage extends StatefulWidget {
  const BranchOrderPage({super.key});

  @override
  State<BranchOrderPage> createState() => _BranchOrderPageState();
}

class _BranchOrderPageState extends State<BranchOrderPage> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF4F7FB),
      body: BlocBuilder<BranchOrderBloc, BranchOrderState>(
        builder: (context, state) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Header(state: state),
                const SizedBox(height: 18),
                _Filters(
                  state: state,
                  searchController: _searchController,
                  onSearchChanged: (value) {
                    _searchDebounce?.cancel();
                    _searchDebounce = Timer(
                      const Duration(milliseconds: 350),
                      () {
                        context.read<BranchOrderBloc>().add(
                          BranchOrderSearchChanged(value),
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 18),
                Expanded(child: _Content(state: state)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final BranchOrderState state;

  const _Header({required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xff0EA5E9), Color(0xff2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xff0EA5E9).withValues(alpha: .22),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .18),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: .28)),
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Branch Order',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Daily order movement history by branch and date',
                  style: TextStyle(
                    color: Color(0xffE0F2FE),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _StatPill(
            label: 'Items',
            value: state.itemCount.toString(),
            icon: Icons.inventory_2_outlined,
          ),
          const SizedBox(width: 12),
          _StatPill(
            label: 'Total Qty',
            value: _formatNum(state.totalQty),
            icon: Icons.add_chart_rounded,
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatPill({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                label,
                style: const TextStyle(
                  color: Color(0xffDBEAFE),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SelectableText(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  final BranchOrderState state;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;

  const _Filters({
    required this.state,
    required this.searchController,
    required this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xffE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .04),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: state.loadingBranches
                  ? null
                  : () async {
                      final bloc = context.read<BranchOrderBloc>();
                      final selected = await _showBranchPicker(
                        context: context,
                        branches: state.branches,
                        selectedBranch: state.selectedBranch,
                      );
                      if (selected == null) return;
                      bloc.add(BranchOrderBranchChanged(selected));
                    },
              child: InputDecorator(
                decoration: _inputDecoration(
                  label: 'Branch',
                  icon: Icons.store_mall_directory_rounded,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        state.selectedBranch ?? 'Select Branch',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: state.selectedBranch == null
                              ? const Color(0xff94A3B8)
                              : const Color(0xff102A43),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Color(0xff64748B),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 240,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () async {
                final bloc = context.read<BranchOrderBloc>();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: state.selectedDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  builder: (context, child) {
                    return Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: const ColorScheme.light(
                          primary: AppColors.primaryColor,
                        ),
                      ),
                      child: child!,
                    );
                  },
                );

                if (picked == null) return;
                bloc.add(BranchOrderDateChanged(picked));
              },
              child: InputDecorator(
                decoration: _inputDecoration(
                  label: 'Order Date',
                  icon: Icons.calendar_today_rounded,
                ),
                child: Text(
                  _formatDate(state.selectedDate),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xff102A43),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 4,
            child: TextField(
              controller: searchController,
              onChanged: onSearchChanged,
              decoration: _inputDecoration(
                label: 'Search item code or item name',
                icon: Icons.search_rounded,
              ),
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            height: 56,
            child: FilledButton.icon(
              onPressed: state.selectedBranch == null || state.loadingRows
                  ? null
                  : () {
                      context.read<BranchOrderBloc>().add(
                        LoadBranchOrderRows(),
                      );
                    },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xff0F766E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 22),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: state.loadingRows
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: const Text(
                'Load',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 56,
            child: FilledButton.icon(
              onPressed: state.selectedBranch == null || state.rows.isEmpty
                  ? null
                  : () {
                      BranchOrderExcelExporter.export(
                        branch: state.selectedBranch!,
                        orderDate: state.selectedDate,
                        rows: state.rows,
                      );
                    },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xff2563EB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 22),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.download_rounded),
              label: const Text(
                'Export',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Content extends StatelessWidget {
  final BranchOrderState state;

  const _Content({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state.error.isNotEmpty) {
      return _StateCard(
        icon: Icons.error_outline_rounded,
        title: 'Could not load branch order',
        body: state.error,
        color: const Color(0xffEF4444),
      );
    }

    if (state.loadingRows && state.rows.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryColor),
      );
    }

    if (state.selectedBranch == null) {
      return const _StateCard(
        icon: Icons.storefront_rounded,
        title: 'Choose a branch',
        body: 'Select an active branch to view daily order movements.',
        color: Color(0xff0EA5E9),
      );
    }

    if (state.rows.isEmpty) {
      return const _StateCard(
        icon: Icons.inventory_2_outlined,
        title: 'No daily order movement',
        body: 'No daily_order rows were found for this branch and date.',
        color: Color(0xff64748B),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xffE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .04),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              children: [
                const Icon(
                  Icons.table_chart_rounded,
                  color: AppColors.primaryColor,
                ),
                const SizedBox(width: 10),
                const Text(
                  'Daily Order Rows',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xff102A43),
                  ),
                ),
                const Spacer(),
                if (state.loadingRows)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primaryColor,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          const _TableHeader(),
          Expanded(
            child: ListView.separated(
              itemCount: state.rows.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: Color(0xffE8EEF5)),
              itemBuilder: (context, index) {
                return _MovementRow(index: index + 1, row: state.rows[index]);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      color: const Color(0xffF8FAFC),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: const Row(
        children: [
          SizedBox(width: 70, child: _HeaderText('#')),
          Expanded(flex: 2, child: _HeaderText('Item Code')),
          Expanded(flex: 5, child: _HeaderText('Item Name')),
          Expanded(flex: 2, child: _HeaderText('Qty')),
          Expanded(flex: 2, child: _HeaderText('Order Date')),
        ],
      ),
    );
  }
}

class _HeaderText extends StatelessWidget {
  final String text;

  const _HeaderText(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xff64748B),
        fontSize: 12,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _MovementRow extends StatelessWidget {
  final int index;
  final Map<String, dynamic> row;

  const _MovementRow({required this.index, required this.row});

  @override
  Widget build(BuildContext context) {
    final qty = num.tryParse((row['qty'] ?? '0').toString()) ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      color: index.isEven ? const Color(0xffFBFDFF) : Colors.white,
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              index.toString(),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            flex: 2,
            child: SelectableText(
              (row['item_code'] ?? '').toString(),
              style: const TextStyle(
                color: Color(0xff0F3B66),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: SelectableText(
              (row['item_name'] ?? '').toString(),
              maxLines: 2,

              style: const TextStyle(
                color: Color(0xff102A43),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xffDCFCE7),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xffBBF7D0)),
                ),
                child: SelectableText(
                  _formatNum(qty),
                  style: const TextStyle(
                    color: Color(0xff15803D),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: SelectableText(
              (row['movement_date'] ?? '').toString(),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _StateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Color color;

  const _StateCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xffE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .05),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Color(0xff102A43),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xff64748B),
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<String?> _showBranchPicker({
  required BuildContext context,
  required List<String> branches,
  required String? selectedBranch,
}) {
  final controller = TextEditingController();
  var filtered = List<String>.from(branches);

  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Container(
              width: 520,
              constraints: const BoxConstraints(maxHeight: 640),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xffE0F2FE),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.store_mall_directory_rounded,
                          color: AppColors.primaryColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Select Branch',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Color(0xff102A43),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    onChanged: (value) {
                      final q = value.trim().toLowerCase();
                      setDialogState(() {
                        filtered = q.isEmpty
                            ? List<String>.from(branches)
                            : branches
                                  .where(
                                    (branch) =>
                                        branch.toLowerCase().contains(q),
                                  )
                                  .toList();
                      });
                    },
                    decoration: _inputDecoration(
                      label: 'Search branch...',
                      icon: Icons.search_rounded,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Flexible(
                    child: filtered.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(28),
                              child: Text(
                                'No branches found',
                                style: TextStyle(
                                  color: Color(0xff64748B),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final branch = filtered[index];
                              final selected = branch == selectedBranch;

                              return InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () =>
                                    Navigator.pop(dialogContext, branch),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 13,
                                  ),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? const Color(0xffE0F2FE)
                                        : const Color(0xffF8FAFC),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: selected
                                          ? AppColors.primaryColor
                                          : const Color(0xffE2E8F0),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        selected
                                            ? Icons.check_circle_rounded
                                            : Icons.storefront_rounded,
                                        color: selected
                                            ? AppColors.primaryColor
                                            : const Color(0xff64748B),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          branch,
                                          style: const TextStyle(
                                            color: Color(0xff102A43),
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  ).whenComplete(() => controller.dispose());
}

InputDecoration _inputDecoration({
  required String label,
  required IconData icon,
}) {
  return InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, color: AppColors.primaryColor),
    filled: true,
    fillColor: const Color(0xffF8FBFF),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xffD8E5F0)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xffD8E5F0)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: AppColors.primaryColor, width: 1.6),
    ),
  );
}

String _formatDate(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

String _formatNum(num value) {
  if (value % 1 == 0) {
    return value.toInt().toString();
  }
  return value.toStringAsFixed(2);
}
