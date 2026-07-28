part of '../zone_manager_page.dart';

extension _ZoneMaxAdjustmentPageView on _ZoneManagerPageState {
  Widget buildZoneMaxAdjustmentPage() {
    if (_reportLoading && _maxAdj.isEmpty) {
      return const _ReportLoading(label: 'Loading max adjustments…');
    }
    final rows = _filtered(_maxAdj, 'branch_name')..sort(_compareBranchItem);
    const columns = [
      _ColumnDef('branch_name', 'Branch'),
      _ColumnDef('item_code', 'Item Code'),
      _ColumnDef('item_name', 'Item Name'),
      _ColumnDef('current_demand_30d', 'Demand'),
      _ColumnDef('max_adjustment_30d', 'Max Adj'),
      _ColumnDef('adjustment_type', 'Type'),
      _ColumnDef('qty', 'Qty'),
      _ColumnDef('reason', 'Reason'),
      _ColumnDef('update_date', 'Date'),
      _ColumnDef('added_by', 'Added By'),
    ];
    return _ReportPage(
      title: 'Max Adjustment',
      subtitle: 'All active maximum-stock adjustments for zone branches.',
      accent: const Color(0xffF97316),
      rows: rows,
      columns: columns,
      searchController: _search,
      onSearchChanged: _onSearchChanged,
      extraActions: [
        FilledButton.icon(
          onPressed: _showZoneAddMaxDialog,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xff0F2942),
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.add_rounded, size: 19),
          label: const Text('Add Max'),
        ),
      ],
      kpis: [
        _ReportKpi(
          Icons.tune_rounded,
          'Total Adjustments',
          '${rows.length}',
          'Active maximum changes',
          const Color(0xff2563EB),
        ),
        _ReportKpi(
          Icons.add_chart_rounded,
          'Increased Max',
          '${rows.where(_isPositiveMaxAdjustment).length}',
          'Upward stock adjustments',
          const Color(0xff16A34A),
        ),
        _ReportKpi(
          Icons.trending_down_rounded,
          'Reduced Max',
          '${rows.where(_isNegativeMaxAdjustment).length}',
          'Downward stock adjustments',
          const Color(0xffEF4444),
        ),
        _ReportKpi(
          Icons.schedule_rounded,
          'Last Updated',
          _latestActivity(rows, const ['update_date', 'created_at']),
          'Latest adjustment activity',
          const Color(0xff7C3AED),
        ),
      ],
      onExport: () => _exportExcel('Max_Adjustment', rows, columns),
    );
  }

  Future<void> _showZoneAddMaxDialog() async {
    if (_branches.isEmpty) {
      _message('No branches are assigned to this zone.', error: true);
      return;
    }
    final names = _branches
        .map((row) => _text(row['branch_name']))
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    final latestCredits = await _loadMaxCredits(names);
    if (!mounted) return;
    if (latestCredits.isNotEmpty) {
      // ignore: invalid_use_of_protected_member
      setState(() => _maxCredits = latestCredits);
    }
    final initialBranch = _selectedBranch != 'ALL'
        ? _selectedBranch
        : _text(_branches.first['branch_name']);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _ZoneAddMaxDialog(
        branches: _branches,
        credits: _maxCredits,
        initialBranch: initialBranch,
        remote: OrdersRemoteDs(_client),
        onSubmit: _submitZoneMax,
      ),
    );
  }

  Future<String?> _submitZoneMax(Map<String, dynamic> draft) async {
    final branch = _text(draft['branch_name']);
    final allowed = _branches.any(
      (row) => _key(row['branch_name']) == _key(branch),
    );
    if (!allowed) return 'This branch does not belong to your zone.';

    final itemCode = _text(draft['item_code']);
    final itemName = _text(draft['item_name']);
    final reason = _text(draft['reason']);
    final maxValue = num.tryParse(_text(draft['max_adjustment_30d']));
    if (itemCode.isEmpty || itemName.isEmpty) return 'Select a valid item.';
    if (maxValue == null || maxValue < 0) return 'Enter a valid Max value.';
    if (reason.isEmpty) return 'Reason is required.';

    final remote = OrdersRemoteDs(_client);
    try {
      final demand = await remote.fetchItemDemand(
        branch: branch,
        itemCode: itemCode,
      );
      final type = maxValue <= demand ? 'DECREASE' : 'INCREASE';
      final branchInfo = await remote.fetchBranchInfo(branchName: branch);
      final remaining = _zmInt(branchInfo['remaining_slots']);
      if (type == 'INCREASE' && remaining <= 0) {
        return 'No increase credit remains for $branch. Decreases are still allowed.';
      }

      final taggedReason = reason.toLowerCase().endsWith('added by zone')
          ? reason
          : '$reason - Added by Zone';
      await remote.insertMaxAdj({
        'branch_name': branch,
        'item_code': itemCode,
        'item_name': itemName,
        'current_demand_30d': demand,
        'max_adjustment_30d': maxValue,
        'qty': maxValue,
        'adjustment_type': type,
        'reason': taggedReason,
        'added_by': 'branch',
      });

      final names = _branches
          .map((row) => _text(row['branch_name']))
          .where((name) => name.isNotEmpty)
          .toList(growable: false);
      final refreshed = await Future.wait<dynamic>([
        _loadMaxAdj(names),
        _loadMaxCredits(names),
      ]);
      if (!mounted) return null;
      // ignore: invalid_use_of_protected_member
      setState(() {
        _maxAdj = List<Map<String, dynamic>>.from(refreshed[0])
          ..sort(_compareBranchItem);
        _maxCredits = Map<String, Map<String, dynamic>>.from(refreshed[1]);
      });
      _message('Max adjustment added for $branch.');
      return null;
    } catch (error) {
      final message = error.toString();
      if (message.contains('Item already exists')) {
        return 'This item already exists in the Max list for $branch.';
      }
      if (message.contains('Max limit reached')) {
        return 'The increase credit limit has been reached for $branch.';
      }
      return 'Could not add Max adjustment: $message';
    }
  }
}

typedef _ZoneMaxSubmit = Future<String?> Function(Map<String, dynamic> draft);

class _ZoneAddMaxDialog extends StatefulWidget {
  final List<Map<String, dynamic>> branches;
  final Map<String, Map<String, dynamic>> credits;
  final String initialBranch;
  final OrdersRemoteDs remote;
  final _ZoneMaxSubmit onSubmit;

  const _ZoneAddMaxDialog({
    required this.branches,
    required this.credits,
    required this.initialBranch,
    required this.remote,
    required this.onSubmit,
  });

  @override
  State<_ZoneAddMaxDialog> createState() => _ZoneAddMaxDialogState();
}

class _ZoneAddMaxDialogState extends State<_ZoneAddMaxDialog> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _max = TextEditingController();
  final _reason = TextEditingController();
  late String _branch;
  num _demand = 0;
  bool _demandLoading = false;
  bool _searching = false;
  bool _saving = false;
  String? _error;
  int _searchRequest = 0;
  List<Map<String, dynamic>> _suggestions = const [];

  List<Map<String, dynamic>> get _branches {
    final rows = List<Map<String, dynamic>>.from(widget.branches);
    rows.sort(
      (a, b) => _zmKey(a['branch_name']).compareTo(_zmKey(b['branch_name'])),
    );
    return rows;
  }

  Map<String, dynamic> get _branchRow => _branches.firstWhere(
    (row) => _zmKey(row['branch_name']) == _zmKey(_branch),
    orElse: () => const {},
  );

  Map<String, dynamic> get _credit =>
      widget.credits[_zmKey(_branch)] ?? const {};

  int get _limit {
    final value = _zmInt(_branchRow['max_adj_limit']);
    return value > 0 ? value : 50;
  }

  int get _used => _zmInt(_credit['used_slots']);

  int get _remaining {
    if (_credit.containsKey('remaining_slots')) {
      return _zmInt(_credit['remaining_slots']).clamp(0, _limit);
    }
    return (_limit - _used).clamp(0, _limit);
  }

  num? get _maxValue => num.tryParse(_max.text.trim());

  bool get _isIncrease => _maxValue != null && _maxValue! > _demand;

  @override
  void initState() {
    super.initState();
    _branch = widget.initialBranch;
    if (!_branches.any(
      (row) => _zmKey(row['branch_name']) == _zmKey(_branch),
    )) {
      _branch = _zmText(_branches.first['branch_name']);
    }
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _max.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _searchItems(String query, {required bool byCode}) async {
    final request = ++_searchRequest;
    final normalized = query.trim();
    if (normalized.length < 2) {
      setState(() {
        _suggestions = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    try {
      final rows = byCode
          ? await widget.remote.searchItemsByCode(normalized)
          : await widget.remote.searchItemsByName(normalized);
      if (!mounted || request != _searchRequest) return;
      setState(() => _suggestions = rows);
    } catch (error) {
      if (!mounted || request != _searchRequest) return;
      setState(() => _error = 'Item search failed: $error');
    } finally {
      if (mounted && request == _searchRequest) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _selectItem(Map<String, dynamic> row) async {
    _code.text = _zmText(row['item_code']);
    _name.text = _zmText(row['item_name']);
    setState(() {
      _suggestions = const [];
      _error = null;
    });
    await _loadDemand();
  }

  Future<void> _loadDemand() async {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    setState(() => _demandLoading = true);
    try {
      final value = await widget.remote.fetchItemDemand(
        branch: _branch,
        itemCode: code,
      );
      if (!mounted) return;
      setState(() => _demand = value);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Could not load item demand: $error');
    } finally {
      if (mounted) setState(() => _demandLoading = false);
    }
  }

  Future<void> _changeBranch(String value) async {
    setState(() {
      _branch = value;
      _error = null;
    });
    if (_code.text.trim().isNotEmpty) await _loadDemand();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final maxValue = _maxValue;
    if (_code.text.trim().isEmpty || _name.text.trim().isEmpty) {
      setState(() => _error = 'Select an item from the suggestions.');
      return;
    }
    if (maxValue == null || maxValue < 0) {
      setState(() => _error = 'Enter a valid Max adjustment value.');
      return;
    }
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'Reason is required.');
      return;
    }
    if (_isIncrease && _remaining <= 0) {
      setState(
        () => _error =
            'No increase credit remains for $_branch. You can still submit a decrease.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.onSubmit({
      'branch_name': _branch,
      'item_code': _code.text.trim(),
      'item_name': _name.text.trim(),
      'max_adjustment_30d': maxValue,
      'reason': _reason.text.trim(),
    });
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final compact = screen.width < 980;
    final canIncrease = _remaining > 0;
    return Dialog(
      insetPadding: const EdgeInsets.all(22),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 1160,
          maxHeight: screen.height * .90,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xffF6F8FC),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xffD7E0EB)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x330F172A),
                blurRadius: 38,
                offset: Offset(0, 18),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _ZoneMaxDialogHeader(onClose: () => Navigator.pop(context)),
              Expanded(
                child: compact
                    ? SingleChildScrollView(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          children: [
                            SizedBox(
                              height: 230,
                              child: _ZoneMaxCreditRail(
                                branches: _branches,
                                credits: widget.credits,
                                selectedBranch: _branch,
                                onSelected: _changeBranch,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildForm(canIncrease),
                          ],
                        ),
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 330,
                            child: _ZoneMaxCreditRail(
                              branches: _branches,
                              credits: widget.credits,
                              selectedBranch: _branch,
                              onSelected: _changeBranch,
                            ),
                          ),
                          const VerticalDivider(width: 1),
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(22),
                              child: _buildForm(canIncrease),
                            ),
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

  Widget _buildForm(bool canIncrease) {
    final increase = _isIncrease;
    final typeColor = increase
        ? const Color(0xff16A34A)
        : const Color(0xffEF4444);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Create maximum-stock adjustment',
          style: TextStyle(
            color: Color(0xff0F2942),
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'Uses the same item, demand, credit and save logic as the branch workspace.',
          style: TextStyle(
            color: Color(0xff64748B),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 18),
        DropdownButtonFormField<String>(
          initialValue: _branch,
          isExpanded: true,
          decoration: _zmInputDecoration('Branch', Icons.storefront_rounded),
          items: _branches
              .map((row) {
                final name = _zmText(row['branch_name']);
                final credit = widget.credits[_zmKey(name)] ?? const {};
                final limit = _zmInt(row['max_adj_limit']) > 0
                    ? _zmInt(row['max_adj_limit'])
                    : 50;
                final remaining = credit.containsKey('remaining_slots')
                    ? _zmInt(credit['remaining_slots'])
                    : (limit - _zmInt(credit['used_slots']));
                return DropdownMenuItem(
                  value: name,
                  child: Text(
                    '$name  •  ${remaining.clamp(0, limit)} of $limit increase credits left',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                );
              })
              .toList(growable: false),
          onChanged: _saving
              ? null
              : (value) {
                  if (value != null) _changeBranch(value);
                },
        ),
        const SizedBox(height: 12),
        _ZoneMaxCreditSummary(
          branch: _branch,
          used: _used,
          remaining: _remaining,
          limit: _limit,
          nextAvailableDate: _zmText(_credit['next_available_date']),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _code,
                enabled: !_saving,
                decoration: _zmInputDecoration(
                  'Item Code',
                  Icons.qr_code_rounded,
                ),
                onChanged: (value) => _searchItems(value, byCode: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _name,
                enabled: !_saving,
                decoration: _zmInputDecoration(
                  'Item Name',
                  Icons.medication_outlined,
                ),
                onChanged: (value) => _searchItems(value, byCode: false),
              ),
            ),
          ],
        ),
        if (_searching)
          const LinearProgressIndicator(minHeight: 2)
        else if (_suggestions.isNotEmpty)
          _ZoneMaxSuggestions(rows: _suggestions, onSelected: _selectItem),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _ZoneMaxReadOnlyValue(
                label: 'Current Demand (30D)',
                value: _demandLoading ? 'Loading…' : _zmNumber(_demand),
                icon: Icons.query_stats_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _max,
                enabled: !_saving,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: _zmInputDecoration(
                  'Max Adjustment',
                  Icons.tune_rounded,
                ),
                onChanged: (_) => setState(() => _error = null),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            color: typeColor.withValues(alpha: .07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: typeColor.withValues(alpha: .24)),
          ),
          child: Row(
            children: [
              Icon(
                increase
                    ? Icons.trending_up_rounded
                    : Icons.trending_down_rounded,
                color: typeColor,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  increase
                      ? 'INCREASE • consumes 1 credit after a successful save.'
                      : 'DECREASE • does not consume increase credit.',
                  style: TextStyle(
                    color: typeColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (increase && !canIncrease)
                const Text(
                  'NO CREDIT',
                  style: TextStyle(
                    color: Color(0xffEF4444),
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _reason,
          enabled: !_saving,
          maxLines: 3,
          decoration: _zmInputDecoration(
            'Reason',
            Icons.notes_rounded,
            helper: 'Saved as: your reason - Added by Zone',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xffFEF2F2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xffFCA5A5)),
            ),
            child: Text(
              _error!,
              style: const TextStyle(
                color: Color(0xffB91C1C),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xffF97316),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 15,
                ),
              ),
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.add_rounded),
              label: Text(_saving ? 'Adding…' : 'Add Max for $_branch'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ZoneMaxDialogHeader extends StatelessWidget {
  final VoidCallback onClose;

  const _ZoneMaxDialogHeader({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xff0F2942), Color(0xff174A68)],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.add_chart_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Zone Max Control',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  'Select a zone branch, review its credit, then create an adjustment.',
                  style: TextStyle(
                    color: Color(0xffC8D8E5),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
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

class _ZoneMaxCreditRail extends StatelessWidget {
  final List<Map<String, dynamic>> branches;
  final Map<String, Map<String, dynamic>> credits;
  final String selectedBranch;
  final ValueChanged<String> onSelected;

  const _ZoneMaxCreditRail({
    required this.branches,
    required this.credits,
    required this.selectedBranch,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(15, 17, 12, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'BRANCH INCREASE CREDIT',
            style: TextStyle(
              color: Color(0xff64748B),
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: .7,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Decreases are always allowed',
            style: TextStyle(
              color: Color(0xff0F2942),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Scrollbar(
              child: ListView.separated(
                itemCount: branches.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final row = branches[index];
                  final branch = _zmText(row['branch_name']);
                  final limit = _zmInt(row['max_adj_limit']) > 0
                      ? _zmInt(row['max_adj_limit'])
                      : 50;
                  final credit = credits[_zmKey(branch)] ?? const {};
                  final used = _zmInt(credit['used_slots']);
                  final remaining = credit.containsKey('remaining_slots')
                      ? _zmInt(credit['remaining_slots'])
                      : limit - used;
                  return _ZoneMaxCreditRow(
                    branch: branch,
                    used: used,
                    remaining: remaining.clamp(0, limit),
                    limit: limit,
                    selected: _zmKey(branch) == _zmKey(selectedBranch),
                    onTap: () => onSelected(branch),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ZoneMaxCreditRow extends StatelessWidget {
  final String branch;
  final int used, remaining, limit;
  final bool selected;
  final VoidCallback onTap;

  const _ZoneMaxCreditRow({
    required this.branch,
    required this.used,
    required this.remaining,
    required this.limit,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = remaining == 0
        ? const Color(0xffEF4444)
        : remaining <= 5
        ? const Color(0xffF59E0B)
        : const Color(0xff16A34A);
    final progress = limit <= 0 ? 0.0 : (used / limit).clamp(0.0, 1.0);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: selected ? const Color(0xffEFF6FF) : const Color(0xffF8FAFC),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected
                  ? const Color(0xff38BDF8)
                  : const Color(0xffE2E8F0),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.storefront_rounded, size: 15, color: color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      branch,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xff0F2942),
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    '$remaining left',
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: const Color(0xffE2E8F0),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '$used used of $limit',
                style: const TextStyle(
                  color: Color(0xff64748B),
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ZoneMaxCreditSummary extends StatelessWidget {
  final String branch;
  final int used, remaining, limit;
  final String nextAvailableDate;

  const _ZoneMaxCreditSummary({
    required this.branch,
    required this.used,
    required this.remaining,
    required this.limit,
    required this.nextAvailableDate,
  });

  @override
  Widget build(BuildContext context) {
    final color = remaining == 0
        ? const Color(0xffEF4444)
        : const Color(0xff16A34A);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: .10), Colors.white],
        ),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: color.withValues(alpha: .24)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.bolt_rounded, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$branch • $remaining increase credits remaining',
                  style: const TextStyle(
                    color: Color(0xff0F2942),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  remaining == 0 && nextAvailableDate.isNotEmpty
                      ? '$used of $limit used • Next available $nextAvailableDate'
                      : '$used of $limit used • Decreases remain unlimited',
                  style: const TextStyle(
                    color: Color(0xff64748B),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ZoneMaxSuggestions extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final ValueChanged<Map<String, dynamic>> onSelected;

  const _ZoneMaxSuggestions({required this.rows, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 210),
      margin: const EdgeInsets.only(top: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xffCBD5E1)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x190F172A),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: rows.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final row = rows[index];
          return ListTile(
            dense: true,
            leading: const Icon(Icons.medication_outlined),
            title: Text(
              _zmText(row['item_name']),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(_zmText(row['item_code'])),
            onTap: () => onSelected(row),
          );
        },
      ),
    );
  }
}

class _ZoneMaxReadOnlyValue extends StatelessWidget {
  final String label, value;
  final IconData icon;

  const _ZoneMaxReadOnlyValue({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: const Color(0xffF1F5F9),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xffCBD5E1)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xff64748B), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xff64748B),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xff0F2942),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

InputDecoration _zmInputDecoration(
  String label,
  IconData icon, {
  String? helper,
}) {
  return InputDecoration(
    labelText: label,
    helperText: helper,
    prefixIcon: Icon(icon, size: 20),
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(color: Color(0xffCBD5E1)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(color: Color(0xffCBD5E1)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(color: Color(0xff38BDF8), width: 1.5),
    ),
  );
}

String _zmText(dynamic value) => value?.toString().trim() ?? '';

String _zmKey(dynamic value) => _zmText(value).toLowerCase();

int _zmInt(dynamic value) =>
    value is num ? value.toInt() : int.tryParse(_zmText(value)) ?? 0;

String _zmNumber(num value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
