import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/uae_date_time_formatter.dart';
import '../../../domain/entities/items_tracker_record.dart';
import '../../../domain/repositories/items_tracker_repository.dart';

Future<bool> showItemsTrackerEditorDialog({
  required BuildContext context,
  required ItemsTrackerRepository repository,
  required List<String> statusOptions,
  ItemsTrackerRecord? record,
}) async {
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ItemsTrackerEditorDialog(
          repository: repository,
          statusOptions: statusOptions,
          record: record,
        ),
      ) ??
      false;
}

Future<bool> showItemsTrackerActivityDialog({
  required BuildContext context,
  required ItemsTrackerRepository repository,
  required ItemsTrackerRecord record,
  required String role,
}) async {
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ItemsTrackerActivityDialog(
          repository: repository,
          record: record,
          role: role,
        ),
      ) ??
      false;
}

Future<void> showItemsTrackerTimelineDialog({
  required BuildContext context,
  required ItemsTrackerRepository repository,
  required ItemsTrackerRecord record,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) =>
        ItemsTrackerTimelineDialog(repository: repository, record: record),
  );
}

Future<bool> showItemsTrackerCommentsDialog({
  required BuildContext context,
  required ItemsTrackerRepository repository,
  required ItemsTrackerRecord record,
  required String role,
}) async {
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ItemsTrackerCommentsDialog(
          repository: repository,
          record: record,
          role: role,
        ),
      ) ??
      false;
}

class ItemsTrackerEditorDialog extends StatefulWidget {
  final ItemsTrackerRepository repository;
  final List<String> statusOptions;
  final ItemsTrackerRecord? record;

  const ItemsTrackerEditorDialog({
    super.key,
    required this.repository,
    required this.statusOptions,
    this.record,
  });

  @override
  State<ItemsTrackerEditorDialog> createState() =>
      _ItemsTrackerEditorDialogState();
}

class _ItemsTrackerEditorDialogState extends State<ItemsTrackerEditorDialog> {
  final _search = TextEditingController();
  final _unitCost = TextEditingController();
  final _quantity = TextEditingController();
  final _note = TextEditingController();
  Timer? _searchDebounce;
  List<ItemsTrackerProduct> _suggestions = const [];
  ItemsTrackerProduct? _product;
  late DateTime _escalatedDate;
  String? _statusUpdatedTo;
  String _followUpRole = ItemsTrackerRoles.category;
  bool _searching = false;
  bool _saving = false;
  int _searchToken = 0;
  String? _error;

  bool get _isEditing => widget.record != null;

  @override
  void initState() {
    super.initState();
    final record = widget.record;
    _escalatedDate = record?.escalatedDate ?? DateTime.now();
    if (record != null) {
      _product = ItemsTrackerProduct(
        itemCode: record.itemCode,
        itemName: record.itemName,
        category: record.category,
        supplier: record.supplier,
        company: record.company,
        itemStatus: record.sourceItemStatus,
        retailPrice: record.retailSnapshot,
      );
      _unitCost.text = record.unitCost?.toString() ?? '';
      _quantity.text = record.requiredQty.toString();
      _note.text = record.inventoryNote;
      _statusUpdatedTo = record.statusUpdatedTo;
      _followUpRole = record.followUpRole;
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    _unitCost.dispose();
    _quantity.dispose();
    _note.dispose();
    super.dispose();
  }

  void _scheduleSearch(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      setState(() {
        _suggestions = const [];
        _searching = false;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 280), () {
      unawaited(_loadSuggestions(query));
    });
  }

  Future<void> _loadSuggestions(String query) async {
    final token = ++_searchToken;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final result = await widget.repository.searchProducts(query);
      if (!mounted || token != _searchToken) return;
      setState(() {
        _suggestions = result;
        _searching = false;
      });
    } catch (error) {
      if (!mounted || token != _searchToken) return;
      setState(() {
        _suggestions = const [];
        _searching = false;
        _error = _friendlyError(error);
      });
    }
  }

  void _selectProduct(ItemsTrackerProduct product) {
    FocusScope.of(context).unfocus();
    final autoFollowUp = ItemsTrackerRoles.defaultFollowUpForCategory(
      product.category,
    );
    setState(() {
      _product = product;
      _search.text = product.searchLabel;
      _suggestions = const [];
      _followUpRole = autoFollowUp;
      if ((_statusUpdatedTo ?? '').isEmpty) {
        _statusUpdatedTo = product.itemStatus;
      }
      _error = null;
    });
  }

  double? get _cost => _parseNumber(_unitCost.text);
  double? get _qty => _parseNumber(_quantity.text);
  double? get _calculatedValue => calculateItemsTrackerValue(_cost, _qty);

  List<String> get _effectiveStatuses {
    final result =
        <String>{
          ...widget.statusOptions.where((value) => value.trim().isNotEmpty),
          if ((_statusUpdatedTo ?? '').trim().isNotEmpty)
            _statusUpdatedTo!.trim(),
          if ((_product?.itemStatus ?? '').trim().isNotEmpty)
            _product!.itemStatus.trim(),
        }.toList(growable: false)..sort(
          (left, right) => left.toLowerCase().compareTo(right.toLowerCase()),
        );
    return result;
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _escalatedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (selected != null) setState(() => _escalatedDate = selected);
  }

  Future<void> _save() async {
    final product = _product;
    final qty = _qty;
    final cost = _cost;
    if (product == null) {
      setState(() => _error = 'Select a valid product from the suggestions.');
      return;
    }
    if (qty == null || qty <= 0) {
      setState(() => _error = 'Required quantity must be greater than zero.');
      return;
    }
    if (cost != null && cost < 0) {
      setState(() => _error = 'Item cost cannot be negative.');
      return;
    }
    if ((_statusUpdatedTo ?? '').trim().isEmpty) {
      setState(() => _error = 'Status Updated To is required.');
      return;
    }
    if (!ItemsTrackerRoles.isAllowed(_followUpRole)) {
      setState(() => _error = 'Choose a valid follow-up department.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final record = widget.record;
      if (record == null) {
        await widget.repository.createRecord(
          CreateItemsTrackerRecord(
            escalatedDate: _escalatedDate,
            itemCode: product.itemCode,
            unitCost: cost,
            inventoryNote: _note.text,
            requiredQty: qty,
            statusUpdatedTo: _statusUpdatedTo!,
            followUpRole: _followUpRole,
          ),
        );
      } else {
        await widget.repository.updateInventoryFields(
          UpdateItemsTrackerRecord(
            itemId: record.id,
            escalatedDate: _escalatedDate,
            unitCost: cost,
            inventoryNote: _note.text,
            requiredQty: qty,
            statusUpdatedTo: _statusUpdatedTo!,
            followUpRole: _followUpRole,
            expectedVersion: record.rowVersion,
          ),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _friendlyError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120, maxHeight: 850),
        child: Column(
          children: [
            _DialogHeader(
              icon: _isEditing
                  ? Icons.edit_note_rounded
                  : Icons.add_box_rounded,
              title: _isEditing ? 'Edit tracked item' : 'Add item to tracker',
              subtitle:
                  'Inventory-owned details • catalog values are filled automatically',
              onClose: _saving ? null : () => Navigator.pop(context),
              accent: const Color(0xffffcf3e),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!_isEditing) ...[
                      const _SectionTitle(
                        icon: Icons.manage_search_rounded,
                        title: 'Find a product',
                        subtitle: 'Search by item code or item name',
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey('itemsTrackerProductSearch'),
                        controller: _search,
                        autofocus: true,
                        onChanged: _scheduleSearch,
                        decoration: InputDecoration(
                          hintText: 'Type at least 2 characters…',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _searching
                              ? const Padding(
                                  padding: EdgeInsets.all(13),
                                  child: SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                      ),
                      if (_suggestions.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 245),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.border),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x16000000),
                                blurRadius: 18,
                                offset: Offset(0, 7),
                              ),
                            ],
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: _suggestions.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final product = _suggestions[index];
                              return ListTile(
                                dense: true,
                                leading: const CircleAvatar(
                                  backgroundColor: Color(0xffe8f5fb),
                                  child: Icon(
                                    Icons.inventory_2_outlined,
                                    color: AppColors.secondaryColor,
                                    size: 19,
                                  ),
                                ),
                                title: Text(
                                  product.itemName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                subtitle: Text(
                                  '${product.itemCode}  •  ${product.category}  •  ${product.supplier}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: const Icon(
                                  Icons.arrow_forward_rounded,
                                ),
                                onTap: () => _selectProduct(product),
                              );
                            },
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                    ],
                    if (_product != null) ...[
                      _SelectedProductCard(product: _product!),
                      const SizedBox(height: 22),
                    ],
                    const _SectionTitle(
                      icon: Icons.assignment_outlined,
                      title: 'Escalation details',
                      subtitle: 'These fields can only be changed by Inventory',
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: [
                        _FieldBox(
                          width: 245,
                          child: _DateField(
                            label: 'Escalated date *',
                            value: _escalatedDate,
                            onTap: _pickDate,
                          ),
                        ),
                        _FieldBox(
                          width: 245,
                          child: TextField(
                            key: const ValueKey('itemsTrackerUnitCost'),
                            controller: _unitCost,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Item cost',
                              prefixText: 'AED  ',
                              helperText: 'Manual purchase cost',
                            ),
                          ),
                        ),
                        _FieldBox(
                          width: 245,
                          child: TextField(
                            key: const ValueKey('itemsTrackerRequiredQty'),
                            controller: _quantity,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Qty required action *',
                            ),
                          ),
                        ),
                        _FieldBox(
                          width: 245,
                          child: _CalculatedValueField(value: _calculatedValue),
                        ),
                        _FieldBox(
                          width: 330,
                          child: DropdownButtonFormField<String>(
                            key: ValueKey(
                              'itemsTrackerStatus-${_statusUpdatedTo ?? ''}',
                            ),
                            initialValue: _statusUpdatedTo,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Status Updated To *',
                            ),
                            items: _effectiveStatuses
                                .map(
                                  (value) => DropdownMenuItem(
                                    value: value,
                                    child: Text(
                                      value,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: (value) =>
                                setState(() => _statusUpdatedTo = value),
                          ),
                        ),
                        _FieldBox(
                          width: 245,
                          child: DropdownButtonFormField<String>(
                            key: ValueKey(
                              'itemsTrackerFollowUp-$_followUpRole',
                            ),
                            initialValue: _followUpRole,
                            decoration: const InputDecoration(
                              labelText: 'To Follow Up By *',
                            ),
                            items: ItemsTrackerRoles.allowed
                                .map(
                                  (value) => DropdownMenuItem(
                                    value: value,
                                    child: Text(ItemsTrackerRoles.label(value)),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _followUpRole = value);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: const Color(0xfffff8d9),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: const Color(0xffffe18a)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            color: Color(0xff9a6c00),
                            size: 19,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              'item_report does not contain purchase cost. Enter the actual item cost manually; retail price is shown above only as a reference and is never used silently.',
                              style: TextStyle(
                                color: Colors.brown.shade800,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const ValueKey('itemsTrackerInventoryNote'),
                      controller: _note,
                      minLines: 3,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'Notes & reason',
                        alignLabelWithHint: true,
                        hintText: 'Why does this item require action?',
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      _ErrorBanner(message: _error!),
                    ],
                  ],
                ),
              ),
            ),
            _DialogFooter(
              saving: _saving,
              saveLabel: _isEditing ? 'Save changes' : 'Add item',
              onCancel: _saving ? null : () => Navigator.pop(context),
              onSave: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}

class ItemsTrackerActivityDialog extends StatefulWidget {
  final ItemsTrackerRepository repository;
  final ItemsTrackerRecord record;
  final String role;

  const ItemsTrackerActivityDialog({
    super.key,
    required this.repository,
    required this.record,
    required this.role,
  });

  @override
  State<ItemsTrackerActivityDialog> createState() =>
      _ItemsTrackerActivityDialogState();
}

class _ItemsTrackerActivityDialogState
    extends State<ItemsTrackerActivityDialog> {
  final _body = TextEditingController();
  String _mode = 'action';
  late DateTime _date;
  late String _caseStatus;
  late String _targetRole;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _date = DateTime.now();
    _caseStatus = widget.record.caseStatus;
    _targetRole = widget.record.followUpRole;
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (selected != null) setState(() => _date = selected);
  }

  Future<void> _save() async {
    final body = _body.text.trim();
    if (body.isEmpty) {
      setState(() => _error = 'Write a clear action or follow-up note.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_mode == 'action') {
        await widget.repository.addAction(
          AddItemsTrackerAction(
            itemId: widget.record.id,
            actionDate: _date,
            body: body,
            caseStatus: _caseStatus,
            expectedVersion: widget.record.rowVersion,
          ),
        );
      } else {
        await widget.repository.changeFollowUp(
          ChangeItemsTrackerFollowUp(
            itemId: widget.record.id,
            targetRole: _targetRole,
            note: body,
            actionDate: _date,
            expectedVersion: widget.record.rowVersion,
          ),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _friendlyError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ownsItem = widget.record.canAct(widget.role);
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DialogHeader(
              icon: Icons.add_task_rounded,
              title: 'Record team activity',
              subtitle: '${widget.record.itemCode} • ${widget.record.itemName}',
              onClose: _saving ? null : () => Navigator.pop(context),
              accent: const Color(0xff63d8e9),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AssignmentBanner(
                      assignedRole: widget.record.followUpRole,
                      currentRole: widget.role,
                    ),
                    const SizedBox(height: 20),
                    SegmentedButton<String>(
                      key: const ValueKey('itemsTrackerActivityMode'),
                      segments: const [
                        ButtonSegment(
                          value: 'action',
                          icon: Icon(Icons.task_alt_rounded),
                          label: Text('Add Action'),
                        ),
                        ButtonSegment(
                          value: 'follow_up',
                          icon: Icon(Icons.redo_rounded),
                          label: Text('Follow Up'),
                        ),
                      ],
                      selected: {_mode},
                      onSelectionChanged: ownsItem
                          ? (values) => setState(() => _mode = values.first)
                          : null,
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: [
                        _FieldBox(
                          width: 260,
                          child: _DateField(
                            label: _mode == 'action'
                                ? 'Action date *'
                                : 'Follow-up date *',
                            value: _date,
                            onTap: ownsItem ? _pickDate : null,
                          ),
                        ),
                        if (_mode == 'action')
                          _FieldBox(
                            width: 300,
                            child: DropdownButtonFormField<String>(
                              initialValue: _caseStatus,
                              decoration: const InputDecoration(
                                labelText: 'Case status *',
                              ),
                              items: ItemsTrackerCaseStatuses.values
                                  .map(
                                    (value) => DropdownMenuItem(
                                      value: value,
                                      child: Text(
                                        ItemsTrackerCaseStatuses.label(value),
                                      ),
                                    ),
                                  )
                                  .toList(growable: false),
                              onChanged: ownsItem
                                  ? (value) {
                                      if (value != null) {
                                        setState(() => _caseStatus = value);
                                      }
                                    }
                                  : null,
                            ),
                          )
                        else
                          _FieldBox(
                            width: 300,
                            child: DropdownButtonFormField<String>(
                              initialValue: _targetRole,
                              decoration: const InputDecoration(
                                labelText: 'Next follow-up department *',
                              ),
                              items: ItemsTrackerRoles.allowed
                                  .map(
                                    (value) => DropdownMenuItem(
                                      value: value,
                                      child: Text(
                                        ItemsTrackerRoles.label(value),
                                      ),
                                    ),
                                  )
                                  .toList(growable: false),
                              onChanged: ownsItem
                                  ? (value) {
                                      if (value != null) {
                                        setState(() => _targetRole = value);
                                      }
                                    }
                                  : null,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const ValueKey('itemsTrackerActivityBody'),
                      controller: _body,
                      enabled: ownsItem,
                      minLines: 5,
                      maxLines: 8,
                      decoration: InputDecoration(
                        labelText: _mode == 'action'
                            ? 'Action plan & note *'
                            : 'Follow-up note *',
                        alignLabelWithHint: true,
                        hintText: _mode == 'action'
                            ? 'What was done, what was agreed, and what happens next?'
                            : 'Why is ownership being followed up or transferred?',
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      _ErrorBanner(message: _error!),
                    ],
                  ],
                ),
              ),
            ),
            _DialogFooter(
              saving: _saving,
              saveLabel: _mode == 'action' ? 'Save action' : 'Save follow-up',
              onCancel: _saving ? null : () => Navigator.pop(context),
              onSave: !_saving && ownsItem ? _save : null,
            ),
          ],
        ),
      ),
    );
  }
}

class ItemsTrackerTimelineDialog extends StatefulWidget {
  final ItemsTrackerRepository repository;
  final ItemsTrackerRecord record;

  const ItemsTrackerTimelineDialog({
    super.key,
    required this.repository,
    required this.record,
  });

  @override
  State<ItemsTrackerTimelineDialog> createState() =>
      _ItemsTrackerTimelineDialogState();
}

class _ItemsTrackerTimelineDialogState
    extends State<ItemsTrackerTimelineDialog> {
  late Future<List<ItemsTrackerTimelineEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.fetchTimeline(widget.record.id);
  }

  void _reload() {
    setState(() {
      _future = widget.repository.fetchTimeline(widget.record.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 820),
        child: Column(
          children: [
            _DialogHeader(
              icon: Icons.history_rounded,
              title: 'Complete activity history',
              subtitle: '${widget.record.itemCode} • ${widget.record.itemName}',
              onClose: () => Navigator.pop(context),
              accent: const Color(0xff63d8e9),
            ),
            _RecordSummary(record: widget.record),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<List<ItemsTrackerTimelineEntry>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _DialogLoadError(
                      message: _friendlyError(snapshot.error!),
                      onRetry: _reload,
                    );
                  }
                  final entries = snapshot.data ?? const [];
                  if (entries.isEmpty) {
                    return const Center(
                      child: Text('No history has been recorded yet.'),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return _TimelineTile(
                        entry: entry,
                        isLast: index == entries.length - 1,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ItemsTrackerCommentsDialog extends StatefulWidget {
  final ItemsTrackerRepository repository;
  final ItemsTrackerRecord record;
  final String role;

  const ItemsTrackerCommentsDialog({
    super.key,
    required this.repository,
    required this.record,
    required this.role,
  });

  @override
  State<ItemsTrackerCommentsDialog> createState() =>
      _ItemsTrackerCommentsDialogState();
}

class _ItemsTrackerCommentsDialogState
    extends State<ItemsTrackerCommentsDialog> {
  final _comment = TextEditingController();
  late Future<List<ItemsTrackerTimelineEntry>> _future;
  bool _saving = false;
  bool _changed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = _loadComments();
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<List<ItemsTrackerTimelineEntry>> _loadComments() async {
    final entries = await widget.repository.fetchTimeline(widget.record.id);
    return entries.where((entry) => entry.isComment).toList(growable: false);
  }

  void _reload() {
    setState(() => _future = _loadComments());
  }

  Future<void> _addComment() async {
    final body = _comment.text.trim();
    if (body.isEmpty) {
      setState(() => _error = 'Write a comment first.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.addComment(itemId: widget.record.id, body: body);
      if (!mounted) return;
      _comment.clear();
      _changed = true;
      setState(() {
        _saving = false;
        _future = _loadComments();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _friendlyError(error);
      });
    }
  }

  void _close() => Navigator.pop(context, _changed);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 800),
        child: Column(
          children: [
            _DialogHeader(
              icon: Icons.forum_outlined,
              title: 'Team comments',
              subtitle:
                  'Open to Inventory, Purchase and Category • comments are permanent',
              onClose: _saving ? null : _close,
              accent: const Color(0xffb994f1),
            ),
            _RecordSummary(record: widget.record),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<List<ItemsTrackerTimelineEntry>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _DialogLoadError(
                      message: _friendlyError(snapshot.error!),
                      onRetry: _reload,
                    );
                  }
                  final comments = snapshot.data ?? const [];
                  if (comments.isEmpty) {
                    return const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 46,
                            color: Color(0xffb5a8c9),
                          ),
                          SizedBox(height: 10),
                          Text(
                            'No comments yet. Start the conversation below.',
                          ),
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    reverse: false,
                    padding: const EdgeInsets.all(24),
                    itemCount: comments.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      return _CommentBubble(entry: comments[index]);
                    },
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 20),
              decoration: const BoxDecoration(
                color: Color(0xfffaf9fc),
                border: Border(top: BorderSide(color: AppColors.border)),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xffeee7f8),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          ItemsTrackerRoles.label(widget.role),
                          style: const TextStyle(
                            color: Color(0xff7650b7),
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('itemsTrackerCommentBody'),
                          controller: _comment,
                          enabled: !_saving,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            hintText: 'Add a comment visible to all teams…',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        key: const ValueKey('itemsTrackerAddComment'),
                        onPressed: _saving ? null : _addComment,
                        icon: _saving
                            ? const SizedBox.square(
                                dimension: 17,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.send_rounded),
                        label: const Text('Send'),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    _ErrorBanner(message: _error!),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedProductCard extends StatelessWidget {
  final ItemsTrackerProduct product;

  const _SelectedProductCard({required this.product});

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,##0.00');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xfff5fbfe), Color(0xfffffbee)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xffd9e8ee)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primaryColor.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.inventory_2_outlined,
                  color: AppColors.secondaryColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.itemName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      product.itemCode,
                      style: const TextStyle(
                        color: AppColors.secondaryColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 9,
            runSpacing: 9,
            children: [
              _InfoPill(label: 'Category', value: product.category),
              _InfoPill(label: 'Supplier', value: product.supplier),
              _InfoPill(label: 'Company', value: product.company),
              _InfoPill(label: 'Item Status', value: product.itemStatus),
              _InfoPill(
                label: 'Retail reference',
                value: product.retailPrice == null
                    ? 'Not available'
                    : 'AED ${money.format(product.retailPrice)}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecordSummary extends StatelessWidget {
  final ItemsTrackerRecord record;

  const _RecordSummary({required this.record});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(26, 16, 26, 16),
      color: const Color(0xfff7fafc),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            record.itemName,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          _InfoPill(label: 'Code', value: record.itemCode),
          _InfoPill(
            label: 'Assigned',
            value: ItemsTrackerRoles.label(record.followUpRole),
          ),
          _InfoPill(
            label: 'Status',
            value: ItemsTrackerCaseStatuses.label(record.caseStatus),
          ),
        ],
      ),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  final ItemsTrackerTimelineEntry entry;
  final bool isLast;

  const _TimelineTile({required this.entry, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final color = _entryColor(entry);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            child: Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .12),
                    shape: BoxShape.circle,
                    border: Border.all(color: color.withValues(alpha: .35)),
                  ),
                  child: Icon(_entryIcon(entry), size: 15, color: color),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: color.withValues(alpha: .2),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: const Color(0xfffafbfd),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          _entryTitle(entry),
                          style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          DateFormat(
                            'dd MMM yyyy, HH:mm',
                          ).format(UaeDateTimeFormatter.toUae(entry.createdAt)),
                          style: const TextStyle(
                            color: AppColors.subText,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                    if (entry.body.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SelectableText(
                        entry.body,
                        style: const TextStyle(height: 1.45),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _MiniTag(
                          icon: Icons.badge_outlined,
                          text: ItemsTrackerRoles.label(entry.actorRole),
                        ),
                        if (entry.actionDate != null)
                          _MiniTag(
                            icon: Icons.event_outlined,
                            text: DateFormat(
                              'dd MMM yyyy',
                            ).format(entry.actionDate!),
                          ),
                        if (entry.toRole.isNotEmpty)
                          _MiniTag(
                            icon: Icons.redo_rounded,
                            text:
                                '${ItemsTrackerRoles.label(entry.fromRole)} → ${ItemsTrackerRoles.label(entry.toRole)}',
                          ),
                        if (entry.toStatus.isNotEmpty)
                          _MiniTag(
                            icon: Icons.flag_outlined,
                            text: ItemsTrackerCaseStatuses.label(
                              entry.toStatus,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentBubble extends StatelessWidget {
  final ItemsTrackerTimelineEntry entry;

  const _CommentBubble({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xfffaf7ff),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xffe8ddf8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_circle_outlined,
                color: Color(0xff7650b7),
                size: 18,
              ),
              const SizedBox(width: 7),
              Text(
                ItemsTrackerRoles.label(entry.actorRole),
                style: const TextStyle(
                  color: Color(0xff7650b7),
                  fontWeight: FontWeight.w900,
                  fontSize: 11.5,
                ),
              ),
              const Spacer(),
              Text(
                DateFormat(
                  'dd MMM yyyy, HH:mm',
                ).format(UaeDateTimeFormatter.toUae(entry.createdAt)),
                style: const TextStyle(
                  color: AppColors.subText,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          SelectableText(entry.body, style: const TextStyle(height: 1.45)),
        ],
      ),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onClose;
  final Color accent;

  const _DialogHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onClose,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(25, 20, 16, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xff102d42), Color(0xff17637a)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xffc4d7e1),
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _DialogFooter extends StatelessWidget {
  final bool saving;
  final String saveLabel;
  final VoidCallback? onCancel;
  final VoidCallback? onSave;

  const _DialogFooter({
    required this.saving,
    required this.saveLabel,
    required this.onCancel,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 15, 24, 18),
      decoration: const BoxDecoration(
        color: Color(0xfff8fafc),
        border: Border(top: BorderSide(color: AppColors.border)),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(onPressed: onCancel, child: const Text('Cancel')),
          const SizedBox(width: 10),
          FilledButton.icon(
            key: const ValueKey('itemsTrackerDialogSave'),
            onPressed: onSave,
            icon: saving
                ? const SizedBox.square(
                    dimension: 17,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(saving ? 'Saving…' : saveLabel),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.primaryColor.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: AppColors.secondaryColor, size: 20),
        ),
        const SizedBox(width: 11),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
            ),
            Text(
              subtitle,
              style: const TextStyle(color: AppColors.subText, fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }
}

class _FieldBox extends StatelessWidget {
  final double width;
  final Widget child;

  const _FieldBox({required this.width, required this.child});

  @override
  Widget build(BuildContext context) => SizedBox(width: width, child: child);
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime value;
  final VoidCallback? onTap;

  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_month_outlined),
          enabled: onTap != null,
        ),
        child: Text(
          DateFormat('dd MMMM yyyy').format(value),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _CalculatedValueField extends StatelessWidget {
  final double? value;

  const _CalculatedValueField({required this.value});

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Value required action',
        prefixIcon: Icon(Icons.calculate_outlined),
      ),
      child: Text(
        value == null
            ? 'Pending item cost'
            : 'AED ${NumberFormat('#,##0.00').format(value)}',
        style: TextStyle(
          color: value == null ? AppColors.subText : const Color(0xff087763),
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String label;
  final String value;

  const _InfoPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .82),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0xffdce6eb)),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                color: AppColors.subText,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: value.trim().isEmpty ? '—' : value,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        style: const TextStyle(fontSize: 11),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MiniTag({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xffeef3f7),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.subText),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              color: AppColors.subText,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AssignmentBanner extends StatelessWidget {
  final String assignedRole;
  final String currentRole;

  const _AssignmentBanner({
    required this.assignedRole,
    required this.currentRole,
  });

  @override
  Widget build(BuildContext context) {
    final owns =
        ItemsTrackerRoles.normalize(assignedRole) ==
        ItemsTrackerRoles.normalize(currentRole);
    final color = owns ? const Color(0xff0f8f78) : const Color(0xff78848e);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: .2)),
      ),
      child: Row(
        children: [
          Icon(
            owns ? Icons.verified_user_outlined : Icons.lock_outline_rounded,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              owns
                  ? 'This item is assigned to ${ItemsTrackerRoles.label(currentRole)}. You can add an action or record a follow-up.'
                  : 'Read-only: this item is currently assigned to ${ItemsTrackerRoles.label(assignedRole)}.',
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xffffeded),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xffffc5c5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xffb63838)),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xff8f2d2d),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DialogLoadError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _DialogLoadError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 44,
              color: AppColors.subText,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _entryIcon(ItemsTrackerTimelineEntry entry) {
  if (entry.isComment) return Icons.mode_comment_outlined;
  return switch (entry.eventType) {
    'created' => Icons.add_circle_outline_rounded,
    'inventory_update' => Icons.edit_note_rounded,
    'action' => Icons.task_alt_rounded,
    'follow_up' => Icons.redo_rounded,
    'status_change' => Icons.flag_outlined,
    _ => Icons.history_rounded,
  };
}

Color _entryColor(ItemsTrackerTimelineEntry entry) {
  if (entry.isComment) return const Color(0xff7650b7);
  return switch (entry.eventType) {
    'created' => const Color(0xffb47b00),
    'inventory_update' => const Color(0xffb47b00),
    'action' => const Color(0xff0f8f78),
    'follow_up' => const Color(0xff087e9b),
    'status_change' => const Color(0xffd4770a),
    _ => AppColors.primaryColor,
  };
}

String _entryTitle(ItemsTrackerTimelineEntry entry) {
  if (entry.isComment) return 'COMMENT';
  return switch (entry.eventType) {
    'created' => 'ITEM CREATED',
    'inventory_update' => 'INVENTORY UPDATE',
    'action' => 'ACTION',
    'follow_up' => 'FOLLOW-UP',
    'status_change' => 'STATUS CHANGE',
    _ => entry.eventType.toUpperCase(),
  };
}

double? _parseNumber(String value) {
  final cleaned = value.trim().replaceAll(',', '');
  if (cleaned.isEmpty) return null;
  return double.tryParse(cleaned);
}

String _friendlyError(Object error) {
  final text = error.toString();
  if (text.contains('ITEM_TRACKER_STALE_VERSION') ||
      text.contains('STALE_ITEM_VERSION')) {
    return 'This item was changed by another user. Close the dialog, refresh, and try again.';
  }
  if (text.contains('ITEM_TRACKER_NOT_ASSIGNED') ||
      text.contains('ITEM_IS_NOT_ASSIGNED_TO_YOUR_ROLE')) {
    return 'This item has already been assigned to another department.';
  }
  if (text.contains('ITEM_TRACKER_INVENTORY_ONLY') ||
      text.contains('INVENTORY_PERMISSION_REQUIRED')) {
    return 'Only Inventory can change these fields.';
  }
  if (text.contains('ITEM_TRACKER_PRODUCT_NOT_FOUND') ||
      text.contains('ITEM_NOT_FOUND_IN_ITEM_REPORT')) {
    return 'The selected product no longer exists in item_report.';
  }
  return text
      .replaceFirst('PostgrestException(message: ', '')
      .replaceFirst('Exception: ', '')
      .split(', code:')
      .first
      .trim();
}
