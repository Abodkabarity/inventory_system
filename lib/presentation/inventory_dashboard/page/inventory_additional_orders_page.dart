import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import 'package:uuid/uuid.dart';
import 'package:xml/xml.dart';
import '../../../core/theme/app_colors.dart';

class InventoryAdditionalOrdersPage extends StatefulWidget {
  const InventoryAdditionalOrdersPage({super.key});

  @override
  State<InventoryAdditionalOrdersPage> createState() =>
      _InventoryAdditionalOrdersPageState();
}

class _InventoryAdditionalOrdersPageState
    extends State<InventoryAdditionalOrdersPage> {
  final _client = Supabase.instance.client;
  final _title = TextEditingController(text: 'Inventory Additional Order');
  final _branches = <String>[];
  final _lines = <_InventoryAdditionalLine>[];
  final _groups = <_InventoryAdditionalGroup>[];
  String? _selectedGroupId;
  String? _editingGroupId;
  bool _loading = true;
  bool _groupsLoading = false;
  bool _sending = false;
  bool _importing = false;
  bool _exporting = false;
  bool _deleting = false;
  String _message = '';
  String _error = '';

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    await Future.wait([_loadBranches(), _loadGroups()]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadBranches() async {
    try {
      final rows = await _client
          .from('branches')
          .select('branch_name')
          .eq('is_active', true)
          .order('branch_name');
      if (!mounted) return;
      setState(() {
        _branches
          ..clear()
          ..addAll(
            List<Map<String, dynamic>>.from(rows)
                .map((e) => (e['branch_name'] ?? '').toString().trim())
                .where((e) => e.isNotEmpty)
                .toList()
              ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
          );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load branches: $e';
      });
    }
  }

  Future<void> _loadGroups() async {
    if (mounted) setState(() => _groupsLoading = true);
    try {
      final rows = await _client
          .from('additional_order_inventory')
          .select(
            'id,request_group_id,branch_name,item_code,item_name,request_qty,inventory_qty,fulfilled_qty,status,inventory_note,created_at,updated_at',
          )
          .order('created_at', ascending: false);
      final byId = <String, _InventoryAdditionalGroup>{};
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final groupId = (row['request_group_id'] ?? '').toString();
        if (groupId.isEmpty) continue;
        (byId[groupId] ??= _InventoryAdditionalGroup(id: groupId)).add(row);
      }
      final groups = byId.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!mounted) return;
      setState(() {
        _groups
          ..clear()
          ..addAll(groups);
        _selectedGroupId ??= groups.isEmpty ? null : groups.first.id;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not load sent additional orders: $e');
      }
    } finally {
      if (mounted) setState(() => _groupsLoading = false);
    }
  }

  _InventoryAdditionalGroup? get _selectedGroup {
    for (final group in _groups) {
      if (group.id == _selectedGroupId) return group;
    }
    return null;
  }

  Future<void> _pickDestinations(_InventoryAdditionalLine line) async {
    final picked = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _BranchPickerDialog(
        branches: _branches,
        selected: line.destinations,
        title: 'Choose destinations',
        subtitle: line.itemName,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => line.setDestinations(picked));
  }

  Future<void> _pickProducts() async {
    final additions = await showDialog<List<_InventoryAdditionalLine>>(
      context: context,
      builder: (_) => _ProductPickerDialog(client: _client),
    );
    if (additions == null || additions.isEmpty || !mounted) return;
    setState(() {
      for (final line in additions) {
        final existing = _lines.indexWhere(
          (e) =>
              e.itemCode == line.itemCode &&
              _sameDestinations(e.destinations, line.destinations),
        );
        if (existing >= 0) {
          _lines[existing].qtyController.text = line.qtyController.text;
          line.dispose();
        } else {
          _lines.add(line);
        }
      }
    });
  }

  Future<void> _import() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'xlsx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      setState(() => _error = 'Could not read the selected file.');
      return;
    }

    setState(() {
      _importing = true;
      _error = '';
      _message = '';
    });
    await Future<void>.delayed(Duration.zero);
    try {
      final ext = (file.extension ?? '').toLowerCase();
      final table = ext == 'csv' ? _readCsv(bytes) : _readXlsx(bytes);
      final rows = _parseImportedRows(table);
      if (rows.isEmpty) {
        throw Exception(
          'No valid rows found. Required columns: item_code, item_name, qty. Optional: branch.',
        );
      }
      if (!mounted) return;
      setState(() {
        for (final imported in rows) {
          final index = _lines.indexWhere(
            (e) =>
                e.itemCode == imported.itemCode &&
                _sameDestinations(e.destinations, imported.destinations),
          );
          if (index >= 0) {
            _lines[index].qtyController.text = imported.qtyController.text;
            imported.dispose();
          } else {
            _lines.add(imported);
          }
        }
        final unassigned = rows.where((row) => row.destinations.isEmpty).length;
        _message = unassigned == 0
            ? '${rows.length} item(s) imported with their destinations.'
            : '${rows.length} item(s) imported. Assign destinations to $unassigned item(s) before sending.';
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Import failed: $e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _send() async {
    final lines = _lines.where((e) => e.qty > 0).toList();
    if (lines.isEmpty) {
      setState(
        () =>
            _error = 'Add at least one item with a quantity greater than zero.',
      );
      return;
    }
    final unresolved = lines
        .where((line) => line.destinations.isEmpty)
        .toList();
    if (unresolved.isNotEmpty) {
      setState(
        () => _error =
            'Choose at least one destination for every product before sending.',
      );
      return;
    }
    final invalidBranches = lines
        .expand((line) => line.destinations)
        .where((branch) => !_branches.contains(branch))
        .toSet();
    if (invalidBranches.isNotEmpty) {
      setState(
        () => _error =
            'The imported file contains unknown branch names: ${invalidBranches.join(', ')}.',
      );
      return;
    }

    setState(() {
      _sending = true;
      _error = '';
      _message = '';
    });
    try {
      final itemMetadata = await _loadItemMetadata(
        lines.map((line) => line.itemCode),
      );
      const chunkSize = 300;
      final groupId = _editingGroupId ?? const Uuid().v4();
      final today = DateTime.now();
      final date =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final payload = <Map<String, dynamic>>[];
      for (final line in lines) {
        final metadata = itemMetadata[line.itemCode] ?? const {};
        for (final branch in line.destinations) {
          payload.add({
            'request_group_id': groupId,
            'run_date': date,
            'branch_name': branch,
            'item_code': line.itemCode,
            'item_name': line.itemName,
            'request_qty': line.qty,
            'inventory_qty': line.qty,
            'inventory_note': _title.text.trim(),
            'status': 'sent_to_store',
            'source': 'inventory',
            'store_item_classifications': _storeClassification(metadata),
            'supplier': metadata['supplier'],
            'barcode': metadata['barcode'],
            'category': metadata['category'],
          });
        }
      }
      if (_editingGroupId != null) {
        await _client
            .from('additional_order_inventory')
            .delete()
            .eq('request_group_id', _editingGroupId!)
            .eq('status', 'sent_to_store');
      }
      for (var i = 0; i < payload.length; i += chunkSize) {
        await _client
            .from('additional_order_inventory')
            .insert(
              payload.sublist(i, (i + chunkSize).clamp(0, payload.length)),
            );
      }
      if (!mounted) return;
      setState(() {
        for (final line in _lines) {
          line.dispose();
        }
        _lines.clear();
        _editingGroupId = null;
        _message =
            'Sent ${payload.length} inventory additional order item(s) to Store.';
      });
      await _loadGroups();
      if (mounted) setState(() => _selectedGroupId = groupId);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not send additional orders: $e');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<Map<String, Map<String, dynamic>>> _loadItemMetadata(
    Iterable<String> itemCodes,
  ) async {
    final codes = itemCodes
        .map((code) => code.trim())
        .where((code) => code.isNotEmpty)
        .toSet()
        .toList();
    final result = <String, Map<String, dynamic>>{};

    const batchSize = 250;
    for (var index = 0; index < codes.length; index += batchSize) {
      final end = (index + batchSize).clamp(0, codes.length);
      final rows = await _client
          .from('item_report')
          // Item report schemas differ between older installations. Fetch the
          // available row rather than making a missing optional column block
          // the entire inventory additional order.
          .select()
          .inFilter('item_code', codes.sublist(index, end));

      for (final raw in List<Map<String, dynamic>>.from(rows)) {
        final code = (raw['item_code'] ?? '').toString().trim();
        if (code.isEmpty) continue;
        result.putIfAbsent(code, () => raw);
      }
    }
    return result;
  }

  String? _storeClassification(Map<String, dynamic> metadata) {
    for (final key in const [
      'store_item_classifications',
      'store_item_classification',
      'store_classification',
    ]) {
      final value = metadata[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  bool _sameDestinations(Set<String> first, Set<String> second) =>
      first.length == second.length && first.containsAll(second);

  Future<void> _editGroup(_InventoryAdditionalGroup group) async {
    if (!group.canEdit) {
      setState(() => _error = 'Only orders still sent to Store can be edited.');
      return;
    }
    setState(() {
      for (final line in _lines) {
        line.dispose();
      }
      _lines
        ..clear()
        ..addAll(
          group.rows.map(
            (row) => _InventoryAdditionalLine(
              itemCode: row.itemCode,
              itemName: row.itemName,
              qty: row.requestQty.toString(),
              branch: row.branch,
            ),
          ),
        );
      _title.text = group.note;
      _editingGroupId = group.id;
      _message =
          'Editing ${group.title}. Update the items, then send changes to Store.';
      _error = '';
    });
  }

  Future<void> _deleteGroup(_InventoryAdditionalGroup group) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete additional order?'),
        content: Text(
          'This will permanently remove ${group.totalItems} item(s) from "${group.title}". Store will no longer see this order.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete order'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await _client
          .from('additional_order_inventory')
          .delete()
          .eq('request_group_id', group.id);
      if (!mounted) return;
      setState(() {
        if (_selectedGroupId == group.id) _selectedGroupId = null;
        _message = 'Additional order deleted.';
      });
      await _loadGroups();
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not delete the additional order: $e');
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _exportDraft() async {
    if (_lines.isEmpty) {
      setState(() => _error = 'There are no items to export.');
      return;
    }
    setState(() => _exporting = true);
    await Future<void>.delayed(Duration.zero);
    try {
      final workbook = xlsio.Workbook();
      final sheet = workbook.worksheets[0]
        ..name = 'Inventory Additional Orders';
      const headers = [
        'Branch',
        'Item Code',
        'Item Name',
        'Quantity',
        'Order Note',
      ];
      for (var column = 0; column < headers.length; column++) {
        final cell = sheet.getRangeByIndex(1, column + 1);
        cell.setText(headers[column]);
        cell.cellStyle.bold = true;
        cell.cellStyle.backColor = '#DCEBFF';
      }
      var rowIndex = 2;
      for (final line in _lines) {
        final branches = line.destinations.isEmpty
            ? {'Destination required'}
            : line.destinations;
        for (final branch in branches) {
          final values = [
            branch,
            line.itemCode,
            line.itemName,
            line.qty,
            _title.text.trim(),
          ];
          for (var column = 0; column < values.length; column++) {
            final cell = sheet.getRangeByIndex(rowIndex, column + 1);
            final value = values[column];
            if (value is num) {
              cell.setNumber(value.toDouble());
            } else {
              cell.setText(value.toString());
            }
          }
          rowIndex++;
        }
      }
      sheet
          .getRangeByIndex(1, 1, rowIndex - 1, headers.length)
          .autoFitColumns();
      final bytes = workbook.saveAsStream();
      workbook.dispose();
      final blob = html.Blob([
        Uint8List.fromList(bytes),
      ], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..download = 'Inventory_Additional_Orders.xlsx'
        ..click();
      html.Url.revokeObjectUrl(url);
    } catch (e) {
      if (mounted) setState(() => _error = 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ColoredBox(
        color: AppColors.bg,
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primaryColor),
        ),
      );
    }
    return ColoredBox(
      color: AppColors.bg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
        child: Column(
          children: [
            _hero(),
            const SizedBox(height: 16),
            _composer(),
            const SizedBox(height: 16),
            Expanded(
              child: Row(
                children: [
                  SizedBox(width: 320, child: _sentOrdersPanel()),
                  const SizedBox(width: 16),
                  Expanded(child: _draftTable()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero() => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
    decoration: BoxDecoration(
      color: AppColors.primaryColor,
      borderRadius: BorderRadius.circular(12),
      boxShadow: const [
        BoxShadow(
          color: Color(0x334EB0DE),
          blurRadius: 20,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.outbox_rounded,
            color: Colors.white,
            size: 28,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Additional Orders',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Build one delivery, with the right destination for every product.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        _heroMetric(
          '${_lines.expand((line) => line.destinations).toSet().length}',
          'Destinations',
        ),
        const SizedBox(width: 10),
        _heroMetric('${_lines.length}', 'Items'),
      ],
    ),
  );

  Widget _heroMetric(String value, String label) => Container(
    constraints: const BoxConstraints(minWidth: 88),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.17),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
    ),
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.88),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  Widget _composer() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppColors.card,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _editingGroupId == null
                        ? 'Prepare delivery'
                        : 'Update delivery',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.secondaryColor,
                    ),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'Add products first, then assign the exact branches for each product.',
                    style: TextStyle(color: AppColors.subText),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: _importing ? null : _import,
              icon: _importing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file_rounded),
              label: Text(_importing ? 'Importing...' : 'Import CSV / XLSX'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.secondaryColor,
                side: const BorderSide(color: AppColors.secondaryColor),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: _exporting ? null : _exportDraft,
              icon: _exporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_rounded),
              label: Text(_exporting ? 'Exporting...' : 'Export'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.secondaryColor,
                side: const BorderSide(color: AppColors.secondaryColor),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(
                _sending
                    ? 'Saving...'
                    : _editingGroupId == null
                    ? 'Send to Store'
                    : 'Update order',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: _title,
                decoration: InputDecoration(
                  labelText: 'Order note',
                  hintText: 'Optional note for Store',
                  filled: true,
                  fillColor: AppColors.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: AppColors.primaryColor,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              height: 56,
              child: FilledButton.icon(
                onPressed: _pickProducts,
                icon: const Icon(Icons.add_box_rounded),
                label: const Text('1. Add products'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                ),
              ),
            ),
          ],
        ),
        if (_message.isNotEmpty || _error.isNotEmpty) ...[
          const SizedBox(height: 12),
          _notice(_error.isNotEmpty ? _error : _message, _error.isNotEmpty),
        ],
        const SizedBox(height: 8),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '2. Set destinations beside each product. Imports can assign a branch per row using the optional branch column.',
            style: TextStyle(color: AppColors.subText, fontSize: 12),
          ),
        ),
        /*
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '2. Use “Set destinations” beside each product. Import supports item_code, item_name, qty, and optional branch.',
            style: TextStyle(color: AppColors.subText, fontSize: 12),
          ),
        ),
        */
      ],
    ),
  );

  Widget _notice(String message, bool error) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: error ? Colors.red.shade50 : Colors.green.shade50,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      message,
      style: TextStyle(
        color: error ? Colors.red.shade800 : Colors.green.shade800,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _sentOrdersPanel() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.card,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.outbox_rounded, color: AppColors.primaryColor),
            SizedBox(width: 8),
            Text(
              'Sent additional orders',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.secondaryColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${_groups.length} order${_groups.length == 1 ? '' : 's'} saved',
          style: const TextStyle(color: AppColors.subText, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _groupsLoading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primaryColor,
                  ),
                )
              : _groups.isEmpty
              ? const Center(
                  child: Text(
                    'No additional orders sent yet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.subText),
                  ),
                )
              : ListView.separated(
                  itemCount: _groups.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, index) => _groupCard(_groups[index]),
                ),
        ),
      ],
    ),
  );

  Widget _groupCard(_InventoryAdditionalGroup group) {
    final selected = group.id == _selectedGroupId;
    final color = group.statusColor;
    return Material(
      color: selected ? AppColors.blueSoft : AppColors.bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _selectedGroupId = group.id),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.primaryColor : AppColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      group.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                '${group.branchCount} branches  |  ${group.totalItems} items',
                style: const TextStyle(
                  color: AppColors.subText,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _statusChip(
                    'Sent ${group.sentCount}',
                    AppColors.primaryColor,
                  ),
                  _statusChip(
                    'Done ${group.doneCount}',
                    const Color(0xFF16A34A),
                  ),
                  _statusChip(
                    'Rejected ${group.rejectedCount}',
                    const Color(0xFFDC2626),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.secondaryColor,
                        side: const BorderSide(color: AppColors.secondaryColor),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onPressed: group.canEdit ? () => _editGroup(group) : null,
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Edit'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Delete order',
                    onPressed: _deleting || !group.canEdit
                        ? null
                        : () => _deleteGroup(group),
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: Color(0xFFDC2626),
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

  Widget _statusChip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800),
    ),
  );

  String _destinationsForLine(_InventoryAdditionalLine line) {
    final branches = line.destinations.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (branches.isEmpty) return 'Destination required';
    if (branches.length <= 2) return branches.join(', ');
    return '${branches.take(2).join(', ')} +${branches.length - 2} more';
  }

  String _destinationTooltip(_InventoryAdditionalLine line) {
    if (line.destinations.isEmpty) {
      return 'Choose one or more branches for this product.';
    }
    final branches = line.destinations.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return branches.join(', ');
  }

  Widget _draftTable() => Container(
    decoration: BoxDecoration(
      color: AppColors.card,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(12),
    ),
    clipBehavior: Clip.antiAlias,
    child: _lines.isEmpty
        ? (_selectedGroup == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppColors.blueSoft,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.playlist_add_rounded,
                          size: 34,
                          color: AppColors.primaryColor,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Start with the products',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColors.secondaryColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Add products or import a file, then set the destination for each product.',
                        style: TextStyle(color: AppColors.subText),
                      ),
                    ],
                  ),
                )
              : _groupDetails(_selectedGroup!))
        : Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                color: AppColors.headerBg,
                child: const Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        'Item code',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.headerText,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 5,
                      child: Text(
                        'Item name',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.headerText,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        'Destinations',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.headerText,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 150,
                      child: Text(
                        'Quantity',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.headerText,
                        ),
                      ),
                    ),
                    SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _lines.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, index) {
                    final item = _lines[index];
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.bg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.inventory_2_outlined,
                            color: AppColors.primaryColor,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: SelectableText(
                              item.itemCode,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 5,
                            child: SelectableText(
                              item.itemName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Tooltip(
                              message: _destinationTooltip(item),
                              child: OutlinedButton.icon(
                                onPressed: () => _pickDestinations(item),
                                icon: Icon(
                                  item.destinations.isEmpty
                                      ? Icons.add_location_alt_outlined
                                      : Icons.storefront_rounded,
                                  size: 17,
                                ),
                                label: Text(
                                  _destinationsForLine(item),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: item.destinations.isEmpty
                                      ? const Color(0xFFDC2626)
                                      : AppColors.primaryColor,
                                  side: BorderSide(
                                    color: item.destinations.isEmpty
                                        ? const Color(0xFFFCA5A5)
                                        : AppColors.primaryColor,
                                  ),
                                  alignment: Alignment.centerLeft,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 150,
                            child: TextField(
                              controller: item.qtyController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText: 'Quantity',
                                isDense: true,
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: AppColors.primaryColor,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove item',
                            onPressed: () => setState(() {
                              item.dispose();
                              _lines.removeAt(index);
                            }),
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
  );

  Widget _groupDetails(_InventoryAdditionalGroup group) => Column(
    children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        color: AppColors.headerBg,
        child: Row(
          children: [
            const Icon(
              Icons.receipt_long_rounded,
              color: AppColors.primaryColor,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                group.title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.headerText,
                ),
              ),
            ),
            Text(
              '${group.totalItems} items',
              style: const TextStyle(
                color: AppColors.subText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      Expanded(
        child: ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: group.rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, index) {
            final row = group.rows[index];
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.blueSoft,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(
                      Icons.inventory_2_outlined,
                      color: AppColors.primaryColor,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: SelectableText(
                      row.branch,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: SelectableText(
                      row.itemCode,
                      style: const TextStyle(color: AppColors.subText),
                    ),
                  ),
                  Expanded(
                    flex: 5,
                    child: SelectableText(
                      row.itemName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  SizedBox(
                    width: 90,
                    child: Text(
                      '${row.requestQty}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _statusChip(row.statusLabel, row.statusColor),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ],
  );
}

class _InventoryAdditionalLine {
  final String itemCode;
  final String itemName;
  final Set<String> destinations;
  final TextEditingController qtyController;
  _InventoryAdditionalLine({
    required this.itemCode,
    required this.itemName,
    required String qty,
    String branch = '',
    Set<String>? destinations,
  }) : destinations = {
         if (branch.trim().isNotEmpty) branch.trim(),
         ...?destinations,
       },
       qtyController = TextEditingController(text: qty);
  num get qty => num.tryParse(qtyController.text.trim()) ?? 0;
  void setDestinations(Set<String> values) {
    destinations
      ..clear()
      ..addAll(
        values.map((value) => value.trim()).where((value) => value.isNotEmpty),
      );
  }

  void dispose() => qtyController.dispose();
}

class _InventoryAdditionalGroup {
  _InventoryAdditionalGroup({required this.id});

  final String id;
  final List<_InventoryAdditionalGroupRow> rows = [];

  void add(Map<String, dynamic> row) =>
      rows.add(_InventoryAdditionalGroupRow.fromMap(row));

  DateTime get createdAt => rows.isEmpty
      ? DateTime.fromMillisecondsSinceEpoch(0)
      : DateTime.tryParse(rows.first.createdAt) ??
            DateTime.fromMillisecondsSinceEpoch(0);
  String get note => rows.isEmpty ? '' : rows.first.note;
  String get title => note.isEmpty ? 'Inventory additional order' : note;
  Set<String> get branches => rows.map((e) => e.branch).toSet();
  int get branchCount => branches.length;
  int get totalItems => rows.length;
  int get sentCount => rows.where((e) => e.status == 'sent_to_store').length;
  int get doneCount => rows.where((e) => e.status == 'done').length;
  int get rejectedCount => rows.where((e) => e.status == 'rejected').length;
  bool get canEdit => rows.isNotEmpty && sentCount == rows.length;
  Color get statusColor => rejectedCount > 0
      ? const Color(0xFFDC2626)
      : sentCount > 0
      ? AppColors.primaryColor
      : const Color(0xFF16A34A);
}

class _InventoryAdditionalGroupRow {
  _InventoryAdditionalGroupRow({
    required this.branch,
    required this.itemCode,
    required this.itemName,
    required this.requestQty,
    required this.status,
    required this.note,
    required this.createdAt,
  });

  factory _InventoryAdditionalGroupRow.fromMap(Map<String, dynamic> row) =>
      _InventoryAdditionalGroupRow(
        branch: (row['branch_name'] ?? '').toString(),
        itemCode: (row['item_code'] ?? '').toString(),
        itemName: (row['item_name'] ?? '').toString(),
        requestQty: (row['request_qty'] as num?)?.toDouble() ?? 0,
        status: (row['status'] ?? 'sent_to_store').toString(),
        note: (row['inventory_note'] ?? '').toString(),
        createdAt: (row['created_at'] ?? '').toString(),
      );

  final String branch;
  final String itemCode;
  final String itemName;
  final double requestQty;
  final String status;
  final String note;
  final String createdAt;

  String get statusLabel {
    switch (status) {
      case 'done':
        return 'Done';
      case 'rejected':
        return 'Rejected';
      default:
        return 'Sent to Store';
    }
  }

  Color get statusColor {
    switch (status) {
      case 'done':
        return const Color(0xFF16A34A);
      case 'rejected':
        return const Color(0xFFDC2626);
      default:
        return AppColors.primaryColor;
    }
  }
}

class _BranchPickerDialog extends StatefulWidget {
  final List<String> branches;
  final Set<String> selected;
  final String title;
  final String? subtitle;
  const _BranchPickerDialog({
    required this.branches,
    required this.selected,
    this.title = 'Select Destinations',
    this.subtitle,
  });
  @override
  State<_BranchPickerDialog> createState() => _BranchPickerDialogState();
}

class _BranchPickerDialogState extends State<_BranchPickerDialog> {
  final _search = TextEditingController();
  late final Set<String> _selected = {...widget.selected};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.toLowerCase();
    final visible =
        widget.branches.where((e) => e.toLowerCase().contains(query)).toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .16),
              blurRadius: 30,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppColors.blueSoft,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    Icons.storefront_rounded,
                    color: AppColors.primaryColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        widget.subtitle ??
                            '${_selected.length} of ${widget.branches.length} selected',
                        style: const TextStyle(
                          color: AppColors.subText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Close',
                ),
              ],
            ),
            const SizedBox(height: 14),
            Padding(
              padding: EdgeInsets.zero,
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: AppColors.primaryColor,
                  ),
                  hintText: 'Search branches',
                  filled: true,
                  fillColor: AppColors.backgroundWidget,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.primaryColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.primaryColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: AppColors.primaryColor,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.secondaryColor,
                      side: const BorderSide(color: AppColors.secondaryColor),
                    ),
                    onPressed: () => setState(
                      () => _selected
                        ..clear()
                        ..addAll(widget.branches),
                    ),
                    icon: const Icon(Icons.done_all_rounded),
                    label: const Text('Select All'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.secondaryColor,
                      side: const BorderSide(color: AppColors.secondaryColor),
                    ),
                    onPressed: () => setState(_selected.clear),
                    icon: const Icon(Icons.clear_all_rounded),
                    label: const Text('Clear'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Material(
                color: const Color(0xFFF8FAFC),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: AppColors.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (_, i) {
                    final branch = visible[i];
                    final checked = _selected.contains(branch);
                    return CheckboxListTile(
                      value: checked,
                      activeColor: AppColors.primaryColor,
                      controlAffinity: ListTileControlAffinity.leading,
                      secondary: const Icon(
                        Icons.storefront_rounded,
                        color: AppColors.primaryColor,
                      ),
                      title: Text(
                        branch,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      onChanged: (value) => setState(
                        () => value == true
                            ? _selected.add(branch)
                            : _selected.remove(branch),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        color: AppColors.secondaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryColor,
                    ),
                    onPressed: () => Navigator.pop(context, _selected),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductPickerDialog extends StatefulWidget {
  final SupabaseClient client;
  const _ProductPickerDialog({required this.client});
  @override
  State<_ProductPickerDialog> createState() => _ProductPickerDialogState();
}

class _ProductPickerDialogState extends State<_ProductPickerDialog> {
  final _search = TextEditingController();
  final _selected = <String, Map<String, dynamic>>{};
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _lookup(String value) async {
    if (value.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    setState(() => _loading = true);
    try {
      final rows = await widget.client
          .from('item_report')
          .select('item_code,item_name')
          .or(
            'item_code.ilike.%${value.trim()}%,item_name.ilike.%${value.trim()}%',
          )
          .limit(80);
      if (mounted) {
        setState(() => _results = List<Map<String, dynamic>>.from(rows));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    insetPadding: const EdgeInsets.all(24),
    child: Container(
      constraints: const BoxConstraints(maxWidth: 680, maxHeight: 680),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .16),
            blurRadius: 32,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.blueSoft,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.add_box_rounded,
                  color: AppColors.primaryColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Choose Items',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${_selected.length} item(s) selected',
                      style: const TextStyle(
                        color: AppColors.subText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Close',
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _search,
            onChanged: _lookup,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: AppColors.primaryColor,
                          strokeWidth: 2,
                        ),
                      ),
                    )
                  : null,
              hintText: 'Search item code or item name...',
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              itemCount: _results.length,
              itemBuilder: (_, i) {
                final row = _results[i];
                final code = (row['item_code'] ?? '').toString();
                final selected = _selected.containsKey(code);
                return Material(
                  color: selected ? AppColors.blueSoft : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  child: CheckboxListTile(
                    activeColor: AppColors.primaryColor,
                    value: selected,
                    title: Text(
                      (row['item_name'] ?? '').toString(),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      code,
                      style: const TextStyle(color: AppColors.subText),
                    ),
                    onChanged: (value) => setState(
                      () => value == true
                          ? _selected[code] = row
                          : _selected.remove(code),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      color: AppColors.secondaryColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryColor,
                  ),
                  onPressed: () => Navigator.pop(
                    context,
                    _selected.values
                        .map(
                          (row) => _InventoryAdditionalLine(
                            itemCode: (row['item_code'] ?? '').toString(),
                            itemName: (row['item_name'] ?? '').toString(),
                            qty: '1',
                          ),
                        )
                        .toList(),
                  ),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(
                    'Add ${_selected.length} product${_selected.length == 1 ? '' : 's'}',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

List<List<dynamic>> _readCsv(Uint8List bytes) {
  try {
    return const CsvToListConverter().convert(utf8.decode(bytes));
  } catch (_) {
    return const CsvToListConverter().convert(latin1.decode(bytes));
  }
}

List<_InventoryAdditionalLine> _parseImportedRows(List<List<dynamic>> table) {
  if (table.isEmpty) return [];
  final headers = table.first
      .map(
        (e) => e.toString().trim().toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9]'),
          '',
        ),
      )
      .toList();
  int indexOf(List<String> names) => headers.indexWhere(names.contains);
  final codeIndex = indexOf(const ['itemcode', 'code']);
  final nameIndex = indexOf(const ['itemname', 'name']);
  final qtyIndex = indexOf(const ['qty', 'quantity', 'requestqty']);
  final branchIndex = indexOf(const ['branch', 'branchname']);
  if (codeIndex < 0 || nameIndex < 0 || qtyIndex < 0) {
    throw Exception('Missing item_code, item_name, or qty column.');
  }
  final result = <_InventoryAdditionalLine>[];
  for (final row in table.skip(1)) {
    String at(int index) =>
        index >= 0 && index < row.length ? row[index].toString().trim() : '';
    final code = at(codeIndex);
    final name = at(nameIndex);
    final qty = at(qtyIndex);
    if (code.isEmpty || name.isEmpty || (num.tryParse(qty) ?? 0) <= 0) continue;
    result.add(
      _InventoryAdditionalLine(
        itemCode: code,
        itemName: name,
        qty: qty,
        branch: at(branchIndex),
      ),
    );
  }
  return result;
}

List<List<dynamic>> _readXlsx(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  String read(String path) {
    final file = archive.findFile(path);
    return file == null ? '' : utf8.decode(file.content);
  }

  final strings = <String>[];
  final shared = read('xl/sharedStrings.xml');
  if (shared.isNotEmpty) {
    for (final node in XmlDocument.parse(shared).findAllElements('si')) {
      strings.add(node.findAllElements('t').map((e) => e.innerText).join());
    }
  }
  final xml = read('xl/worksheets/sheet1.xml');
  if (xml.isEmpty) throw Exception('Could not read the first worksheet.');
  final result = <List<dynamic>>[];
  for (final row in XmlDocument.parse(xml).findAllElements('row')) {
    final values = <int, String>{};
    var max = -1;
    for (final cell in row.findElements('c')) {
      final index = _xlsxIndex(cell.getAttribute('r') ?? '');
      if (index < 0) continue;
      max = index > max ? index : max;
      var value =
          cell.findElements('v').firstOrNull?.innerText ??
          cell.findAllElements('t').map((e) => e.innerText).join();
      if (cell.getAttribute('t') == 's') {
        final i = int.tryParse(value) ?? -1;
        value = i >= 0 && i < strings.length ? strings[i] : '';
      }
      values[index] = value;
    }
    if (max >= 0) result.add(List.generate(max + 1, (i) => values[i] ?? ''));
  }
  return result;
}

int _xlsxIndex(String reference) {
  final letters = RegExp(r'^[A-Za-z]+').firstMatch(reference)?.group(0);
  if (letters == null) return -1;
  var value = 0;
  for (final unit in letters.toUpperCase().codeUnits) {
    value = value * 26 + unit - 64;
  }
  return value - 1;
}
