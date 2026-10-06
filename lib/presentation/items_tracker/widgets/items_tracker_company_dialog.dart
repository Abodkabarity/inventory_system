import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/entities/items_tracker_record.dart';
import '../../../domain/repositories/items_tracker_repository.dart';
import 'items_tracker_dialogs.dart';
import 'items_tracker_email_dialog.dart';

enum ItemsTrackerAddMode { product, company }

Future<ItemsTrackerAddMode?> showItemsTrackerAddMode(BuildContext context) {
  return showDialog<ItemsTrackerAddMode>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 650),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Add to Item Tracker',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose one product or select products from a company.',
                style: TextStyle(color: _muted),
              ),
              const SizedBox(height: 24),
              _ModeTile(
                icon: Icons.inventory_2_outlined,
                title: 'Single product',
                subtitle: 'Search Item Report and add one product.',
                onTap: () =>
                    Navigator.pop(context, ItemsTrackerAddMode.product),
              ),
              const SizedBox(height: 12),
              _ModeTile(
                icon: Icons.business_outlined,
                title: 'Company products',
                subtitle:
                    'Select company products, enter optional costs, and add missing products manually.',
                onTap: () =>
                    Navigator.pop(context, ItemsTrackerAddMode.company),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

const _ink = Color(0xff19354b);
const _muted = Color(0xff71849a);
const _accent = Color(0xff008a96);
const _border = Color(0xffdee7ef);

class _ModeTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ModeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xfff5fafc),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: _border),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xffe1f3f4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: _accent),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    style: const TextStyle(color: _muted, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.arrow_forward_rounded, color: _accent),
          ],
        ),
      ),
    ),
  );
}

Future<bool> showItemsTrackerCompanyDialog({
  required BuildContext context,
  required ItemsTrackerRepository repository,
  required List<String> statusOptions,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ItemsTrackerCompanyDialog(
        repository: repository,
        statusOptions: statusOptions,
      ),
    ) ??
    false;

class ItemsTrackerCompanyDialog extends StatefulWidget {
  final ItemsTrackerRepository repository;
  final List<String> statusOptions;
  const ItemsTrackerCompanyDialog({
    super.key,
    required this.repository,
    required this.statusOptions,
  });

  @override
  State<ItemsTrackerCompanyDialog> createState() =>
      _ItemsTrackerCompanyDialogState();
}

class _CompanyProductDraft {
  final ItemsTrackerProduct product;
  final bool manual;
  final TextEditingController quantity = TextEditingController(text: '1');
  final TextEditingController cost = TextEditingController();
  bool selected = true;
  late String followUp;
  late String status;

  _CompanyProductDraft(
    this.product,
    List<String> statuses, {
    this.manual = false,
  }) {
    followUp = ItemsTrackerRoles.defaultFollowUpForCategory(product.category);
    status = statuses.contains(product.itemStatus)
        ? product.itemStatus
        : (statuses.isEmpty ? '' : statuses.first);
  }

  void dispose() {
    quantity.dispose();
    cost.dispose();
  }
}

class _ItemsTrackerCompanyDialogState extends State<ItemsTrackerCompanyDialog> {
  final _companySearch = TextEditingController();
  final _productSearch = TextEditingController();
  final _reason = TextEditingController();
  final _bulkQuantity = TextEditingController(text: '1');
  final _horizontalScroll = ScrollController();
  final _form = GlobalKey<FormState>();
  final _rows = <_CompanyProductDraft>[];
  List<ItemsTrackerCompany> _companies = [];
  Timer? _debounce;
  int _searchToken = 0;
  String? _company;
  String? _error;
  bool _loading = true;
  bool _saving = false;
  bool _emailOnAdd = false;
  bool _added = false;
  DateTime _date = DateTime.now();
  String _bulkFollowUp = 'auto';
  String _bulkStatus = 'catalog';

  List<String> get _statuses =>
      widget.statusOptions.where((s) => s.trim().isNotEmpty).toSet().toList()
        ..sort();
  List<_CompanyProductDraft> get _selected =>
      _rows.where((r) => r.selected).toList();
  List<_CompanyProductDraft> get _filtered {
    final query = _productSearch.text.trim().toLowerCase();
    return _rows
        .where(
          (r) => '${r.product.itemCode} ${r.product.itemName}'
              .toLowerCase()
              .contains(query),
        )
        .toList();
  }

  @override
  void initState() {
    super.initState();
    unawaited(_searchCompanies(''));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _horizontalScroll.dispose();
    for (final controller in [
      _companySearch,
      _productSearch,
      _reason,
      _bulkQuantity,
    ]) {
      controller.dispose();
    }
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _scheduleSearch(String query) {
    _debounce?.cancel();
    final token = ++_searchToken;
    setState(() {
      _loading = true;
      _error = null;
    });
    _debounce = Timer(
      const Duration(milliseconds: 280),
      () => _searchCompanies(query, token: token),
    );
  }

  Future<void> _searchCompanies(String query, {int? token}) async {
    final request = token ?? ++_searchToken;
    try {
      final result = await widget.repository.searchCompanies(query);
      if (!mounted || request != _searchToken) return;
      setState(() {
        _companies = result;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || request != _searchToken) return;
      setState(() {
        _loading = false;
        _error = 'Could not load companies. ${_errorText(error)}';
      });
    }
  }

  Future<void> _selectCompany(String name) async {
    final cleaned = name.trim();
    if (cleaned.isEmpty || _saving) return;
    _debounce?.cancel();
    ++_searchToken;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final products = await widget.repository.fetchCompanyProducts(cleaned);
      if (!mounted) return;
      for (final row in _rows) {
        row.dispose();
      }
      setState(() {
        _company = cleaned;
        _rows.clear();
        _rows.addAll(products.map((p) => _CompanyProductDraft(p, _statuses)));
        _productSearch.clear();
        _bulkFollowUp = 'auto';
        _bulkStatus = 'catalog';
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load company products. ${_errorText(error)}';
        });
      }
    }
  }

  Future<void> _addManualProduct() async {
    final product = await showDialog<ItemsTrackerProduct>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ManualProductDialog(company: _company!),
    );
    if (!mounted || product == null) return;
    if (product.itemCode.isNotEmpty &&
        _rows.any(
          (r) =>
              r.product.itemCode.toLowerCase() ==
              product.itemCode.toLowerCase(),
        )) {
      setState(
        () => _error =
            'This item code is already in the list. Select the existing product.',
      );
      return;
    }
    setState(() {
      final row = _CompanyProductDraft(product, _statuses, manual: true);
      if (_bulkFollowUp != 'auto') row.followUp = _bulkFollowUp;
      if (_bulkStatus != 'catalog') row.status = _bulkStatus;
      final qty = _number(_bulkQuantity.text);
      if (qty != null && qty > 0) row.quantity.text = _bulkQuantity.text;
      _rows.insert(0, row);
      _productSearch.clear();
      _error = null;
    });
  }

  Future<void> _changeCompany() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change company?'),
        content: const Text(
          'The current product selection and entered costs will be cleared.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Change company'),
          ),
        ],
      ),
    );
    if (!mounted || discard != true) return;
    for (final row in _rows) {
      row.dispose();
    }
    setState(() {
      _rows.clear();
      _company = null;
      _companySearch.clear();
      _productSearch.clear();
      _error = null;
      _loading = true;
    });
    await _searchCompanies('');
  }

  Future<void> _save() async {
    if (_added || _saving) return;
    FocusScope.of(context).unfocus();
    // Validate every selected product, including rows outside the viewport.
    final selected = _selected;
    if (selected.isEmpty || selected.length > 1000) {
      setState(() => _error = 'Select between 1 and 1,000 products to add.');
      return;
    }
    for (final row in selected) {
      final qty = _number(row.quantity.text);
      final cost = _number(row.cost.text);
      if (qty == null || qty <= 0) {
        setState(
          () => _error =
              '${row.product.itemName}: enter a quantity greater than zero.',
        );
        return;
      }
      if (row.cost.text.trim().isNotEmpty && (cost == null || cost < 0)) {
        setState(
          () => _error =
              '${row.product.itemName}: cost must be a valid, non-negative number or left empty.',
        );
        return;
      }
      if (row.status.isEmpty || !_statuses.contains(row.status)) {
        setState(
          () => _error = '${row.product.itemName}: select a valid status.',
        );
        return;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final itemIds = await widget.repository.createRecords(
        selected
            .map(
              (row) => CreateItemsTrackerRecord(
                escalatedDate: _date,
                itemCode: row.product.itemCode,
                unitCost: _number(row.cost.text),
                inventoryNote: _reason.text.trim(),
                requiredQty: _number(row.quantity.text)!,
                statusUpdatedTo: row.status,
                followUpRole: row.followUp,
                manualProduct: row.manual ? row.product : null,
              ),
            )
            .toList(growable: false),
      );
      _added = true;
      if (_emailOnAdd && mounted) {
        setState(() => _saving = false);
        await showItemsTrackerEmailDialog(
          context: context,
          repository: widget.repository,
          itemIds: itemIds,
          company: _company!,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        if (_added) {
          Navigator.pop(context, true);
          return;
        }
        setState(() {
          _saving = false;
          _error =
              'Products were not added. Your entries are kept. ${_errorText(error)}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final total = selected.fold<double>(
      0,
      (sum, r) =>
          sum + ((_number(r.cost.text) ?? 0) * (_number(r.quantity.text) ?? 0)),
    );
    final costCount = selected
        .where((r) => _number(r.cost.text) != null)
        .length;
    return PopScope(
      canPop: !_saving,
      child: Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 1240,
          height: math.min(850, MediaQuery.sizeOf(context).height - 48),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 14, 18),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xffe6f5f5),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.business_outlined,
                        color: _accent,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Add company products',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: _ink,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _company ??
                                'Choose a company from Item Report, or enter a new company name.',
                            style: const TextStyle(color: _muted),
                          ),
                        ],
                      ),
                    ),
                    if (_company != null)
                      TextButton(
                        onPressed: _saving ? null : _changeCompany,
                        child: const Text('Change company'),
                      ),
                    IconButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.pop(context, false),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: _border),
              if (_error != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  color: const Color(0xfffff2ed),
                  child: Text(
                    _error!,
                    key: const ValueKey('companyEntryError'),
                    style: const TextStyle(color: Color(0xffb34527)),
                  ),
                ),
              Expanded(
                child: _company == null ? _companyPicker() : _productEditor(),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 18,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xfff7fafc),
                  border: Border(top: BorderSide(color: _border)),
                ),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 24,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 420,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${selected.length} selected · ${_rows.length} products',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _ink,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            costCount == 0
                                ? 'Cost is optional. Leave empty if unknown.'
                                : 'Known cost total: AED ${NumberFormat('#,##0.00').format(total)} · $costCount/${selected.length} costs entered',
                            style: const TextStyle(color: _muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 230,
                      child: Row(
                        children: [
                          Checkbox(
                            key: const ValueKey('companyEmailOnAdd'),
                            value: _emailOnAdd,
                            onChanged: _saving
                                ? null
                                : (value) => setState(
                                    () => _emailOnAdd = value ?? false,
                                  ),
                          ),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Email with Outlook',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: _ink,
                                  ),
                                ),
                                Text(
                                  'One email per department',
                                  style: TextStyle(fontSize: 11, color: _muted),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          key: const ValueKey('companyEntrySave'),
                          style: FilledButton.styleFrom(
                            backgroundColor: _accent,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 18,
                            ),
                          ),
                          onPressed:
                              _saving || _added || _loading || _company == null
                              ? null
                              : _save,
                          icon: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.add_rounded, size: 19),
                          label: Text(
                            _saving
                                ? 'Adding products…'
                                : 'Add ${selected.length} products${_emailOnAdd ? ' & email' : ''}',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _companyPicker() => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _companySearch,
          key: const ValueKey('companyEntrySearch'),
          onChanged: _scheduleSearch,
          decoration: _decoration(
            'Search or enter company name',
            icon: Icons.search,
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('companyEntryUseName'),
            onPressed: _loading || _companySearch.text.trim().isEmpty
                ? null
                : () => _selectCompany(_companySearch.text),
            icon: const Icon(Icons.add_business_outlined),
            label: const Text('Use this company name / add missing products'),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'COMPANIES IN ITEM REPORT',
          style: TextStyle(
            fontSize: 11,
            color: _muted,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 10),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: ListView.separated(
            itemCount: _companies.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final company = _companies[i];
              return Material(
                color: const Color(0xfff6f9fc),
                borderRadius: BorderRadius.circular(12),
                child: ListTile(
                  enabled: !_loading,
                  key: ValueKey('companyOption:${company.name}'),
                  leading: const Icon(Icons.business_outlined, color: _accent),
                  title: Text(
                    company.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _ink,
                    ),
                  ),
                  subtitle: Text('${company.productCount} products'),
                  trailing: const Icon(Icons.chevron_right, color: _muted),
                  onTap: () => _selectCompany(company.name),
                ),
              );
            },
          ),
        ),
        if (!_loading && _companies.isEmpty)
          const Text(
            'No matching company. Use the name above to add products manually.',
            style: TextStyle(color: _muted),
          ),
      ],
    ),
  );

  Widget _productEditor() => AbsorbPointer(
    absorbing: _saving,
    child: LayoutBuilder(
      builder: (context, constraints) => Scrollbar(
        controller: _horizontalScroll,
        thumbVisibility: constraints.maxWidth < 1100,
        notificationPredicate: (notification) =>
            notification.metrics.axis == Axis.horizontal,
        child: SingleChildScrollView(
          controller: _horizontalScroll,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: math.max(1100, constraints.maxWidth),
            height: constraints.maxHeight,
            child: Form(
              key: _form,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.check_circle_outline,
                                size: 18,
                                color: _accent,
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'All catalog products are selected. Uncheck any products you do not want to add.',
                                  style: TextStyle(color: _muted),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: _addManualProduct,
                                key: const ValueKey('companyEntryManual'),
                                icon: const Icon(Icons.add),
                                label: const Text('Add missing product'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller: _reason,
                                  maxLines: 2,
                                  key: const ValueKey('companyEntryReason'),
                                  decoration: _decoration(
                                    'Reason / inventory note for selected products',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              SizedBox(
                                width: 165,
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final date =
                                        await showItemsTrackerDatePicker(
                                          context: context,
                                          initialDate: _date,
                                        );
                                    if (date != null && mounted) {
                                      setState(() => _date = date);
                                    }
                                  },
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.all(18),
                                  ),
                                  icon: const Icon(
                                    Icons.calendar_today_outlined,
                                    size: 16,
                                  ),
                                  label: Text(
                                    DateFormat('dd MMM yyyy').format(_date),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xfff4f8fb),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 150,
                                  child: TextField(
                                    controller: _bulkQuantity,
                                    decoration: _decoration('Quantity for all'),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    final value = _number(_bulkQuantity.text);
                                    if (value == null || value <= 0) {
                                      setState(
                                        () => _error =
                                            'Enter a quantity greater than zero.',
                                      );
                                      return;
                                    }
                                    setState(() {
                                      for (final r in _selected) {
                                        r.quantity.text = _bulkQuantity.text;
                                      }
                                      _error = null;
                                    });
                                  },
                                  child: const Text('Apply'),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    initialValue: _bulkFollowUp,
                                    decoration: _decoration('Follow up by'),
                                    items: [
                                      const DropdownMenuItem(
                                        value: 'auto',
                                        child: Text('By product category'),
                                      ),
                                      ...ItemsTrackerRoles.allowed.map(
                                        (r) => DropdownMenuItem(
                                          value: r,
                                          child: Text(
                                            ItemsTrackerRoles.label(r),
                                          ),
                                        ),
                                      ),
                                    ],
                                    onChanged: (value) {
                                      if (value == null) return;
                                      setState(() {
                                        _bulkFollowUp = value;
                                        for (final r in _selected) {
                                          r.followUp = value == 'auto'
                                              ? ItemsTrackerRoles.defaultFollowUpForCategory(
                                                  r.product.category,
                                                )
                                              : value;
                                        }
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    initialValue: _bulkStatus,
                                    decoration: _decoration(
                                      'Status for selected products',
                                    ),
                                    items: [
                                      const DropdownMenuItem(
                                        value: 'catalog',
                                        child: Text('Use catalog status'),
                                      ),
                                      ..._statuses.map(
                                        (s) => DropdownMenuItem(
                                          value: s,
                                          child: Text(
                                            s,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ],
                                    isExpanded: true,
                                    onChanged: (value) {
                                      if (value == null) return;
                                      setState(() {
                                        _bulkStatus = value;
                                        for (final r in _selected) {
                                          r.status = value == 'catalog'
                                              ? (_statuses.contains(
                                                      r.product.itemStatus,
                                                    )
                                                    ? r.product.itemStatus
                                                    : (_statuses.isEmpty
                                                          ? ''
                                                          : _statuses.first))
                                              : value;
                                        }
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Checkbox(
                                value:
                                    _rows.isNotEmpty &&
                                    _selected.length == _rows.length,
                                tristate: false,
                                onChanged: (value) => setState(() {
                                  for (final r in _rows) {
                                    r.selected = value ?? false;
                                  }
                                }),
                              ),
                              const Text(
                                'Select all',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(width: 18),
                              Expanded(
                                child: TextField(
                                  controller: _productSearch,
                                  onChanged: (_) => setState(() {}),
                                  decoration: _decoration(
                                    'Find a product in this company',
                                    icon: Icons.search,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_rows.isEmpty)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'No products in Item Report for this company. Add a missing product to begin.',
                          style: TextStyle(color: _muted),
                        ),
                      ),
                    ),
                  SliverList.builder(
                    itemCount: _filtered.length,
                    itemBuilder: (_, i) => _productRow(_filtered[i]),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _productRow(_CompanyProductDraft row) {
    final p = row.product;
    final index = _rows.indexOf(row);
    return Container(
      key: ValueKey(row),
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BoxDecoration(
        color: row.selected ? Colors.white : const Color(0xfff7f9fb),
        border: Border.all(
          color: row.selected ? _border : const Color(0xffecf0f4),
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Checkbox(
            value: row.selected,
            key: ValueKey('companySelect:$index'),
            onChanged: (value) => setState(() => row.selected = value ?? false),
          ),
          const SizedBox(width: 4),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.itemName,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: row.selected ? _ink : _muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${p.itemCode.isEmpty ? 'Auto-generated code' : p.itemCode} · ${p.category}',
                  style: const TextStyle(color: _muted, fontSize: 11),
                ),
                if (row.manual)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'MANUAL PRODUCT',
                      style: TextStyle(
                        color: _accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          SizedBox(
            width: 115,
            child: TextFormField(
              controller: row.cost,
              enabled: row.selected,
              key: ValueKey('companyCost:$index'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: _decoration('Cost (AED)', hint: 'Optional'),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 95,
            child: TextFormField(
              controller: row.quantity,
              enabled: row.selected,
              key: ValueKey('companyQty:$index'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: _decoration('Quantity'),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 140,
            child: DropdownButtonFormField<String>(
              key: ValueKey('companyFollowUp:$index:${row.followUp}'),
              initialValue: row.followUp,
              decoration: _decoration('Follow up by'),
              isExpanded: true,
              items: ItemsTrackerRoles.allowed
                  .map(
                    (r) => DropdownMenuItem(
                      value: r,
                      child: Text(ItemsTrackerRoles.label(r)),
                    ),
                  )
                  .toList(),
              onChanged: row.selected
                  ? (value) => setState(() => row.followUp = value!)
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String>(
              key: ValueKey('companyStatus:$index:${row.status}'),
              initialValue: row.status.isEmpty ? null : row.status,
              decoration: _decoration('Status updated to'),
              isExpanded: true,
              items: _statuses
                  .map(
                    (s) => DropdownMenuItem(
                      value: s,
                      child: Text(s, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: row.selected
                  ? (value) => setState(() => row.status = value!)
                  : null,
            ),
          ),
          if (row.manual)
            IconButton(
              tooltip: 'Remove manual product',
              onPressed: () {
                setState(() => _rows.remove(row));
                row.dispose();
              },
              icon: const Icon(Icons.delete_outline, color: _muted),
            ),
        ],
      ),
    );
  }
}

class _ManualProductDialog extends StatefulWidget {
  final String company;
  const _ManualProductDialog({required this.company});
  @override
  State<_ManualProductDialog> createState() => _ManualProductDialogState();
}

class _ManualProductDialogState extends State<_ManualProductDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _category = TextEditingController();
  final _supplier = TextEditingController();

  @override
  void dispose() {
    for (final c in [_name, _code, _category, _supplier]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Add missing product',
                  style: TextStyle(
                    fontSize: 22,
                    color: _ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.company,
                  style: const TextStyle(
                    color: _accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Saved in Item Tracker only. Cost and quantity are entered in the company list.',
                  style: TextStyle(color: _muted, height: 1.5),
                ),
                const SizedBox(height: 22),
                TextFormField(
                  controller: _name,
                  key: const ValueKey('manualProductName'),
                  decoration: _decoration('Product name *'),
                  validator: _required,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _code,
                  key: const ValueKey('manualProductCode'),
                  decoration: _decoration(
                    'Item code (optional)',
                    hint: 'Generated automatically if empty',
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _category,
                  key: const ValueKey('manualProductCategory'),
                  decoration: _decoration(
                    'Category *',
                    hint: 'e.g. MEDICINE, COSMETICS',
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _supplier,
                  key: const ValueKey('manualProductSupplier'),
                  decoration: _decoration('Supplier (optional)'),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: () {
                        if (!_form.currentState!.validate()) return;
                        Navigator.pop(
                          context,
                          ItemsTrackerProduct(
                            itemCode: _code.text.trim(),
                            itemName: _name.text.trim(),
                            category: _category.text.trim().toUpperCase(),
                            supplier: _supplier.text.trim(),
                            company: widget.company,
                            itemStatus: '',
                            retailPrice: null,
                          ),
                        );
                      },
                      key: const ValueKey('manualProductAdd'),
                      child: const Text('Add to selection'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

InputDecoration _decoration(String label, {String? hint, IconData? icon}) =>
    InputDecoration(
      labelText: label,
      hintText: hint,
      isDense: true,
      prefixIcon: icon == null ? null : Icon(icon, size: 20, color: _muted),
      filled: true,
      fillColor: Colors.white,
      labelStyle: const TextStyle(color: _muted, fontSize: 12),
      hintStyle: const TextStyle(color: _muted, fontSize: 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 17),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _accent, width: 1.5),
      ),
    );
double? _number(String text) {
  final number = double.tryParse(text.trim().replaceAll(',', ''));
  return number != null && number.isFinite ? number : null;
}

String? _required(String? value) =>
    (value ?? '').trim().isEmpty ? 'Required' : null;
String _errorText(Object error) {
  final message = error.toString();
  if (message.contains('PRODUCT_ALREADY_IN_ITEM_REPORT')) {
    return 'This code already exists in Item Report. Select the catalog product.';
  }
  if (message.contains('DUPLICATE_PRODUCT')) {
    return 'Duplicate product codes are not allowed in one selection.';
  }
  if (message.contains('INVENTORY_PERMISSION')) {
    return 'Only Inventory can add products.';
  }
  return message;
}
