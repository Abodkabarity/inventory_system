import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/items_tracker_record.dart';
import '../../../domain/entities/items_tracker_email.dart';
import '../../widgets/inventory_dropdown.dart';

Future<List<ItemsTrackerRecord>?> showTrackerEmailSelection({
  required BuildContext context,
  required List<ItemsTrackerRecord> records,
  bool newOnly = false,
}) => showDialog<List<ItemsTrackerRecord>>(
  context: context,
  builder: (_) =>
      ItemsTrackerEmailSelection(records: records, newOnly: newOnly),
);

/// Selection is scoped to a single team; changing teams clears the selection.
class ItemsTrackerEmailSelection extends StatefulWidget {
  final List<ItemsTrackerRecord> records;
  final bool newOnly;
  const ItemsTrackerEmailSelection({
    super.key,
    required this.records,
    this.newOnly = false,
  });
  @override
  State<ItemsTrackerEmailSelection> createState() =>
      _ItemsTrackerEmailSelectionState();
}

class _ItemsTrackerEmailSelectionState
    extends State<ItemsTrackerEmailSelection> {
  final _search = TextEditingController();
  final _selected = <String>{};
  late final List<ItemsTrackerRecord> _records;
  late final List<String> _teams;
  String? _team;
  @override
  void initState() {
    super.initState();
    _records =
        widget.records
            .where((r) => r.canSendEmail && (!widget.newOnly || r.isNewEmail))
            .toList()
          ..sort((a, b) => a.itemName.compareTo(b.itemName));
    _teams = _records.map((r) => r.followUpRole).toSet().toList()..sort();
    _team = _teams.firstOrNull;
    if (widget.newOnly) _selectVisible();
  }

  List<ItemsTrackerRecord> get _visible {
    final query = _search.text.trim().toLowerCase();
    return _records
        .where(
          (r) =>
              r.followUpRole == _team &&
              (query.isEmpty ||
                  '${r.itemCode} ${r.itemName} ${r.company} ${r.inventoryNote}'
                      .toLowerCase()
                      .contains(query)),
        )
        .toList();
  }

  void _selectVisible() {
    _selected.removeWhere(
      (id) => _records.any((r) => r.id == id && r.emailStatus == 'draft'),
    );
    for (final record in _visible) {
      if (record.emailStatus == 'draft') continue;
      if (_selected.length == 1000) break;
      _selected.add(record.id);
    }
  }

  void _toggle(ItemsTrackerRecord record, bool value) {
    if (!value) {
      _selected.remove(record.id);
      return;
    }
    if (record.emailStatus == 'draft') {
      _selected.clear();
    } else {
      _selected.removeWhere(
        (id) => _records.any((r) => r.id == id && r.emailStatus == 'draft'),
      );
    }
    _selected.add(record.id);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chosen = _records.where((r) => _selected.contains(r.id)).toList();
    final selectable = _visible.where((r) => r.emailStatus != 'draft').toList();
    final allVisibleSelected =
        selectable.isNotEmpty &&
        selectable.every((r) => _selected.contains(r.id));
    final continuing =
        chosen.length == 1 && chosen.single.emailStatus == 'draft';
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 850, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(22, 20, 12, 20),
              color: AppColors.secondaryColor,
              child: Row(
                children: [
                  const Icon(
                    Icons.outgoing_mail,
                    color: AppColors.primaryColor,
                    size: 28,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.newOnly
                              ? 'New product emails'
                              : 'Email selected products',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        const Text(
                          'One email · One follow-up department',
                          style: TextStyle(
                            color: Color(0xFFBAD8E8),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Close selection',
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Column(
                children: [
                  InventoryDropdown<String>(
                    value: _team,
                    label: 'Follow up by',
                    icon: const Icon(Icons.groups_outlined),
                    items: [
                      for (final team in _teams)
                        DropdownMenuItem(
                          value: team,
                          child: Text(
                            '${ItemsTrackerRoles.label(team)} (${_records.where((r) => r.followUpRole == team).length})',
                          ),
                        ),
                    ],
                    onChanged: (team) => setState(() {
                      _team = team;
                      _selected.clear();
                      if (widget.newOnly) _selectVisible();
                    }),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search product, code, company or reason',
                      prefixIcon: const Icon(
                        Icons.search,
                        color: AppColors.primaryColor,
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF5FAFE),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Checkbox(
                        value: allVisibleSelected,
                        activeColor: AppColors.primaryColor,
                        onChanged: selectable.isEmpty
                            ? null
                            : (value) => setState(() {
                                if (value == true) {
                                  _selectVisible();
                                } else {
                                  _selected.removeAll(
                                    _visible.map((r) => r.id),
                                  );
                                }
                              }),
                      ),
                      const Expanded(
                        child: Text(
                          'Select visible products',
                          style: TextStyle(
                            color: AppColors.secondaryColor,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Text(
                        '${chosen.length} selected',
                        style: const TextStyle(
                          color: AppColors.subText,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Flexible(
              child: _visible.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(30),
                      child: Text('No products available for this department.'),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: _visible.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, index) {
                        final record = _visible[index];
                        final selected = _selected.contains(record.id);
                        return Material(
                          color: selected
                              ? AppColors.primaryColor.withValues(alpha: .07)
                              : const Color(0xFFFBFCFE),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: selected
                                  ? AppColors.primaryColor.withValues(alpha: .5)
                                  : AppColors.border,
                            ),
                          ),
                          child: CheckboxListTile(
                            key: ValueKey('emailSelect:${record.id}'),
                            value: selected,
                            activeColor: AppColors.primaryColor,
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged: !selected && _selected.length >= 1000
                                ? null
                                : (value) => setState(
                                    () => _toggle(record, value == true),
                                  ),
                            title: Text(
                              record.itemName,
                              style: const TextStyle(
                                color: AppColors.secondaryColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 5),
                              child: Text(
                                '${record.itemCode} · ${record.company}\nQty ${ItemsTrackerEmailProduct.fromRecord(record).qtyLabel} · Total AED ${ItemsTrackerEmailProduct.money(record.requiredValue)}\n${record.emailStatus == 'draft' ? 'Saved draft · ' : ''}${record.inventoryNote}',
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.subText,
                                  fontSize: 11,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    continuing
                        ? 'Continue this saved draft with its original full product list. Discard the unsent draft first if you need to change its products.'
                        : widget.newOnly
                        ? 'Only products added after the new-email queue was introduced appear here. Saved drafts stay until you confirm sending.'
                        : 'Selection is kept while searching. Products already sent are excluded.',
                    style: const TextStyle(
                      color: AppColors.subText,
                      fontSize: 11,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const ValueKey('prepareSelectedEmail'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryColor,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: chosen.isEmpty
                        ? null
                        : () => Navigator.pop(context, chosen),
                    icon: const Icon(Icons.preview_outlined, size: 20),
                    label: Text(
                      continuing
                          ? 'Continue saved draft'
                          : 'Preview email · ${chosen.length} products',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
