import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/product_movement_excel_exporter.dart';
import '../../../domain/entities/product_movement.dart';
import '../product_movement/bloc/product_movement_bloc.dart';
import '../product_movement/bloc/product_movement_event.dart';
import '../product_movement/bloc/product_movement_state.dart';

class ProductMovementPage extends StatefulWidget {
  const ProductMovementPage({super.key});

  @override
  State<ProductMovementPage> createState() => _ProductMovementPageState();
}

class _ProductMovementPageState extends State<ProductMovementPage> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF4F7FB),
      body: BlocBuilder<ProductMovementBloc, ProductMovementState>(
        builder: (context, state) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Header(state: state),
                const SizedBox(height: 18),
                _Filters(state: state, searchController: _searchController),
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
  final ProductMovementState state;

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
              Icons.move_down_rounded,
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
                  'Product Movement',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Track daily orders and additional requests across branches',
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
            label: 'Rows',
            value: state.rows.length.toString(),
            icon: Icons.table_rows_rounded,
          ),
          const SizedBox(width: 12),
          _StatPill(
            label: 'Daily',
            value: state.dailyCount.toString(),
            icon: Icons.shopping_cart_rounded,
          ),
          const SizedBox(width: 12),
          _StatPill(
            label: 'Additional',
            value: state.additionalCount.toString(),
            icon: Icons.add_box_rounded,
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 19),
          const SizedBox(width: 9),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xffDBEAFE),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
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
  final ProductMovementState state;
  final TextEditingController searchController;

  const _Filters({required this.state, required this.searchController});

  @override
  Widget build(BuildContext context) {
    final showSuggestions = state.suggestions.isNotEmpty;
    final suggestionsSpace = showSuggestions
        ? (state.suggestions.length * 66.0 + 18).clamp(96.0, 300.0)
        : 0.0;

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
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: TextField(
                      controller: searchController,
                      onChanged: (value) {
                        context.read<ProductMovementBloc>().add(
                          ProductMovementQueryChanged(value),
                        );
                      },
                      decoration: _inputDecoration(
                        label: 'Search item code or item name',
                        icon: Icons.search_rounded,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(flex: 3, child: _BranchSelector(state: state)),
                  const SizedBox(width: 14),
                  SizedBox(width: 250, child: _DateRangeButton(state: state)),
                  const SizedBox(width: 14),
                  SizedBox(
                    width: 230,
                    child: _MovementTypeSelector(state: state),
                  ),
                  const SizedBox(width: 14),
                  SizedBox(
                    height: 56,
                    child: FilledButton.icon(
                      onPressed: state.rows.isEmpty
                          ? null
                          : () {
                              final itemLabel = state.selectedItemName.isEmpty
                                  ? state.selectedItemCode
                                  : '${state.selectedItemCode} - ${state.selectedItemName}';
                              ProductMovementExcelExporter.export(
                                itemLabel: itemLabel,
                                branchLabel:
                                    state.selectedBranch ?? 'All Branches',
                                from: state.dateRange.start,
                                to: state.dateRange.end,
                                movementTypeLabel: _movementTypeTitle(
                                  state.movementType,
                                ),
                                rows: state.rows,
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
                      icon: const Icon(Icons.download_rounded),
                      label: const Text(
                        'Export',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
              if (showSuggestions) SizedBox(height: suggestionsSpace),
              const SizedBox(height: 12),
              Row(
                children: [
                  _FilterChip(
                    icon: Icons.storefront_rounded,
                    label: state.selectedBranch ?? 'All Branches',
                    color: const Color(0xff0EA5E9),
                  ),
                  const SizedBox(width: 10),
                  _FilterChip(
                    icon: Icons.calendar_month_rounded,
                    label:
                        '${_formatDate(state.dateRange.start)} -> ${_formatDate(state.dateRange.end)}',
                    color: const Color(0xff8B5CF6),
                  ),
                  const SizedBox(width: 10),
                  _FilterChip(
                    icon: Icons.tune_rounded,
                    label: _movementTypeTitle(state.movementType),
                    color: const Color(0xffF97316),
                  ),
                ],
              ),
            ],
          ),
          if (showSuggestions)
            Positioned(
              top: 64,
              left: 0,
              width: 610,
              child: _ProductSuggestions(
                suggestions: state.suggestions,
                onSelected: (item) {
                  final itemCode = (item['item_code'] ?? '').toString();
                  final itemName = (item['item_name'] ?? '').toString();
                  searchController.text = itemName.isEmpty
                      ? itemCode
                      : '$itemCode - $itemName';
                  context.read<ProductMovementBloc>().add(
                    ProductMovementSuggestionSelected(
                      itemCode: itemCode,
                      itemName: itemName,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _BranchSelector extends StatelessWidget {
  final ProductMovementState state;

  const _BranchSelector({required this.state});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: state.loadingBranches
          ? null
          : () async {
              final bloc = context.read<ProductMovementBloc>();
              final selected = await _showBranchPicker(
                context: context,
                branches: state.branches,
                selectedBranch: state.selectedBranch,
              );
              if (selected == _noSelectionSentinel) return;
              bloc.add(ProductMovementBranchChanged(selected));
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
                state.selectedBranch ?? 'All Branches',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xff102A43),
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
    );
  }
}

class _ProductSuggestions extends StatelessWidget {
  final List<Map<String, dynamic>> suggestions;
  final ValueChanged<Map<String, dynamic>> onSelected;

  const _ProductSuggestions({
    required this.suggestions,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 280),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xffD8E5F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: suggestions.length,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, color: Color(0xffE8EEF5)),
        itemBuilder: (context, index) {
          final item = suggestions[index];
          final itemCode = (item['item_code'] ?? '').toString();
          final itemName = (item['item_name'] ?? '').toString();
          final barcode = (item['barcode'] ?? '').toString();

          return InkWell(
            onTap: () => onSelected(item),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xffE0F2FE),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.medication_liquid_rounded,
                      color: AppColors.primaryColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          itemName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xff102A43),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          barcode.isEmpty ? itemCode : '$itemCode  •  $barcode',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xff64748B),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: Color(0xff94A3B8),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DateRangeButton extends StatelessWidget {
  final ProductMovementState state;

  const _DateRangeButton({required this.state});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        final bloc = context.read<ProductMovementBloc>();
        final result = await showDialog<DateTimeRange>(
          context: context,
          barrierColor: Colors.black26,
          builder: (_) => _DateRangePickerDialog(initialRange: state.dateRange),
        );

        if (result == null) return;
        bloc.add(ProductMovementDateRangeChanged(result));
      },
      child: InputDecorator(
        decoration: _inputDecoration(
          label: 'Date Range',
          icon: Icons.date_range_rounded,
        ),
        child: Text(
          '${_formatDate(state.dateRange.start)} -> ${_formatDate(state.dateRange.end)}',
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            color: Color(0xff102A43),
          ),
        ),
      ),
    );
  }
}

class _MovementTypeSelector extends StatelessWidget {
  final ProductMovementState state;

  const _MovementTypeSelector({required this.state});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: state.movementType,
      decoration: _inputDecoration(
        label: 'Movement Type',
        icon: Icons.category_rounded,
      ),
      borderRadius: BorderRadius.circular(18),
      items: const [
        DropdownMenuItem(value: 'all', child: Text('All Movements')),
        DropdownMenuItem(value: 'daily_order', child: Text('Daily Order')),
        DropdownMenuItem(
          value: 'additional_request',
          child: Text('Additional Request'),
        ),
      ],
      onChanged: (value) {
        if (value == null) return;
        context.read<ProductMovementBloc>().add(
          ProductMovementTypeChanged(value),
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _FilterChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _Content extends StatelessWidget {
  final ProductMovementState state;

  const _Content({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state.error.isNotEmpty) {
      return _StateCard(
        icon: Icons.error_outline_rounded,
        title: 'Could not load product movement',
        body: state.error,
        color: const Color(0xffEF4444),
      );
    }

    if (!state.searched && state.query.trim().isEmpty) {
      return const _StateCard(
        icon: Icons.manage_search_rounded,
        title: 'Search for a product',
        body:
            'Type an item code or item name to see movement across all branches.',
        color: Color(0xff0EA5E9),
      );
    }

    if (state.selectedItemCode.trim().isEmpty) {
      return const _StateCard(
        icon: Icons.touch_app_rounded,
        title: 'Choose a product',
        body: 'Select an item from the suggestions to load movement history.',
        color: Color(0xff8B5CF6),
      );
    }

    if (state.loadingRows && state.rows.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryColor),
      );
    }

    if (state.rows.isEmpty) {
      return const _StateCard(
        icon: Icons.inventory_2_outlined,
        title: 'No movement found',
        body: 'Try another product, branch, movement type, or date range.',
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
                  Icons.timeline_rounded,
                  color: AppColors.primaryColor,
                ),
                const SizedBox(width: 10),
                const Text(
                  'Movement Timeline',
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
          SizedBox(width: 58, child: _HeaderText('#')),
          Expanded(flex: 2, child: _HeaderText('Branch')),
          Expanded(flex: 2, child: _HeaderText('Item Code')),
          Expanded(flex: 4, child: _HeaderText('Item Name')),
          Expanded(flex: 2, child: _HeaderText('Movement')),
          Expanded(flex: 1, child: _HeaderText('Qty')),
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
  final ProductMovement row;

  const _MovementRow({required this.index, required this.row});

  @override
  Widget build(BuildContext context) {
    final isDaily = row.movementType == 'daily_order';
    final color = isDaily ? const Color(0xff2563EB) : const Color(0xffF97316);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      color: index.isEven ? const Color(0xffFBFDFF) : Colors.white,
      child: Row(
        children: [
          SizedBox(
            width: 58,
            child: Text(
              index.toString(),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            flex: 2,
            child: SelectableText(
              row.branch,
              //  overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xff102A43),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: SelectableText(
              row.itemCode,
              style: const TextStyle(
                color: Color(0xff0F3B66),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: SelectableText(
              row.itemName,
              maxLines: 2,
              //  overflow: TextOverflow.ellipsis,
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
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: color.withValues(alpha: .2)),
                ),
                child: SelectableText(
                  isDaily ? 'Daily Order' : 'Additional',
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: SelectableText(
              _formatNum(row.qty),
              style: const TextStyle(
                color: Color(0xff15803D),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: SelectableText(
              _formatDate(row.movementDate),
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
        width: 560,
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

class _DateRangePickerDialog extends StatefulWidget {
  final DateTimeRange initialRange;

  const _DateRangePickerDialog({required this.initialRange});

  @override
  State<_DateRangePickerDialog> createState() => _DateRangePickerDialogState();
}

class _DateRangePickerDialogState extends State<_DateRangePickerDialog> {
  late DateTime _start;
  DateTime? _end;
  DateTime? _hoverDay;
  late DateTime _leftMonth;
  bool _selectingEnd = false;

  static const _accent = Color(0xff06B6D4);
  static const _accentBg = Color(0xffCCF2F8);
  static const _textPri = Color(0xff1E293B);
  static const _textSec = Color(0xff64748B);
  static const _textHint = Color(0xff94A3B8);
  static const _border = Color(0xffE2E8F0);
  static const _inputBg = Color(0xffF1F5F9);
  static const _surfaceBg = Color(0xffF8FAFC);

  static const _weekdays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  static const _monthsShort = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  void initState() {
    super.initState();
    _start = _d(widget.initialRange.start);
    _end = _d(widget.initialRange.end);
    _leftMonth = DateTime(_start.year, _start.month);
  }

  DateTime _d(DateTime dt) => DateTime(dt.year, dt.month, dt.day);
  DateTime get _rightMonth => DateTime(_leftMonth.year, _leftMonth.month + 1);

  bool _same(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _inRange(DateTime day) {
    final endRef = _end ?? (_selectingEnd ? _hoverDay : null);
    if (endRef == null) return false;
    final s = _start.isBefore(endRef) ? _start : endRef;
    final e = _start.isBefore(endRef) ? endRef : _start;
    return day.isAfter(s) && day.isBefore(e);
  }

  bool _isStart(DateTime day) => _same(day, _start);

  bool _isEnd(DateTime day) {
    final endRef = _end ?? (_selectingEnd ? _hoverDay : null);
    return endRef != null && _same(day, endRef);
  }

  void _onDayTap(DateTime day) {
    setState(() {
      if (!_selectingEnd) {
        _start = day;
        _end = null;
        _selectingEnd = true;
      } else {
        if (day.isBefore(_start)) {
          _end = _start;
          _start = day;
        } else {
          _end = day;
        }
        _selectingEnd = false;
        _hoverDay = null;
      }
    });
  }

  void _onHover(DateTime? day) {
    if (_selectingEnd) setState(() => _hoverDay = day);
  }

  void _preset(DateTime s, DateTime e) {
    setState(() {
      _start = _d(s);
      _end = _d(e);
      _selectingEnd = false;
      _hoverDay = null;
      _leftMonth = DateTime(_start.year, _start.month);
    });
  }

  String _fmt(DateTime d) => '${_monthsShort[d.month - 1]} ${d.day}, ${d.year}';

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      elevation: 20,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: 840,
        height: 490,
        child: Row(
          children: [
            _buildSidebar(),
            Container(width: 1, color: _border),
            Expanded(
              child: Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildMonth(_leftMonth)),
                        Container(width: 1, color: _border),
                        Expanded(child: _buildMonth(_rightMonth)),
                      ],
                    ),
                  ),
                  _buildFooter(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    final now = DateTime.now();
    final today = _d(now);
    final weekStart = today.subtract(Duration(days: today.weekday % 7));
    final weekEnd = weekStart.add(const Duration(days: 6));
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 0);

    final presets = [
      ('Today', today, today),
      (
        'Yesterday',
        today.subtract(const Duration(days: 1)),
        today.subtract(const Duration(days: 1)),
      ),
      ('This Week', weekStart, weekEnd),
      ('Last 7 Days', today.subtract(const Duration(days: 6)), today),
      ('This Month', monthStart, monthEnd),
      ('Last 30 Days', today.subtract(const Duration(days: 29)), today),
      ('Last 3 Months', DateTime(now.year, now.month - 2, 1), monthEnd),
      ('Last 6 Months', DateTime(now.year, now.month - 5, 1), monthEnd),
    ];

    return Container(
      width: 155,
      color: _surfaceBg,
      padding: const EdgeInsets.fromLTRB(10, 16, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 6, bottom: 8),
            child: Text(
              'QUICK SELECT',
              style: TextStyle(
                color: _textHint,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
          ...presets.map((p) {
            final active =
                _end != null && _same(_start, p.$2) && _same(_end!, p.$3);
            return GestureDetector(
              onTap: () => _preset(p.$2, p.$3),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 3),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: active
                      ? _accent.withValues(alpha: 0.10)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: active
                      ? Border.all(color: _accent.withValues(alpha: 0.3))
                      : null,
                ),
                child: Text(
                  p.$1,
                  style: TextStyle(
                    color: active ? _accent : _textPri,
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          _navBtn(
            Icons.chevron_left,
            () => setState(
              () =>
                  _leftMonth = DateTime(_leftMonth.year, _leftMonth.month - 1),
            ),
          ),
          const SizedBox(width: 6),
          _navBtn(
            Icons.chevron_right,
            () => setState(
              () =>
                  _leftMonth = DateTime(_leftMonth.year, _leftMonth.month + 1),
            ),
          ),
          const SizedBox(width: 14),
          _dateChip('From', _fmt(_start), !_selectingEnd),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Icon(
              Icons.arrow_forward_rounded,
              size: 14,
              color: _textHint,
            ),
          ),
          _dateChip(
            'To',
            _end != null
                ? _fmt(_end!)
                : _selectingEnd
                ? 'Pick end...'
                : '-',
            _selectingEnd,
            faded: _end == null,
          ),
          const Spacer(),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, size: 18, color: _textSec),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _navBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: _inputBg,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: _border),
        ),
        child: Icon(icon, size: 16, color: _textSec),
      ),
    );
  }

  Widget _dateChip(
    String label,
    String text,
    bool active, {
    bool faded = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: active ? _accent.withValues(alpha: 0.08) : _surfaceBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: active ? _accent.withValues(alpha: 0.35) : _border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: active ? _accent : _textHint,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          Text(
            text,
            style: TextStyle(
              color: faded
                  ? _textHint
                  : active
                  ? _accent
                  : _textPri,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonth(DateTime month) {
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    final offset = DateTime(month.year, month.month, 1).weekday % 7;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Column(
        children: [
          Text(
            '${_months[month.month - 1]} ${month.year}',
            style: const TextStyle(
              color: _textPri,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: _weekdays
                .map(
                  (w) => Expanded(
                    child: Center(
                      child: Text(
                        w,
                        style: const TextStyle(
                          color: _textSec,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 4),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.1,
            ),
            itemCount: offset + days,
            itemBuilder: (_, i) {
              if (i < offset) return const SizedBox();
              final day = DateTime(month.year, month.month, i - offset + 1);
              return _buildCell(day);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCell(DateTime day) {
    final isStart = _isStart(day);
    final isEnd = _isEnd(day);
    final inRange = _inRange(day);
    final isFuture = day.isAfter(DateTime.now());
    final isEdge = isStart || isEnd;

    final endRef = _end ?? (_selectingEnd ? _hoverDay : null);
    bool stripLeft = false;
    bool stripRight = false;
    if (endRef != null) {
      final s = _start.isBefore(endRef) ? _start : endRef;
      final e = _start.isBefore(endRef) ? endRef : _start;
      if (!day.isBefore(s) && !day.isAfter(e)) {
        stripLeft = !_same(day, s);
        stripRight = !_same(day, e);
      }
    }

    Color textColor = isFuture ? const Color(0xffCBD5E1) : _textPri;
    if (isEdge) {
      textColor = Colors.white;
    } else if (inRange) {
      textColor = _accent;
    }

    return MouseRegion(
      onEnter: (_) => _onHover(day),
      onExit: (_) => _onHover(null),
      cursor: isFuture
          ? SystemMouseCursors.forbidden
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: isFuture ? null : () => _onDayTap(day),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Row(
              children: [
                Expanded(
                  child: Container(
                    color: stripLeft ? _accentBg : Colors.transparent,
                  ),
                ),
                Expanded(
                  child: Container(
                    color: stripRight ? _accentBg : Colors.transparent,
                  ),
                ),
              ],
            ),
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isEdge ? _accent : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${day.day}',
                style: TextStyle(
                  color: textColor,
                  fontSize: 11,
                  fontWeight: isEdge ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          if (_end != null)
            Text(
              '${_fmt(_start)} -> ${_fmt(_end!)}',
              style: const TextStyle(color: _textSec, fontSize: 11),
            ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(foregroundColor: _textSec),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _end != null
                ? () => Navigator.of(
                    context,
                  ).pop(DateTimeRange(start: _start, end: _end!))
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _border,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Apply',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

const _noSelectionSentinel = '__no_selection__';

Future<String?> _showBranchPicker({
  required BuildContext context,
  required List<String> branches,
  required String? selectedBranch,
}) {
  final controller = TextEditingController();
  var filtered = <String?>[null, ...branches];

  return showDialog<String?>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Container(
              width: 540,
              constraints: const BoxConstraints(maxHeight: 660),
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
                        onPressed: () =>
                            Navigator.pop(dialogContext, _noSelectionSentinel),
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
                            ? <String?>[null, ...branches]
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
                              final isAll = branch == null;

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
                                    color:
                                        selected ||
                                            isAll && selectedBranch == null
                                        ? const Color(0xffE0F2FE)
                                        : const Color(0xffF8FAFC),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color:
                                          selected ||
                                              isAll && selectedBranch == null
                                          ? AppColors.primaryColor
                                          : const Color(0xffE2E8F0),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        selected ||
                                                isAll && selectedBranch == null
                                            ? Icons.check_circle_rounded
                                            : isAll
                                            ? Icons.all_inclusive_rounded
                                            : Icons.storefront_rounded,
                                        color:
                                            selected ||
                                                isAll && selectedBranch == null
                                            ? AppColors.primaryColor
                                            : const Color(0xff64748B),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          branch ?? 'All Branches',
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

String _movementTypeTitle(String value) {
  switch (value) {
    case 'daily_order':
      return 'Daily Order';
    case 'additional_request':
      return 'Additional Request';
    default:
      return 'All Movements';
  }
}

String _formatDate(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

String _formatDateTime(DateTime date) {
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '${_formatDate(date)} $hour:$minute';
}

String _formatNum(num value) {
  if (value % 1 == 0) {
    return value.toInt().toString();
  }
  return value.toStringAsFixed(2);
}
