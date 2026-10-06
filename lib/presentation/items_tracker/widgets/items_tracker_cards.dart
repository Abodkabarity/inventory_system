import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/entities/items_tracker_record.dart';
import '../../../domain/entities/items_tracker_column_filter.dart';
import '../../../core/theme/app_colors.dart';
import 'items_tracker_grid.dart';

/// A compact workspace: primary fields stay aligned, secondary fields live in
/// the product's side panel. Non-medicine products group by company and team.
class ItemsTrackerCards extends StatelessWidget {
  final List<ItemsTrackerRecord> records;
  final List<ItemsTrackerRecord> allRecords;
  final String role;
  final List<String> statusOptions;
  final Map<ItemsTrackerColumn, ItemsTrackerColumnFilter> columnFilters;
  final void Function(BuildContext anchor, ItemsTrackerColumn column)
  onColumnFilter;
  final ValueChanged<ItemsTrackerColumn> onClearColumnFilter;
  final ItemsTrackerStatusChanged onStatusUpdatedToChanged;
  final ItemsTrackerCaseStatusChanged onTrackerStatusChanged;
  final ValueChanged<ItemsTrackerRecord> onEditInventory;
  final ValueChanged<ItemsTrackerRecord> onAction;
  final ValueChanged<ItemsTrackerRecord> onHistory;
  final ValueChanged<ItemsTrackerRecord> onAttachment;
  final ValueChanged<ItemsTrackerRecord> onComment;
  final void Function(String company, String followUpRole) onCompanyAction;
  final ValueChanged<ItemsTrackerRecord> onEmail;
  final void Function(String company, String followUpRole) onCompanyEmail;

  const ItemsTrackerCards({
    super.key,
    required this.records,
    required this.allRecords,
    required this.role,
    required this.statusOptions,
    required this.columnFilters,
    required this.onColumnFilter,
    required this.onClearColumnFilter,
    required this.onStatusUpdatedToChanged,
    required this.onTrackerStatusChanged,
    required this.onEditInventory,
    required this.onAction,
    required this.onHistory,
    required this.onAttachment,
    required this.onComment,
    required this.onCompanyAction,
    required this.onEmail,
    required this.onCompanyEmail,
  });

  static const _ink = Color(0xff19344a);
  static const _muted = Color(0xff748494);
  static const _accent = Color(0xff087f8c);
  static const _border = Color(0xffe3eaf0);
  static const _flex = [21, 11, 9, 18, 20, 13, 18, 13, 14];

  (String, String) _groupKey(ItemsTrackerRecord record) => (
    record.company.trim().toLowerCase(),
    ItemsTrackerRoles.normalize(record.followUpRole),
  );

  @override
  Widget build(BuildContext context) {
    final companyCounts = <(String, String), int>{};
    for (final record in allRecords.where((item) => item.canGroupByCompany)) {
      final key = _groupKey(record);
      companyCounts[key] = (companyCounts[key] ?? 0) + 1;
    }
    final groups = <Object, List<ItemsTrackerRecord>>{};
    final orderedRecords = [
      ...records.where(
        (item) => item.caseStatus != ItemsTrackerCaseStatuses.done,
      ),
      ...records.where(
        (item) => item.caseStatus == ItemsTrackerCaseStatuses.done,
      ),
    ];
    for (final record in orderedRecords) {
      final company = _groupKey(record);
      final grouped =
          record.canGroupByCompany && (companyCounts[company] ?? 0) > 1;
      groups.putIfAbsent(grouped ? company : record.id, () => []).add(record);
    }
    bool completedGroup(MapEntry<Object, List<ItemsTrackerRecord>> entry) =>
        entry.value.every(
          (item) => item.caseStatus == ItemsTrackerCaseStatuses.done,
        );
    final entries = [
      ...groups.entries.where((entry) => !completedGroup(entry)),
      ...groups.entries.where(completedGroup),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        return Scrollbar(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: math.max(1700, constraints.maxWidth),
              height: constraints.maxHeight,
              child: Column(
                children: [
                  if (columnFilters.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      color: Colors.white,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '${records.length} matching items',
                            style: const TextStyle(
                              color: AppColors.subText,
                              fontSize: 12,
                            ),
                          ),
                          for (final column in columnFilters.keys)
                            InputChip(
                              label: Text(
                                column.label,
                                style: const TextStyle(
                                  color: AppColors.secondaryColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              avatar: const Icon(
                                Icons.filter_alt,
                                size: 14,
                                color: AppColors.primaryColor,
                              ),
                              backgroundColor: AppColors.backgroundWidget,
                              side: BorderSide.none,
                              onDeleted: () => onClearColumnFilter(column),
                              deleteIcon: const Icon(Icons.close, size: 14),
                            ),
                        ],
                      ),
                    ),
                  _columnHeader(),
                  Expanded(
                    child: records.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.filter_alt_off_outlined,
                                  size: 32,
                                  color: AppColors.subText,
                                ),
                                SizedBox(height: 12),
                                Text(
                                  'No matching items',
                                  style: TextStyle(
                                    color: AppColors.secondaryColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'Adjust the column filters or select Clear.',
                                  style: TextStyle(
                                    color: AppColors.subText,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            key: const ValueKey('itemsTrackerCards'),
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                            itemCount: entries.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final entry = entries[index];
                              if (entry.key is String) {
                                return _productRow(context, entry.value.single);
                              }
                              final company = entry.value.first.company.trim();
                              final fullGroup = allRecords
                                  .where(
                                    (item) =>
                                        item.canGroupByCompany &&
                                        _groupKey(item) ==
                                            _groupKey(entry.value.first),
                                  )
                                  .toList();
                              return _companyGroup(
                                context,
                                company,
                                entry.value,
                                fullGroup,
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _columnHeader() => Container(
    height: 47,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: const BoxDecoration(
      color: Color(0xffeaf1f7),
      border: Border(bottom: BorderSide(color: _border)),
    ),
    child: Row(
      children: [
        for (var i = 0; i < _flex.length; i++)
          Expanded(
            flex: _flex[i],
            child: Container(
              decoration: BoxDecoration(
                border: i == _flex.length - 1
                    ? null
                    : const Border(right: BorderSide(color: Color(0xffd7e2eb))),
              ),
              child: Builder(
                builder: (anchor) {
                  final column = ItemsTrackerColumn.values[i];
                  final active = columnFilters.containsKey(column);
                  return Tooltip(
                    message:
                        'Filter ${column.label.toLowerCase()}${active ? ' · active' : ''}',
                    child: Material(
                      color: active
                          ? AppColors.primaryColor.withValues(alpha: .12)
                          : Colors.transparent,
                      child: InkWell(
                        key: ValueKey('columnFilter:${column.name}'),
                        onTap: () => onColumnFilter(anchor, column),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 10,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(
                                  column.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xff456075),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: .3,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 5),
                              Icon(
                                active
                                    ? Icons.filter_alt_rounded
                                    : Icons.filter_list_rounded,
                                size: 14,
                                color: active
                                    ? AppColors.primaryColor
                                    : const Color(0xff748494),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        const SizedBox(width: 158),
      ],
    ),
  );

  Widget _companyGroup(
    BuildContext context,
    String company,
    List<ItemsTrackerRecord> visible,
    List<ItemsTrackerRecord> fullGroup,
  ) {
    final followUpRole = ItemsTrackerRoles.normalize(
      fullGroup.first.followUpRole,
    );
    final groupIdentity = '${company.toLowerCase()}:$followUpRole';
    final teamColor = _teamColor(followUpRole);
    return Material(
      key: ValueKey('company:$groupIdentity'),
      color: const Color(0xfff2f7fc),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xffdce7f1)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey('companyExpanded:$groupIdentity'),
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xffe0edf9),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.business_rounded,
            size: 19,
            color: Color(0xff346990),
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                company,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: teamColor.withValues(alpha: .09),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                ItemsTrackerRoles.label(followUpRole),
                style: TextStyle(
                  color: teamColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                visible.length == fullGroup.length
                    ? '${fullGroup.length} products'
                    : '${visible.length} of ${fullGroup.length} products',
                style: const TextStyle(
                  color: Color(0xff50738d),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (ItemsTrackerRoles.canEditInventoryFields(role))
              fullGroup.every((item) => item.emailSent)
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        'Email sent ✓',
                        style: TextStyle(
                          color: Color(0xff199b69),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    )
                  : TextButton.icon(
                      key: ValueKey('companyEmail:$groupIdentity'),
                      onPressed: () => onCompanyEmail(company, followUpRole),
                      icon: Icon(
                        fullGroup.any((item) => item.emailStatus == 'draft')
                            ? Icons.drafts_outlined
                            : Icons.outgoing_mail,
                        size: 17,
                      ),
                      label: Text(
                        fullGroup.any((item) => item.emailStatus == 'draft')
                            ? 'Email draft'
                            : fullGroup.any((item) => item.emailSent)
                            ? 'Email remaining'
                            : 'Email company',
                      ),
                      style: TextButton.styleFrom(foregroundColor: _accent),
                    ),
            if (fullGroup.any((item) => item.canAct(role)))
              TextButton.icon(
                key: ValueKey('companyAction:$groupIdentity'),
                onPressed: () => onCompanyAction(company, followUpRole),
                icon: const Icon(Icons.add_task_rounded, size: 16),
                label: const Text('Company action'),
                style: TextButton.styleFrom(foregroundColor: _accent),
              ),
            const SizedBox(width: 12),
            const Icon(Icons.unfold_more_rounded, size: 19, color: _muted),
          ],
        ),
        children: [
          for (final record in visible) ...[
            _productRow(context, record),
            if (record != visible.last) const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  String _actor(ItemsTrackerRecord record) {
    if (record.displayedLastActivity.isEmpty || _isInitialActivity(record)) {
      return '—';
    }
    if (record.displayedLastActivityByName.isNotEmpty) {
      return record.displayedLastActivityByName;
    }
    if (record.displayedLastActivityRole.isNotEmpty) {
      return ItemsTrackerRoles.label(record.displayedLastActivityRole);
    }
    return '—';
  }

  String _commentActor(ItemsTrackerRecord record) {
    if (record.latestComment.trim().isEmpty) return '—';
    if (record.commentByName.trim().isNotEmpty) return record.commentByName;
    if (record.commentByRole.trim().isNotEmpty) {
      return ItemsTrackerRoles.label(record.commentByRole);
    }
    return '—';
  }

  Widget _cell(int index, Widget child) => Expanded(
    flex: _flex[index],
    child: Container(
      decoration: BoxDecoration(
        border: index == _flex.length - 1
            ? null
            : const Border(right: BorderSide(color: Color(0xffe3eaf0))),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        child: child,
      ),
    ),
  );

  Widget _text(
    String value, {
    bool subdued = false,
    bool numeric = false,
    bool bold = false,
    TextAlign? textAlign,
  }) => Tooltip(
    message: value,
    child: Text(
      value.isEmpty ? '—' : value,
      maxLines: 4,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign ?? (numeric ? TextAlign.right : TextAlign.left),
      style: TextStyle(
        color: subdued ? _muted : _ink,
        height: 1.55,
        fontSize: 12.5,
        fontWeight: numeric || bold ? FontWeight.w700 : FontWeight.w500,
      ),
    ),
  );

  Widget _productRow(BuildContext context, ItemsTrackerRecord record) {
    final teamColor = _teamColor(record.followUpRole);
    final statusColor = record.caseStatus == ItemsTrackerCaseStatuses.done
        ? const Color(0xff199b69)
        : const Color(0xffee9828);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080c3048),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xffd6e2eb)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('itemCard:${record.id}'),
          onTap: () => _showDetails(context, record),
          hoverColor: const Color(0xfff3f9fc),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 110),
            child: Row(
              children: [
                _cell(
                  0,
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Tooltip(
                        message: ItemsTrackerCaseStatuses.label(
                          record.caseStatus,
                        ),
                        child: Container(
                          key: ValueKey('statusIndicator:${record.id}'),
                          width: 4,
                          height: 38,
                          margin: const EdgeInsets.only(right: 10),
                          decoration: BoxDecoration(
                            color: statusColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          record.itemName,
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 14,
                            height: 1.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _cell(
                  1,
                  _text(
                    record.unitCost == null
                        ? '—'
                        : 'AED ${NumberFormat('#,##0.00').format(record.unitCost)}',
                    numeric: true,
                    textAlign: TextAlign.center,
                  ),
                ),
                _cell(
                  2,
                  Align(
                    alignment: Alignment.center,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xffedf3f8),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _text(
                        NumberFormat('#,##0.##').format(record.requiredQty),
                        numeric: true,
                      ),
                    ),
                  ),
                ),
                _cell(
                  3,
                  _noteBlock(
                    record.inventoryNote.isEmpty
                        ? 'No reason added'
                        : record.inventoryNote,
                    label: 'Inventory reason',
                    icon: Icons.notes_rounded,
                    background: const Color(0xfffff8ea),
                    foreground: const Color(0xff946724),
                  ),
                ),
                _cell(
                  4,
                  _noteBlock(
                    record.displayedLastActivity.isEmpty ||
                            _isInitialActivity(record)
                        ? 'Awaiting first action'
                        : record.displayedLastActivity,
                    label:
                        record.displayedLastActivity.isEmpty ||
                            _isInitialActivity(record)
                        ? 'No action yet'
                        : record.displayedLastActivityType == 'follow_up'
                        ? 'Latest follow-up'
                        : 'Latest action',
                    icon: Icons.bolt_rounded,
                    background: const Color(0xffeff6ff),
                    foreground: const Color(0xff3569a4),
                  ),
                ),
                _cell(
                  5,
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 3, right: 6),
                        child: Icon(
                          Icons.person_outline_rounded,
                          size: 15,
                          color: _muted,
                        ),
                      ),
                      Expanded(
                        child: _text(
                          _actor(record),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
                _cell(
                  6,
                  _noteBlock(
                    record.latestComment.isEmpty
                        ? 'No comment yet'
                        : record.latestComment,
                    label: record.latestComment.isEmpty
                        ? 'No comments'
                        : record.commentCount > 1
                        ? '${record.commentCount} comments · Latest'
                        : 'Latest comment',
                    icon: Icons.chat_bubble_outline_rounded,
                    background: const Color(0xfff7f2fb),
                    foreground: const Color(0xff76548e),
                  ),
                ),
                _cell(
                  7,
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 3, right: 6),
                        child: Icon(
                          Icons.person_outline_rounded,
                          size: 15,
                          color: _muted,
                        ),
                      ),
                      Expanded(
                        child: _text(
                          _commentActor(record),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
                _cell(8, _followUpBadge(record, teamColor)),
                SizedBox(
                  width: 158,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (record.canAct(role))
                        IconButton(
                          key: ValueKey('productAction:${record.id}'),
                          tooltip: 'Add product action',
                          icon: const Icon(
                            Icons.add_task_rounded,
                            size: 19,
                            color: _accent,
                          ),
                          onPressed: () => onAction(record),
                        )
                      else
                        const SizedBox(width: 40),
                      if (ItemsTrackerRoles.canEditInventoryFields(role))
                        record.emailSent
                            ? Tooltip(
                                message:
                                    'Email sent${record.emailScope == 'company' ? ' as part of a company email' : ''} · confirmed in the system${record.emailSentAt == null ? '' : '\n${DateFormat('dd MMM yyyy, HH:mm').format(record.emailSentAt!.toLocal())}'}',
                                child: const SizedBox(
                                  width: 40,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.mark_email_read_outlined,
                                        size: 19,
                                        color: Color(0xff199b69),
                                      ),
                                      Text(
                                        'Sent',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xff199b69),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : IconButton(
                                key: ValueKey('productEmail:${record.id}'),
                                tooltip: record.emailStatus == 'draft'
                                    ? 'Email draft · confirm sent in Outlook'
                                    : 'Send product email with Outlook',
                                icon: Icon(
                                  record.emailStatus == 'draft'
                                      ? Icons.drafts_outlined
                                      : Icons.outgoing_mail,
                                  size: 19,
                                  color: record.emailStatus == 'draft'
                                      ? const Color(0xffb37717)
                                      : _accent,
                                ),
                                onPressed: () => onEmail(record),
                              )
                      else
                        const SizedBox(width: 40),
                      Expanded(
                        child: TextButton(
                          onPressed: () => _showDetails(context, record),
                          style: TextButton.styleFrom(
                            foregroundColor: _accent,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'Details',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _isInitialActivity(ItemsTrackerRecord record) => RegExp(
    r'^Follow-up:\s*Created\s*->\s*$',
    caseSensitive: false,
  ).hasMatch(record.displayedLastActivity);

  Color _teamColor(String role) => switch (ItemsTrackerRoles.normalize(role)) {
    ItemsTrackerRoles.inventory => const Color(0xff13877c),
    ItemsTrackerRoles.purchase => const Color(0xff346ca9),
    ItemsTrackerRoles.category => const Color(0xff8555ad),
    _ => _muted,
  };

  Widget _followUpBadge(ItemsTrackerRecord record, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.center,
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        key: ValueKey('followUpBy:${record.id}'),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: .18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.groups_outlined, size: 15, color: color),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                ItemsTrackerRoles.label(record.followUpRole),
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 7),
      Text(
        record.canAct(role) ? 'Your team' : 'Assigned team',
        textAlign: TextAlign.center,
        style: const TextStyle(color: _muted, fontSize: 10.5),
      ),
    ],
  );

  Widget _noteBlock(
    String body, {
    required String label,
    required IconData icon,
    required Color background,
    required Color foreground,
  }) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(9),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, color: foreground, size: 14),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        _text(body, bold: true),
      ],
    ),
  );

  void _showDetails(BuildContext context, ItemsTrackerRecord record) {
    final theme = Theme.of(context);
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close product details',
      barrierColor: const Color(0x330d2336),
      transitionDuration: const Duration(milliseconds: 240),
      transitionBuilder: (_, animation, _, child) => SlideTransition(
        position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        child: child,
      ),
      pageBuilder: (panelContext, _, _) => Theme(
        data: theme,
        child: Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: math.min(480, MediaQuery.sizeOf(panelContext).width),
            height: double.infinity,
            child: Material(
              key: ValueKey('itemDetailsPanel:${record.id}'),
              color: Colors.white,
              elevation: 16,
              shadowColor: const Color(0x330d2336),
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(20),
              ),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 14, 10),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'PRODUCT DETAILS',
                              style: TextStyle(
                                color: _accent,
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close details',
                            onPressed: () => Navigator.pop(panelContext),
                            icon: const Icon(Icons.close_rounded, size: 21),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                      child: Text(
                        record.itemName,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 21,
                          height: 1.4,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const Divider(height: 1, color: _border),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _section('CATALOG'),
                            _detail('Item code', record.itemCode),
                            _detail('Company', record.company),
                            _detail('Supplier', record.supplier),
                            _detail('Category', record.category),
                            _detail('Source status', record.sourceItemStatus),
                            _detail(
                              'Retail price',
                              record.retailSnapshot == null
                                  ? '—'
                                  : 'AED ${NumberFormat('#,##0.00').format(record.retailSnapshot)}',
                            ),
                            const SizedBox(height: 24),
                            _section('TRACKING'),
                            _detail(
                              'Escalated date',
                              DateFormat.yMMMd().format(record.escalatedDate),
                            ),
                            _detail(
                              'Required value',
                              record.requiredValue == null
                                  ? '—'
                                  : 'AED ${NumberFormat('#,##0.00').format(record.requiredValue)}',
                            ),
                            _detail(
                              'Follow-up team',
                              ItemsTrackerRoles.label(record.followUpRole),
                            ),
                            _detail(
                              'Email status',
                              record.emailSent
                                  ? 'Sent · confirmed in the system${record.emailScope == 'company' ? ' · company email' : ''}'
                                  : record.emailStatus == 'draft'
                                  ? 'Outlook draft · awaiting confirmation'
                                  : 'Not sent',
                            ),
                            if (record.emailSentAt != null)
                              _detail(
                                'Email confirmed at',
                                DateFormat(
                                  'dd MMM yyyy, HH:mm',
                                ).format(record.emailSentAt!.toLocal()),
                              ),
                            _detail(
                              'Tracker status',
                              ItemsTrackerCaseStatuses.label(record.caseStatus),
                            ),
                            _detail(
                              'Status updated to',
                              record.statusUpdatedTo,
                            ),
                            _detail(
                              'Action date',
                              record.displayedLastActivityDate == null
                                  ? '—'
                                  : DateFormat.yMMMd().format(
                                      record.displayedLastActivityDate!,
                                    ),
                            ),
                            const SizedBox(height: 24),
                            _section('COMMENTS'),
                            _detail('Latest comment', record.latestComment),
                            _detail(
                              'Comment by',
                              record.commentByName.isNotEmpty
                                  ? record.commentByName
                                  : record.commentByRole.isEmpty
                                  ? '—'
                                  : ItemsTrackerRoles.label(
                                      record.commentByRole,
                                    ),
                            ),
                            _detail('Comments', '${record.commentCount}'),
                            if (record.canEditInventoryFields(role)) ...[
                              const SizedBox(height: 24),
                              _section('UPDATE STATUS'),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                isExpanded: true,
                                initialValue:
                                    statusOptions.contains(
                                      record.statusUpdatedTo,
                                    )
                                    ? record.statusUpdatedTo
                                    : null,
                                decoration: const InputDecoration(
                                  labelText: 'Status updated to',
                                ),
                                items: statusOptions
                                    .map(
                                      (status) => DropdownMenuItem(
                                        value: status,
                                        child: Text(
                                          status,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (status) {
                                  if (status == null ||
                                      status == record.statusUpdatedTo) {
                                    return;
                                  }
                                  Navigator.pop(panelContext);
                                  onStatusUpdatedToChanged(record, status);
                                },
                              ),
                              const SizedBox(height: 16),
                              DropdownButtonFormField<String>(
                                initialValue: record.caseStatus,
                                decoration: const InputDecoration(
                                  labelText: 'Tracker status',
                                ),
                                items: ItemsTrackerCaseStatuses.values
                                    .map(
                                      (status) => DropdownMenuItem(
                                        value: status,
                                        child: Text(
                                          ItemsTrackerCaseStatuses.label(
                                            status,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (status) {
                                  if (status == null ||
                                      status == record.caseStatus) {
                                    return;
                                  }
                                  Navigator.pop(panelContext);
                                  onTrackerStatusChanged(record, status);
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 1, color: _border),
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (record.canAct(role))
                            FilledButton.icon(
                              onPressed: () {
                                Navigator.pop(panelContext);
                                onAction(record);
                              },
                              icon: const Icon(
                                Icons.add_task_rounded,
                                size: 18,
                              ),
                              label: const Text('Add action'),
                            ),
                          if (record.canEditInventoryFields(role))
                            OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(panelContext);
                                onEditInventory(record);
                              },
                              icon: const Icon(Icons.edit_outlined, size: 17),
                              label: const Text('Edit'),
                            ),
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(panelContext);
                              onHistory(record);
                            },
                            icon: const Icon(Icons.history_rounded, size: 17),
                            label: const Text('Timeline'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(panelContext);
                              onComment(record);
                            },
                            icon: const Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 17,
                            ),
                            label: const Text('Comments'),
                          ),
                          if (record.displayedLastActivityHasAttachment)
                            OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(panelContext);
                                onAttachment(record);
                              },
                              icon: const Icon(
                                Icons.attach_file_rounded,
                                size: 17,
                              ),
                              label: const Text('Attachment'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(String title) => Text(
    title,
    style: const TextStyle(
      color: _accent,
      fontSize: 10.5,
      fontWeight: FontWeight.w800,
      letterSpacing: 1,
    ),
  );

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 128,
          child: Text(
            label,
            style: const TextStyle(color: _muted, fontSize: 12, height: 1.5),
          ),
        ),
        Expanded(
          child: SelectableText(
            value.trim().isEmpty ? '—' : value,
            style: const TextStyle(
              color: _ink,
              fontSize: 12.5,
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}
