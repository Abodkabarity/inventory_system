import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

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
    final selected = await showItemsTrackerDatePicker(
      context: context,
      initialDate: _escalatedDate,
    );

    if (selected != null && mounted) {
      setState(() => _escalatedDate = selected);
    }
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
              accent: AppColors.white,
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
                          border: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: AppColors.primaryColor,
                            ),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: AppColors.primaryColor,
                            ),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: AppColors.primaryColor,
                            ),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          filled: true,
                          fillColor: AppColors.backgroundWidget,
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _searching
                              ? const Padding(
                                  padding: EdgeInsets.all(13),
                                  child: SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.primaryColor,
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
                    const SizedBox(height: 16),
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
                            decoration: InputDecoration(
                              labelText: 'Item cost',
                              prefixText: 'AED  ',
                              helperText: 'Manual purchase cost',
                              border: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: AppColors.primaryColor,
                                ),
                                borderRadius: BorderRadius.circular(15),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: AppColors.primaryColor,
                                ),
                                borderRadius: BorderRadius.circular(15),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: AppColors.primaryColor,
                                ),
                                borderRadius: BorderRadius.circular(15),
                              ),
                              filled: true,
                              fillColor: AppColors.backgroundWidget,
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
                            decoration: InputDecoration(
                              labelText: 'Qty required action *',
                              border: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: AppColors.primaryColor,
                                ),
                                borderRadius: BorderRadius.circular(15),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: AppColors.primaryColor,
                                ),
                                borderRadius: BorderRadius.circular(15),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: AppColors.primaryColor,
                                ),
                                borderRadius: BorderRadius.circular(15),
                              ),
                              filled: true,
                              fillColor: AppColors.backgroundWidget,
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
                            decoration: InputDecoration(
                              labelText: 'Status Updated To *',
                              border: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: AppColors.primaryColor,
                                ),
                                borderRadius: BorderRadius.circular(15),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: AppColors.primaryColor,
                                ),
                                borderRadius: BorderRadius.circular(15),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: AppColors.primaryColor,
                                ),
                                borderRadius: BorderRadius.circular(15),
                              ),
                              filled: true,
                              fillColor: AppColors.backgroundWidget,
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
                            decoration: InputDecoration(
                              labelText: 'To Follow Up By *',
                              border: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: AppColors.primaryColor,
                                ),
                                borderRadius: BorderRadius.circular(15),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: AppColors.primaryColor,
                                ),
                                borderRadius: BorderRadius.circular(15),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: AppColors.primaryColor,
                                ),
                                borderRadius: BorderRadius.circular(15),
                              ),
                              filled: true,
                              fillColor: AppColors.backgroundWidget,
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

                    const SizedBox(height: 16),
                    TextField(
                      key: const ValueKey('itemsTrackerInventoryNote'),
                      controller: _note,
                      minLines: 3,
                      maxLines: 5,
                      decoration: InputDecoration(
                        labelText: 'Notes & reason',
                        alignLabelWithHint: true,
                        hintText: 'Why does this item require action?',
                        border: OutlineInputBorder(
                          borderSide: BorderSide(color: AppColors.primaryColor),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: AppColors.primaryColor),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: AppColors.primaryColor),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        filled: true,
                        fillColor: AppColors.backgroundWidget,
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
  bool _activitySaved = false;
  ItemsTrackerUploadFile? _attachment;
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
    final selected = await showItemsTrackerDatePicker(
      context: context,
      initialDate: _date,
    );

    if (selected != null && mounted) {
      setState(() => _date = selected);
    }
  }

  Future<void> _pickAttachment() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      allowMultiple: false,
      withData: true,
    );
    if (result == null || !mounted) return;

    final selected = result.files.single;
    final bytes = selected.bytes;
    if (bytes == null) {
      setState(() => _error = 'The selected file could not be read.');
      return;
    }
    if (bytes.isEmpty || bytes.length > 15 * 1024 * 1024) {
      setState(() => _error = 'Files must be between 1 byte and 15 MB.');
      return;
    }
    final extension = (selected.extension ?? '').toLowerCase();
    final mimeType = switch (extension) {
      'pdf' => 'application/pdf',
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => '',
    };
    if (mimeType.isEmpty) {
      setState(
        () => _error = 'Only PDF, JPG, PNG, and WEBP files are allowed.',
      );
      return;
    }
    setState(() {
      _attachment = ItemsTrackerUploadFile(
        name: selected.name,
        mimeType: mimeType,
        bytes: bytes,
      );
      _error = null;
    });
  }

  Future<void> _save() async {
    final body = _body.text.trim();
    if (!_activitySaved && body.isEmpty) {
      setState(() => _error = 'Write a clear action or follow-up note.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (!_activitySaved) {
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
        _activitySaved = true;
      }
      if (_attachment != null) {
        await widget.repository.uploadAttachment(
          itemId: widget.record.id,
          file: _attachment!,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _activitySaved
            ? 'The activity was saved, but the file upload failed. '
                  'Your activity will not be duplicated; click Retry upload.\n'
                  '${_friendlyError(error)}'
            : _friendlyError(error);
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

                      style: SegmentedButton.styleFrom(
                        backgroundColor: Colors.white,

                        selectedBackgroundColor: const Color(0xffdff3f1),

                        foregroundColor: const Color(0xff425966),

                        selectedForegroundColor: const Color(0xff08746f),

                        side: const BorderSide(
                          color: Color(0xff9fb5bd),
                          width: 1,
                        ),

                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),

                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),

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
                          ? (values) {
                              setState(() => _mode = values.first);
                            }
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
                        fillColor: AppColors.backgroundWidget,
                        filled: true,
                        border: OutlineInputBorder(
                          borderSide: BorderSide(color: AppColors.primaryColor),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: AppColors.primaryColor),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: AppColors.primaryColor),
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _AttachmentPickerCard(
                      file: _attachment,
                      enabled: ownsItem && !_saving,
                      onPick: _pickAttachment,
                      onRemove: () => setState(() => _attachment = null),
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
              saveLabel: _activitySaved
                  ? _attachment == null
                        ? 'Done'
                        : 'Retry file upload'
                  : _mode == 'action'
                  ? 'Save action'
                  : 'Save follow-up',
              onCancel: _saving
                  ? null
                  : () => Navigator.pop(context, _activitySaved),
              onSave: !_saving && ownsItem ? _save : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentPickerCard extends StatelessWidget {
  final ItemsTrackerUploadFile? file;
  final bool enabled;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  const _AttachmentPickerCard({
    required this.file,
    required this.enabled,
    required this.onPick,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final selected = file;
    final isPdf = selected?.mimeType == 'application/pdf';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: selected == null
            ? const Color(0xfff7fafc)
            : const Color(0xffeef9f7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected == null
              ? const Color(0xffd7e3e8)
              : const Color(0xff9dd8cf),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: selected == null
                  ? Colors.white
                  : isPdf
                  ? const Color(0xffffecec)
                  : const Color(0xffe5f4ff),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              selected == null
                  ? Icons.cloud_upload_outlined
                  : isPdf
                  ? Icons.picture_as_pdf_outlined
                  : Icons.image_outlined,
              color: selected == null
                  ? const Color(0xff55727f)
                  : isPdf
                  ? const Color(0xffc84343)
                  : const Color(0xff287bac),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selected?.name ?? 'Add supporting document',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  selected == null
                      ? 'Private PDF or image · Maximum 15 MB'
                      : '${_formatFileSize(selected.size)} · Saved securely in the item history',
                  style: const TextStyle(
                    color: AppColors.subText,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          if (selected != null)
            IconButton(
              tooltip: 'Remove file',
              onPressed: enabled ? onRemove : null,
              icon: const Icon(Icons.close_rounded),
            ),
          OutlinedButton.icon(
            onPressed: enabled ? onPick : null,
            icon: Icon(
              selected == null ? Icons.attach_file_rounded : Icons.swap_horiz,
              size: 18,
            ),
            label: Text(selected == null ? 'Choose file' : 'Replace'),
          ),
        ],
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
  String? _openingAttachmentId;

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

  Future<void> _openAttachment(ItemsTrackerTimelineEntry entry) async {
    if (!entry.hasAttachment || _openingAttachmentId != null) return;
    setState(() => _openingAttachmentId = entry.attachmentId);
    try {
      final url = await widget.repository.createAttachmentDownloadUrl(
        entry.storagePath,
      );
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw Exception('Could not open the downloaded file.');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_friendlyError(error))));
      }
    } finally {
      if (mounted) setState(() => _openingAttachmentId = null);
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
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primaryColor,
                      ),
                    );
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
                        openingAttachment:
                            _openingAttachmentId == entry.attachmentId,
                        onOpenAttachment: entry.hasAttachment
                            ? () => _openAttachment(entry)
                            : null,
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
              accent: AppColors.primaryColor,
            ),
            _RecordSummary(record: widget.record),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<List<ItemsTrackerTimelineEntry>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primaryColor,
                      ),
                    );
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
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.backgroundWidget,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          ItemsTrackerRoles.label(widget.role),
                          style: const TextStyle(
                            color: AppColors.secondaryColor,
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
                          decoration: InputDecoration(
                            hintText: 'Add a comment visible to all teams…',
                            filled: true,
                            fillColor: AppColors.backgroundWidget,
                            border: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: AppColors.primaryColor,
                              ),
                              borderRadius: BorderRadius.circular(15),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: AppColors.primaryColor,
                              ),
                              borderRadius: BorderRadius.circular(15),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: AppColors.primaryColor,
                              ),
                              borderRadius: BorderRadius.circular(15),
                            ),
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
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primaryColor,
                        ),
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
  final bool openingAttachment;
  final VoidCallback? onOpenAttachment;

  const _TimelineTile({
    required this.entry,
    required this.isLast,
    this.openingAttachment = false,
    this.onOpenAttachment,
  });

  @override
  Widget build(BuildContext context) {
    final color = _entryColor(entry);
    final fromRole = ItemsTrackerRoles.normalize(entry.fromRole);
    final toRole = ItemsTrackerRoles.normalize(entry.toRole);
    final showRoleTransition =
        ItemsTrackerRoles.isAllowed(fromRole) &&
        ItemsTrackerRoles.isAllowed(toRole) &&
        fromRole != toRole;

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
                    if (entry.hasAttachment) ...[
                      const SizedBox(height: 12),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: openingAttachment ? null : onOpenAttachment,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 11,
                            ),
                            decoration: BoxDecoration(
                              color: entry.isImageAttachment
                                  ? const Color(0xffedf7ff)
                                  : const Color(0xfffff1f1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: entry.isImageAttachment
                                    ? const Color(0xffc8e5f5)
                                    : const Color(0xffffd2d2),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  entry.isImageAttachment
                                      ? Icons.image_outlined
                                      : Icons.picture_as_pdf_outlined,
                                  color: entry.isImageAttachment
                                      ? const Color(0xff287bac)
                                      : const Color(0xffc84343),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        entry.fileName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      Text(
                                        '${_formatFileSize(entry.fileSize ?? 0)} · Open secure file',
                                        style: const TextStyle(
                                          color: AppColors.subText,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (openingAttachment)
                                  const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                else
                                  const Icon(
                                    Icons.download_rounded,
                                    color: Color(0xff52707d),
                                  ),
                              ],
                            ),
                          ),
                        ),
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
                          emphasized: true,
                        ),
                        if (entry.actorName.trim().isNotEmpty)
                          _MiniTag(
                            icon: Icons.person_outline_rounded,
                            text: entry.actorName.trim(),
                            emphasized: true,
                          ),
                        if (entry.actionDate != null)
                          _MiniTag(
                            icon: Icons.event_outlined,
                            text: DateFormat(
                              'dd MMM yyyy',
                            ).format(entry.actionDate!),
                          ),
                        if (showRoleTransition)
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
        color: AppColors.backgroundWidget,
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
                color: AppColors.primaryColor,
                size: 18,
              ),
              const SizedBox(width: 7),
              Text(
                [
                  ItemsTrackerRoles.label(entry.actorRole),
                  if (entry.actorName.trim().isNotEmpty) entry.actorName.trim(),
                ].join(' · '),
                style: const TextStyle(
                  color: AppColors.primaryColor,
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
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          SelectableText(
            entry.body,
            style: const TextStyle(height: 1.45, fontWeight: FontWeight.bold),
          ),
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
          TextButton(
            onPressed: onCancel,
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.secondaryColor),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            key: const ValueKey('itemsTrackerDialogSave'),
            onPressed: onSave,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
            ),
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
          filled: true,
          fillColor: AppColors.backgroundWidget,
          suffixIcon: const Icon(Icons.calendar_month_outlined),
          enabled: onTap != null,
          border: OutlineInputBorder(
            borderSide: BorderSide(color: AppColors.primaryColor),
            borderRadius: BorderRadius.circular(15),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: AppColors.primaryColor),
            borderRadius: BorderRadius.circular(15),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: AppColors.primaryColor),
            borderRadius: BorderRadius.circular(15),
          ),
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
      decoration: InputDecoration(
        labelText: 'Value required action',
        prefixIcon: Icon(Icons.calculate_outlined),
        border: OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.primaryColor),
          borderRadius: BorderRadius.circular(15),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.primaryColor),
          borderRadius: BorderRadius.circular(15),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.primaryColor),
          borderRadius: BorderRadius.circular(15),
        ),
        filled: true,
        fillColor: AppColors.backgroundWidget,
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
  final bool emphasized;

  const _MiniTag({
    required this.icon,
    required this.text,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: emphasized ? const Color(0xffe8f4f7) : const Color(0xfff4f7f9),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: emphasized ? const Color(0xffbddce3) : const Color(0xffd7e2e7),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0a173a47),
            blurRadius: 5,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: emphasized ? const Color(0xff256577) : AppColors.subText,
          ),
          const SizedBox(width: 7),
          Text(
            text,
            style: TextStyle(
              color: emphasized
                  ? const Color(0xff214d5b)
                  : const Color(0xff526b76),
              fontSize: 11,
              fontWeight: emphasized ? FontWeight.w900 : FontWeight.w800,
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
    'file_uploaded' => Icons.attach_file_rounded,
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
    'file_uploaded' => const Color(0xff7650b7),
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
    'file_uploaded' => 'FILE UPLOADED',
    _ => entry.eventType.toUpperCase(),
  };
}

String _formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
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

Future<DateTime?> showItemsTrackerDatePicker({
  required BuildContext context,
  required DateTime initialDate,
}) {
  const primary = Color(0xff08746f);
  const darkText = Color(0xff173247);
  const softText = Color(0xff657985);
  const border = Color(0xffd7e3e8);

  return showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: DateTime(2020),
    lastDate: DateTime(2100),
    helpText: 'SELECT DATE',
    cancelText: 'Cancel',
    confirmText: 'Select',
    barrierColor: Colors.black.withValues(alpha: .52),
    switchToInputEntryModeIcon: const Icon(Icons.edit_calendar_outlined),
    switchToCalendarEntryModeIcon: const Icon(Icons.calendar_month_outlined),
    builder: (context, child) {
      final baseTheme = Theme.of(context);

      final pickerTheme = baseTheme.copyWith(
        useMaterial3: true,
        colorScheme: baseTheme.colorScheme.copyWith(
          primary: primary,
          onPrimary: Colors.white,
          surface: Colors.white,
          onSurface: darkText,
          surfaceContainerHigh: Colors.white,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 22,
          shadowColor: Colors.black.withValues(alpha: .28),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: border),
          ),
        ),
        datePickerTheme: DatePickerThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 22,
          shadowColor: Colors.black.withValues(alpha: .28),

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: border),
          ),

          headerBackgroundColor: primary,
          headerForegroundColor: Colors.white,

          headerHeadlineStyle: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            height: 1.15,
            fontWeight: FontWeight.w800,
          ),

          headerHelpStyle: const TextStyle(
            color: Color(0xffd9f1ee),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: .7,
          ),

          dividerColor: border,

          weekdayStyle: const TextStyle(
            color: softText,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),

          dayStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),

          dayForegroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.disabled)) {
              return const Color(0xffb3bec4);
            }

            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }

            return darkText;
          }),

          dayBackgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.selected)) {
              return primary;
            }

            return Colors.transparent;
          }),

          dayOverlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.hovered)) {
              return primary.withValues(alpha: .10);
            }

            if (states.contains(WidgetState.pressed)) {
              return primary.withValues(alpha: .18);
            }

            return null;
          }),

          dayShape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),

          todayForegroundColor: WidgetStateProperty.resolveWith<Color?>((
            states,
          ) {
            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }

            return primary;
          }),

          todayBackgroundColor: WidgetStateProperty.resolveWith<Color?>((
            states,
          ) {
            if (states.contains(WidgetState.selected)) {
              return primary;
            }

            return const Color(0xffe3f4f1);
          }),

          todayBorder: const BorderSide(color: primary, width: 1.2),

          yearStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),

          yearForegroundColor: WidgetStateProperty.resolveWith<Color?>((
            states,
          ) {
            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }

            return darkText;
          }),

          yearBackgroundColor: WidgetStateProperty.resolveWith<Color?>((
            states,
          ) {
            if (states.contains(WidgetState.selected)) {
              return primary;
            }

            return Colors.transparent;
          }),

          yearShape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),

          cancelButtonStyle: TextButton.styleFrom(
            foregroundColor: softText,
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),

          confirmButtonStyle: TextButton.styleFrom(
            foregroundColor: primary,
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),

          toggleButtonTextStyle: const TextStyle(
            color: primary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),

        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: primary,
            textStyle: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      );

      final mediaQuery = MediaQuery.of(context);

      return MediaQuery(
        data: mediaQuery.copyWith(size: const Size(430, 760)),
        child: Theme(
          data: pickerTheme,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: child!,
            ),
          ),
        ),
      );
    },
  );
}
