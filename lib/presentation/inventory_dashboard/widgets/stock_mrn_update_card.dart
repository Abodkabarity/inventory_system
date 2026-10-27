import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Shows the server's last successful import and completed view refresh.
class StockMrnUpdateCard extends StatefulWidget {
  final bool enabled;
  final Future<Map<String, dynamic>?> Function()? loader;
  final VoidCallback? onUpdated;

  const StockMrnUpdateCard({
    super.key,
    this.enabled = true,
    this.loader,
    this.onUpdated,
  });

  @override
  State<StockMrnUpdateCard> createState() => _StockMrnUpdateCardState();
}

class _StockMrnUpdateCardState extends State<StockMrnUpdateCard> {
  Timer? _timer;
  Map<String, dynamic>? _status;
  bool _checking = false, _initialized = false, _unavailable = false;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      _check();
      _timer = Timer.periodic(const Duration(minutes: 1), (_) => _check());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    try {
      final next = widget.loader != null
          ? await widget.loader!()
          : await _fetch();
      if (!mounted) return;
      final changed =
          _initialized &&
          next?['last_success_at'] != null &&
          next?['last_success_at'] != _status?['last_success_at'];
      setState(() {
        _status = next;
        _unavailable = false;
        _initialized = true;
      });
      if (changed) widget.onUpdated?.call();
    } catch (_) {
      if (mounted) setState(() => _unavailable = true);
    } finally {
      _checking = false;
    }
  }

  Future<Map<String, dynamic>?> _fetch() async {
    final value = await Supabase.instance.client.rpc(
      'get_mrn_apg_2026_hourly_status',
    );
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();
    final raw = _status?['last_success_at']?.toString();
    final timestamp = DateTime.tryParse(raw ?? '');
    final dubai = timestamp?.toUtc().add(const Duration(hours: 4));
    final updating = const [
      'downloading',
      'refreshing',
    ].contains(_status?['status']);
    final failed =
        _status?['has_error'] == true || _status?['status'] == 'failed';
    final label = dubai != null
        ? '${DateFormat('dd MMM yyyy · h:mm a').format(dubai)} · Dubai'
        : _unavailable
        ? 'Update time unavailable'
        : !_initialized
        ? 'Checking last update…'
        : 'No successful hourly update yet';
    final detail = _unavailable
        ? 'Unable to check the latest status'
        : updating
        ? 'Updating MRN and Stock Management…'
        : failed
        ? 'Latest attempt failed · last success shown'
        : timestamp != null
        ? 'MRN Overview and Near Expiry updated'
        : 'Hourly updates · 8 AM–5 PM after Purchase';
    final accent = failed || _unavailable
        ? const Color(0xFFB76C06)
        : const Color(0xFF008A83);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: .22)),
        ),
        child: Row(
          children: [
            Icon(Icons.update_rounded, color: accent, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Wrap(
                spacing: 14,
                runSpacing: 3,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'Last MRN update',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                  Text(
                    detail,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            if (updating) ...[
              const SizedBox(width: 12),
              const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
