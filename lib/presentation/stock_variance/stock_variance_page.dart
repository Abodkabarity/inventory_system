import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:daily_order/core/utils/store_branch_identity_registry.dart';

/// Shared workflow surface. The database checks every write and scopes reads.
class StockVariancePage extends StatefulWidget {
  final String role;
  final bool embedded;

  const StockVariancePage({
    super.key,
    required this.role,
    this.embedded = false,
  });

  @override
  State<StockVariancePage> createState() => _StockVariancePageState();
}

class _StockVariancePageState extends State<StockVariancePage> {
  static const _pageSize = 100;
  static const _navy = Color(0xFF152644);
  static const _blue = Color(0xFF3268D8);
  static const _background = Color(0xFFF4F7FC);
  final _client = Supabase.instance.client;
  final _search = TextEditingController();
  List<Map<String, dynamic>> _requests = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;
  String _filter = 'all';

  bool get _isBranch => widget.role == 'branch';
  bool get _isZone => widget.role == 'zone_manager';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final result = await _client
          .from('stock_variance_requests')
          .select('*,stock_variance_items(*),stock_variance_events(*)')
          .order('submitted_at', ascending: false)
          .range(0, _pageSize - 1);
      if (!mounted) return;
      final rows = List<Map<String, dynamic>>.from(result);
      setState(() {
        _requests = rows;
        _hasMore = rows.length == _pageSize;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final result = await _client
          .from('stock_variance_requests')
          .select('*,stock_variance_items(*),stock_variance_events(*)')
          .order('submitted_at', ascending: false)
          .range(_requests.length, _requests.length + _pageSize - 1);
      if (!mounted) return;
      final rows = List<Map<String, dynamic>>.from(result);
      setState(() {
        _requests.addAll(rows);
        _hasMore = rows.length == _pageSize;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  List<Map<String, dynamic>> get _visible => _requests.where((r) {
    final query = _search.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      final items = List<Map<String, dynamic>>.from(
        r['stock_variance_items'] ?? [],
      );
      final matches =
          '${StoreBranchIdentityRegistry.displayName(r['branch_name']?.toString())} ${r['id']} ${r['zone']}'.toLowerCase().contains(
            query,
          ) ||
          items.any(
            (item) =>
                '${item['item_code']} ${item['item_name']} ${item['batch_number']}'
                    .toLowerCase()
                    .contains(query),
          );
      if (!matches) return false;
    }
    if (_filter == 'all') return true;
    if (_filter == 'active') {
      return !{
        'closed',
        'rejected_zone',
        'rejected_inventory',
      }.contains(r['status']);
    }
    return r['status'] == _filter;
  }).toList();

  String _label(String value) =>
      const {
        'pending_zone': 'With Zone Manager',
        'returned_branch': 'Returned to Branch',
        'rejected_zone': 'Rejected by Zone',
        'pending_inventory': 'With Inventory',
        'returned_zone': 'Returned to Zone',
        'audit_review': 'With Audit Team',
        'correction_pending': 'Correction Pending',
        'closed': 'Closed',
        'rejected_inventory': 'Rejected by Inventory',
      }[value] ??
      value;

  Color _statusColor(String value) => switch (value) {
    'closed' => const Color(0xFF0D936D),
    'rejected_zone' || 'rejected_inventory' => const Color(0xFFD34B55),
    'audit_review' => const Color(0xFF8054C8),
    'returned_branch' || 'returned_zone' => const Color(0xFFDF8B25),
    _ => _blue,
  };

  List<({String code, String label, bool needsReference})> _actions(
    Map<String, dynamic> r,
  ) {
    final status = (r['status'] ?? '').toString();
    if (_isBranch && status == 'returned_branch') {
      return [
        (code: 'revise', label: 'Edit and Resubmit', needsReference: false),
      ];
    }
    if (_isZone && {'pending_zone', 'returned_zone'}.contains(status)) {
      return [
        (
          code: 'zone_approve',
          label: 'Approve and Send to Inventory',
          needsReference: false,
        ),
        (code: 'zone_return', label: 'Return to Branch', needsReference: false),
        (code: 'zone_reject', label: 'Reject Request', needsReference: false),
      ];
    }
    if (widget.role == 'inventory') {
      if (status == 'pending_inventory') {
        return [
          (
            code: 'ready_correction',
            label: 'Ready for Correction',
            needsReference: false,
          ),
          (
            code: 'send_audit',
            label: 'Send to Audit Team',
            needsReference: true,
          ),
          (
            code: 'inventory_return',
            label: 'Return to Zone',
            needsReference: false,
          ),
          (
            code: 'inventory_reject',
            label: 'Reject Request',
            needsReference: false,
          ),
        ];
      }
      if (status == 'audit_review') {
        return [
          (
            code: 'ready_correction',
            label: 'Record Audit Result and Continue',
            needsReference: false,
          ),
          (
            code: 'audit_no_change',
            label: 'Close Without Correction',
            needsReference: true,
          ),
        ];
      }
      if (status == 'correction_pending') {
        return [
          (
            code: 'close',
            label: 'Record Correction and Close',
            needsReference: true,
          ),
        ];
      }
    }
    return [];
  }

  Future<void> _act(
    Map<String, dynamic> request,
    ({String code, String label, bool needsReference}) action,
  ) async {
    final note = TextEditingController();
    final reference = TextEditingController();
    bool saving = false;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: Text(
            action.label,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: note,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Reason / investigation notes *',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (action.needsReference) ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: reference,
                    decoration: InputDecoration(
                      labelText:
                          action.code == 'send_audit' ||
                              action.code == 'audit_no_change'
                          ? 'Audit reference *'
                          : 'Correction reference *',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (note.text.trim().isEmpty ||
                          (action.needsReference &&
                              reference.text.trim().isEmpty)) {
                        update(() => error = 'Complete the required fields.');
                        return;
                      }
                      update(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        await _client.rpc(
                          'transition_stock_variance_request',
                          params: {
                            'p_request_id': request['id'],
                            'p_action': action.code,
                            'p_note': note.text.trim(),
                            'p_reference': reference.text.trim(),
                          },
                        );
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                        await _load();
                      } catch (e) {
                        update(() {
                          saving = false;
                          error = e.toString();
                        });
                      }
                    },
              child: Text(saving ? 'Saving…' : 'Confirm'),
            ),
          ],
        ),
      ),
    );
    note.dispose();
    reference.dispose();
  }

  Future<void> _newRequest([Map<String, dynamic>? existing]) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _CreateVarianceDialog(existing: existing),
    );
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final body = Container(
      color: _background,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_navy, Color(0xFF345AAF)],
                ),
                borderRadius: BorderRadius.circular(26),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x26345AAF),
                    blurRadius: 26,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 20,
                runSpacing: 16,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.inventory_2_outlined,
                        color: Colors.white70,
                        size: 30,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Stock Variance Requests',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _isBranch
                            ? 'Report a difference and follow every decision.'
                            : _isZone
                            ? 'Review requests from your assigned zones.'
                            : 'Investigate, route to audit, and record the final correction.',
                        style: const TextStyle(
                          color: Color(0xFFE1E9FF),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  if (_isBranch)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: _navy,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 18,
                        ),
                      ),
                      onPressed: _newRequest,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('New request'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _metric('Loaded', _requests.length, Icons.receipt_long_rounded),
                _metric(
                  'Open',
                  _requests
                      .where(
                        (r) => !{
                          'closed',
                          'rejected_zone',
                          'rejected_inventory',
                        }.contains(r['status']),
                      )
                      .length,
                  Icons.pending_actions_rounded,
                ),
                _metric(
                  'With Audit',
                  _requests.where((r) => r['status'] == 'audit_review').length,
                  Icons.policy_outlined,
                ),
                _metric(
                  'Closed',
                  _requests.where((r) => r['status'] == 'closed').length,
                  Icons.verified_outlined,
                ),
              ],
            ),
            const SizedBox(height: 22),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search branch, product, batch or request ID',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFFE5EAF3)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in [
                  ('all', 'All'),
                  ('active', 'Open'),
                  ('pending_zone', 'With Zone'),
                  ('pending_inventory', 'With Inventory'),
                  ('audit_review', 'With Audit'),
                  ('closed', 'Closed'),
                ])
                  ChoiceChip(
                    label: Text(entry.$2),
                    selected: _filter == entry.$1,
                    onSelected: (_) => setState(() => _filter = entry.$1),
                  ),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _notice('Unable to load requests. $_error', Icons.error_outline)
            else if (_visible.isEmpty)
              _notice(
                _requests.isEmpty
                    ? 'No variance requests yet.'
                    : 'No requests match this filter.',
                Icons.inbox_outlined,
              )
            else
              for (final request in _visible) _requestCard(request),
            if (!_loading && _hasMore)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: OutlinedButton.icon(
                    onPressed: _loadingMore ? null : _loadMore,
                    icon: _loadingMore
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.expand_more_rounded),
                    label: Text(
                      _loadingMore ? 'Loading…' : 'Load more requests',
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    return widget.embedded
        ? body
        : Scaffold(
            appBar: AppBar(
              title: const Text('Stock Variance'),
              backgroundColor: _background,
            ),
            body: body,
          );
  }

  Widget _metric(String title, int count, IconData icon) => Container(
    width: 185,
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFE5EAF3)),
    ),
    child: Row(
      children: [
        Icon(icon, color: _blue),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$count',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: _navy,
              ),
            ),
            Text(
              title,
              style: const TextStyle(color: Color(0xFF66758D), fontSize: 12),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _notice(String text, IconData icon) => Container(
    padding: const EdgeInsets.all(36),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      children: [
        Icon(icon, size: 42, color: _blue),
        const SizedBox(height: 12),
        Text(text),
      ],
    ),
  );

  Widget _requestCard(Map<String, dynamic> request) {
    final status = (request['status'] ?? '').toString();
    final items = List<Map<String, dynamic>>.from(
      request['stock_variance_items'] ?? [],
    );
    final events = List<Map<String, dynamic>>.from(
      request['stock_variance_events'] ?? [],
    );
    events.sort(
      (a, b) => (a['created_at'] ?? '').toString().compareTo(
        (b['created_at'] ?? '').toString(),
      ),
    );
    final date = DateTime.tryParse((request['submitted_at'] ?? '').toString());
    final requestId = '${request['id'] ?? ''}';
    final actions = _actions(request);
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFE5EAF3)),
      ),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        title: Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '#${requestId.length >= 8 ? requestId.substring(0, 8).toUpperCase() : requestId}',
              style: const TextStyle(
                color: Color(0xFF66758D),
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              StoreBranchIdentityRegistry.displayName(request['branch_name']?.toString()),
              style: const TextStyle(fontWeight: FontWeight.w800, color: _navy),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: _statusColor(status).withValues(alpha: .10),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(
                _label(status),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: _statusColor(status),
                ),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 7),
          child: Text(
            '${items.length} product${items.length == 1 ? '' : 's'}  •  ${request['zone']}  •  ${date == null ? '' : DateFormat('dd MMM yyyy, HH:mm').format(date.toLocal())}',
            style: const TextStyle(color: Color(0xFF6D7890)),
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                Text(
                  'Branch reason: ${request['branch_reason']}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 14),
                for (final item in items)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _background,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Wrap(
                      spacing: 18,
                      runSpacing: 6,
                      children: [
                        SizedBox(
                          width: 260,
                          child: Text(
                            '${item['item_code']} · ${item['item_name']}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        Text(
                          'Batch ${item['batch_number']}  ·  Exp ${item['expiry_date']}',
                        ),
                        Text(
                          'System ${item['system_qty']}  →  Actual ${item['actual_qty']}',
                        ),
                        Text(
                          'Difference ${item['variance']}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color:
                                (num.tryParse('${item['variance']}') ?? 0) < 0
                                ? const Color(0xFFD34B55)
                                : _blue,
                          ),
                        ),
                        Text('Reason: ${item['reason']}'),
                      ],
                    ),
                  ),
                if (events.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Activity',
                    style: TextStyle(fontWeight: FontWeight.w900, color: _navy),
                  ),
                  for (final event in events)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.circle, size: 8, color: _blue),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _label('${event['to_status']}'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: _navy,
                                  ),
                                ),
                                Text(
                                  '${event['actor_name'] ?? ''} · ${_eventDate(event)}',
                                  style: const TextStyle(
                                    color: Color(0xFF8290A5),
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  '${event['note'] ?? ''}',
                                  style: const TextStyle(
                                    color: Color(0xFF59677F),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      for (final action in actions)
                        OutlinedButton(
                          onPressed: () => action.code == 'revise'
                              ? _newRequest(request)
                              : _act(request, action),
                          child: Text(action.label),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _eventDate(Map<String, dynamic> event) {
    final date = DateTime.tryParse('${event['created_at'] ?? ''}');
    return date == null
        ? ''
        : DateFormat('dd MMM yyyy, HH:mm').format(date.toLocal());
  }
}

class _VarianceItemFields {
  _VarianceItemFields([Map<String, dynamic>? data])
    : code = TextEditingController(text: '${data?['item_code'] ?? ''}'),
      name = TextEditingController(text: '${data?['item_name'] ?? ''}'),
      batch = TextEditingController(text: '${data?['batch_number'] ?? ''}'),
      expiry = TextEditingController(text: '${data?['expiry_date'] ?? ''}'),
      system = TextEditingController(text: '${data?['system_qty'] ?? ''}'),
      actual = TextEditingController(text: '${data?['actual_qty'] ?? ''}'),
      reason = TextEditingController(text: '${data?['reason'] ?? ''}');
  final TextEditingController code;
  final TextEditingController name;
  final TextEditingController batch;
  final TextEditingController expiry;
  final TextEditingController system;
  final TextEditingController actual;
  final TextEditingController reason;

  Map<String, dynamic> toJson() => {
    'item_code': code.text.trim(),
    'item_name': name.text.trim(),
    'batch_number': batch.text.trim(),
    'expiry_date': expiry.text.trim(),
    'system_qty': system.text.trim(),
    'actual_qty': actual.text.trim(),
    'reason': reason.text.trim(),
  };
  void dispose() {
    for (final c in [code, name, batch, expiry, system, actual, reason]) {
      c.dispose();
    }
  }
}

class _CreateVarianceDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _CreateVarianceDialog({this.existing});
  @override
  State<_CreateVarianceDialog> createState() => _CreateVarianceDialogState();
}

class _CreateVarianceDialogState extends State<_CreateVarianceDialog> {
  final _reason = TextEditingController();
  final _items = <_VarianceItemFields>[];
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _reason.text = '${existing?['branch_reason'] ?? ''}';
    final rows = List<Map<String, dynamic>>.from(
      existing?['stock_variance_items'] ?? [],
    );
    _items.addAll(
      rows.isEmpty
          ? [_VarianceItemFields()]
          : rows.map((row) => _VarianceItemFields(row)),
    );
  }

  @override
  void dispose() {
    _reason.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final data = _items.map((e) => e.toJson()).toList();
    if (_reason.text.trim().isEmpty ||
        data.any((row) => row.values.any((v) => '$v'.isEmpty))) {
      setState(
        () => _error = 'Complete the request reason and every product field.',
      );
      return;
    }
    for (final row in data) {
      final system = num.tryParse('${row['system_qty']}');
      final actual = num.tryParse('${row['actual_qty']}');
      final date = DateTime.tryParse('${row['expiry_date']}');
      if (system == null ||
          actual == null ||
          system < 0 ||
          actual < 0 ||
          system == actual ||
          date == null) {
        setState(
          () => _error =
              'Enter valid quantities with a difference and a valid expiry date.',
        );
        return;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final existing = widget.existing;
      if (existing == null) {
        await Supabase.instance.client.rpc(
          'create_stock_variance_request',
          params: {'p_reason': _reason.text.trim(), 'p_items': data},
        );
      } else {
        await Supabase.instance.client.rpc(
          'revise_stock_variance_request',
          params: {
            'p_request_id': existing['id'],
            'p_reason': _reason.text.trim(),
            'p_items': data,
          },
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool number = false,
    bool date = false,
  }) => SizedBox(
    width: 190,
    child: TextField(
      controller: controller,
      readOnly: date,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : null,
      onTap: date
          ? () async {
              final selected = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (selected != null) {
                controller.text = DateFormat('yyyy-MM-dd').format(selected);
              }
            }
          : null,
      decoration: InputDecoration(
        labelText: '$label *',
        border: const OutlineInputBorder(),
        suffixIcon: date
            ? const Icon(Icons.calendar_today_outlined, size: 18)
            : null,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Dialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 820, maxHeight: 760),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.existing == null
                  ? 'New stock variance'
                  : 'Revise stock variance',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 5),
            const Text(
              'Confirm the count before sending. Add every affected batch as a separate row.',
              style: TextStyle(color: Color(0xFF66758D)),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: ListView(
                children: [
                  TextField(
                    controller: _reason,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Overall reason *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (var i = 0; i < _items.length; i++)
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F7FC),
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Product ${i + 1}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const Spacer(),
                              if (_items.length > 1)
                                IconButton(
                                  tooltip: 'Remove product',
                                  onPressed: () => setState(() {
                                    final removed = _items.removeAt(i);
                                    WidgetsBinding.instance
                                        .addPostFrameCallback(
                                          (_) => removed.dispose(),
                                        );
                                  }),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 12,
                            children: [
                              _field(_items[i].code, 'Item code'),
                              _field(_items[i].name, 'Item name'),
                              _field(_items[i].batch, 'Batch'),
                              _field(_items[i].expiry, 'Expiry', date: true),
                              _field(
                                _items[i].system,
                                'System qty',
                                number: true,
                              ),
                              _field(
                                _items[i].actual,
                                'Actual qty',
                                number: true,
                              ),
                              _field(_items[i].reason, 'Reason'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  TextButton.icon(
                    onPressed: _items.length >= 50
                        ? null
                        : () =>
                              setState(() => _items.add(_VarianceItemFields())),
                    icon: const Icon(Icons.add),
                    label: const Text('Add another product'),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _saving ? null : _submit,
                  icon: const Icon(Icons.send_rounded),
                  label: Text(
                    _saving
                        ? 'Sending…'
                        : widget.existing == null
                        ? 'Send to Zone'
                        : 'Resubmit to Zone',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
