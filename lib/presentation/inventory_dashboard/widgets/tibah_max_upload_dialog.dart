import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/store_branch_identity_registry.dart';
import '../../../core/utils/tibah_max_import.dart';
import '../../../data/datasources/remote/tibah_order_remote_ds.dart';
import '../../../domain/entities/tibah_order.dart';

class TibahMaxUploadDialog extends StatefulWidget {
  const TibahMaxUploadDialog({super.key, required this.type});
  final TibahOrderType type;

  @override
  State<TibahMaxUploadDialog> createState() => _TibahMaxUploadDialogState();
}

class _TibahMaxUploadDialogState extends State<TibahMaxUploadDialog> {
  bool _busy = false;
  bool _saved = false;
  bool _changed = false;
  double? _progress;
  String? _message;
  String? _error;

  Future<void> _upload() async {
    setState(() {
      _busy = true;
      _error = null;
      _message = 'Choose a CSV or XLSX file...';
    });
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx'],
        withData: true,
      );
      if (picked == null) return;
      final file = picked.files.single;
      if (!mounted) return;
      setState(() {
        _changed = true;
        _message = 'Clearing previous Max and Store request...';
      });
      var rowCount = 0;
      await TibahOrderRemoteDs(Supabase.instance.client).replaceFromFile(
        type: widget.type,
        fileName: file.name,
        onCleared: () {
          if (mounted) {
            setState(
              () => _message = 'Previous Max cleared. Checking the new file...',
            );
          }
        },
        readRows: () async {
          if (file.bytes == null) {
            throw const FormatException(
              'Could not read the file. Previous Max has been cleared.',
            );
          }
          final rows = await parseTibahMaxFile(
            file.bytes!,
            fileName: file.name,
          );
          rowCount = rows.length;
          if (mounted) {
            setState(() {
              _progress = 0;
              _message = 'Uploading $rowCount products...';
            });
          }
          return rows;
        },
        onProgress: (done, total) {
          if (mounted) setState(() => _progress = done / total);
        },
      );
      if (!mounted) return;
      setState(() {
        _saved = true;
        _message =
            '$rowCount products saved as ${widget.type.label}. '
            '${StoreBranchIdentityRegistry.displayName(widget.type.branchTitle)} is now visible in Store. Printing becomes available after the next order calculation.';
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error =
              '$error\nIf the connection stopped during saving, refresh Max before starting another upload.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      backgroundColor: Colors.white,
      title: ValueListenableBuilder<Map<String, String>>(
        valueListenable: StoreBranchIdentityRegistry.groups,
        builder: (_, groups, child) => Text(
          '${StoreBranchIdentityRegistry.displayName(widget.type.branchTitle, groups)} — Max',
        ),
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Use three columns: Item Code, Item Name and Qty. Current Demand is always 0 and Adjustment Type is always INCREASE. Keep Item Code as text in Excel.',
              ),
              const SizedBox(height: 12),
              Text(
                'After choosing a file, previous Max and the Store request for ${StoreBranchIdentityRegistry.displayName(widget.type.branchTitle)} are cleared before checking the file. They stay cleared if checking or uploading fails. The other branches keep their records.',
              ),
              if (_busy) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(value: _progress),
              ],
              if (_message != null) ...[
                const SizedBox(height: 14),
                Text(_message!),
              ],
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(_error!, style: const TextStyle(color: Color(0xFF9F1239))),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: Colors.black),
          onPressed: _busy
              ? null
              : () => Navigator.pop(context, _saved || _changed),
          child: const Text('Close'),
        ),
        if (!_saved)
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6D28D9),
              foregroundColor: Colors.white,
            ),
            onPressed: _busy ? null : _upload,
            icon: const Icon(Icons.upload_file),
            label: const Text('Choose file and replace'),
          ),
      ],
    ),
  );
}
