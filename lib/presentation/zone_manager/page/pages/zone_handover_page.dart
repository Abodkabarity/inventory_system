part of '../zone_manager_page.dart';

enum _ZoneHandoverConfirmAction { decline, cancel }

extension _ZoneHandoverPageView on _ZoneManagerPageState {
  DateTime? _handoverDate(dynamic value) {
    final parsed = DateTime.tryParse(_text(value));
    return parsed?.toLocal();
  }

  String _handoverDisplayStatus(Map<String, dynamic> row) {
    final status = _text(row['status']).toLowerCase();
    final start = _handoverDate(row['start_at']);
    final end = _handoverDate(row['end_at']);
    final now = DateTime.now();
    if ((status == 'accepted' || status == 'pending') &&
        end != null &&
        !now.isBefore(end)) {
      return 'expired';
    }
    if (status == 'accepted' && start != null && now.isBefore(start)) {
      return 'scheduled';
    }
    if (status == 'accepted') return 'active';
    return status;
  }

  List<Map<String, dynamic>> get _incomingPendingHandovers {
    final uid = _client.auth.currentUser?.id ?? '';
    final now = DateTime.now();
    return _zoneDelegations
        .where((row) {
          final end = _handoverDate(row['end_at']);
          return _text(row['recipient_user_id']) == uid &&
              _text(row['status']).toLowerCase() == 'pending' &&
              end != null &&
              end.isAfter(now);
        })
        .toList(growable: false);
  }

  List<Map<String, dynamic>> get _activeIncomingHandovers {
    final uid = _client.auth.currentUser?.id ?? '';
    return _zoneDelegations
        .where((row) {
          final displayStatus = _handoverDisplayStatus(row);
          return _text(row['recipient_user_id']) == uid &&
              (displayStatus == 'active' || displayStatus == 'scheduled');
        })
        .toList(growable: false);
  }

  List<Map<String, dynamic>> get _outgoingDashboardHandovers {
    final uid = _client.auth.currentUser?.id ?? '';
    final now = DateTime.now();
    final rows = _zoneDelegations
        .where((row) {
          if (_text(row['requester_user_id']) != uid) return false;
          final displayStatus = _handoverDisplayStatus(row);
          if (displayStatus == 'active' || displayStatus == 'scheduled') {
            return true;
          }
          final end = _handoverDate(row['end_at']);
          return displayStatus == 'pending' && end != null && end.isAfter(now);
        })
        .toList(growable: false);
    rows.sort((left, right) {
      final leftPending = _handoverDisplayStatus(left) == 'pending';
      final rightPending = _handoverDisplayStatus(right) == 'pending';
      if (leftPending != rightPending) return leftPending ? -1 : 1;
      final leftCreated = _handoverDate(left['created_at']) ?? DateTime(1970);
      final rightCreated = _handoverDate(right['created_at']) ?? DateTime(1970);
      return rightCreated.compareTo(leftCreated);
    });
    return rows;
  }

  Future<bool> _showZoneHandoverConfirmation({
    required _ZoneHandoverConfirmAction action,
    required Map<String, dynamic>? row,
  }) async {
    final isDecline = action == _ZoneHandoverConfirmAction.decline;
    final otherUserId = _text(
      row?[isDecline ? 'requester_user_id' : 'recipient_user_id'],
    );
    final result = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close confirmation',
      barrierColor: const Color(0x990F172A),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (dialogContext, _, _) => _ZoneHandoverConfirmDialog(
        action: action,
        managerName: _zoneManagerName(otherUserId),
        zones: _delegationZones(row?['zones']),
        reason: _text(row?['reason']),
        startAt: _handoverDate(row?['start_at']),
        endAt: _handoverDate(row?['end_at']),
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: .90, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
    return result ?? false;
  }

  Future<void> _showCreateZoneHandover() async {
    if (!_handoverAvailable) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0x660F172A),
      builder: (_) => _ZoneHandoverRequestDialog(
        managers: _zoneManagerDirectory,
        permanentZones: _permanentZones,
        onSubmit: (draft) => _createZoneHandover(
          recipientUserId: draft.recipientUserId,
          zones: draft.zones,
          startAt: draft.startAt,
          endAt: draft.endAt,
          reason: draft.reason,
        ),
      ),
    );
  }

  Widget buildZoneHandoverPage() {
    if (!_handoverAvailable) {
      return _ZoneHandoverSetupRequired(onRetry: _load);
    }
    final active = _activeIncomingHandovers;
    final incoming = _incomingPendingHandovers;
    final rows = List<Map<String, dynamic>>.from(_zoneDelegations)
      ..sort((left, right) {
        final l = _handoverDate(left['created_at']) ?? DateTime(1970);
        final r = _handoverDate(right['created_at']) ?? DateTime(1970);
        return r.compareTo(l);
      });

    return Column(
      children: [
        _ModernPageHero(
          icon: Icons.handshake_outlined,
          eyebrow: 'ZONE COVERAGE CENTER',
          title: 'Zone Handover',
          subtitle:
              'Transfer zone responsibility safely during planned absence.',
          accent: const Color(0xff4F46E5),
          metrics: const [],
          actions: [
            FilledButton.icon(
              onPressed: _handoverBusy ? null : _showCreateZoneHandover,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xff4F46E5),
              ),
              icon: const Icon(Icons.add_rounded, size: 19),
              label: const Text('New Handover Request'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _ReportKpiStrip(
          kpis: [
            _ReportKpi(
              Icons.account_tree_outlined,
              'Permanent Zones',
              '${_permanentZones.length}',
              _permanentZones.join(' • '),
              const Color(0xff4F46E5),
            ),
            _ReportKpi(
              Icons.shield_outlined,
              'Temporary Coverage',
              '${active.length}',
              'Accepted responsibilities',
              const Color(0xff0F9F7F),
            ),
            _ReportKpi(
              Icons.mark_email_unread_outlined,
              'Incoming Requests',
              '${incoming.length}',
              'Waiting for your decision',
              const Color(0xffF59E0B),
            ),
            _ReportKpi(
              Icons.history_rounded,
              'Handover Records',
              '${rows.length}',
              'Complete responsibility trail',
              const Color(0xff0EA5E9),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1050;
              final coverage = _ZoneCoverageOverview(
                permanentZones: _permanentZones,
                activeRows: active,
                managerName: _zoneManagerName,
                zonesOf: _delegationZones,
                dateOf: _handoverDate,
              );
              final history = _ZoneHandoverHistory(
                rows: rows,
                currentUserId: _client.auth.currentUser?.id ?? '',
                managerName: _zoneManagerName,
                zonesOf: _delegationZones,
                dateOf: _handoverDate,
                statusOf: _handoverDisplayStatus,
                busy: _handoverBusy,
                onCancel: _cancelZoneHandover,
                onRespond: _respondToZoneHandover,
              );
              if (!wide) {
                return ListView(
                  children: [
                    SizedBox(height: 270, child: coverage),
                    const SizedBox(height: 12),
                    SizedBox(height: 620, child: history),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: constraints.maxWidth * .34, child: coverage),
                  const SizedBox(width: 12),
                  Expanded(child: history),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ZoneHandoverDraft {
  final String recipientUserId;
  final List<String> zones;
  final DateTime startAt;
  final DateTime endAt;
  final String reason;

  const _ZoneHandoverDraft({
    required this.recipientUserId,
    required this.zones,
    required this.startAt,
    required this.endAt,
    required this.reason,
  });
}

class _ZoneHandoverRequestDialog extends StatefulWidget {
  final List<Map<String, dynamic>> managers;
  final List<String> permanentZones;
  final Future<bool> Function(_ZoneHandoverDraft) onSubmit;

  const _ZoneHandoverRequestDialog({
    required this.managers,
    required this.permanentZones,
    required this.onSubmit,
  });

  @override
  State<_ZoneHandoverRequestDialog> createState() =>
      _ZoneHandoverRequestDialogState();
}

class _ZoneHandoverRequestDialogState
    extends State<_ZoneHandoverRequestDialog> {
  final _reason = TextEditingController();
  String? _recipient;
  late Set<String> _zones;
  late DateTime _start;
  late DateTime _end;
  String? _error;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _start = now;
    _end = now.add(const Duration(days: 7));
    _zones = widget.permanentZones.toSet();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime(bool start) async {
    final initial = start ? _start : _end;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: Color(0xff4F46E5)),
        ),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: Color(0xff4F46E5)),
        ),
        child: child!,
      ),
    );
    if (time == null) return;
    final value = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      if (start) {
        _start = value;
        if (!_end.isAfter(_start)) _end = _start.add(const Duration(days: 1));
      } else {
        _end = value;
      }
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final reason = _reason.text.trim();
    if (_recipient == null || _recipient!.isEmpty) {
      setState(() => _error = 'Choose the Zone Manager who will cover you.');
      return;
    }
    if (_zones.isEmpty) {
      setState(() => _error = 'Select at least one permanent zone.');
      return;
    }
    if (!_end.isAfter(_start) || !_end.isAfter(DateTime.now())) {
      setState(
        () => _error = 'The return time must be after the handover start.',
      );
      return;
    }
    if (reason.length < 4) {
      setState(() => _error = 'Add a clear reason for the handover.');
      return;
    }
    final draft = _ZoneHandoverDraft(
      recipientUserId: _recipient!,
      zones: _zones.toList(growable: false)..sort(),
      startAt: _start,
      endAt: _end,
      reason: reason,
    );
    setState(() {
      _submitting = true;
      _error = null;
    });
    final sent = await widget.onSubmit(draft);
    if (!mounted) return;
    if (sent) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _submitting = false;
      _error = 'The request could not be sent. Please review and try again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('dd MMM yyyy • hh:mm a');
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: 760,
        constraints: const BoxConstraints(maxHeight: 760),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x260F172A),
              blurRadius: 40,
              offset: Offset(0, 18),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(24, 20, 18, 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xff312E81), Color(0xff6366F1)],
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.handshake_outlined,
                        color: Colors.white,
                        size: 25,
                      ),
                    ),
                    const SizedBox(width: 13),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Create Zone Handover',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            'Your colleague must accept before responsibility is transferred.',
                            style: TextStyle(
                              color: Color(0xffC7D2FE),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _ZoneFormLabel('Covering Zone Manager'),
                    const SizedBox(height: 7),
                    DropdownButtonFormField<String>(
                      initialValue: _recipient,
                      isExpanded: true,
                      decoration: _zoneHandoverInput(
                        Icons.person_search_outlined,
                        'Choose a colleague',
                      ),
                      items: widget.managers
                          .map((manager) {
                            final zones = _zoneStringList(manager['zones']);
                            return DropdownMenuItem(
                              value: (manager['user_id'] ?? '').toString(),
                              child: Text(
                                '${manager['user_name'] ?? 'Zone Manager'}${zones.isEmpty ? '' : '  •  ${zones.join(', ')}'}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          })
                          .toList(growable: false),
                      onChanged: _submitting
                          ? null
                          : (value) => setState(() => _recipient = value),
                    ),
                    const SizedBox(height: 18),
                    const _ZoneFormLabel('Zones to hand over'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: widget.permanentZones
                          .map((zone) {
                            final selected = _zones.contains(zone);
                            return FilterChip(
                              selected: selected,
                              onSelected: _submitting
                                  ? null
                                  : (value) => setState(() {
                                      value
                                          ? _zones.add(zone)
                                          : _zones.remove(zone);
                                    }),
                              avatar: Icon(
                                Icons.account_tree_outlined,
                                size: 16,
                                color: selected
                                    ? const Color(0xff4338CA)
                                    : const Color(0xff64748B),
                              ),
                              label: Text(zone),
                              selectedColor: const Color(0xffE0E7FF),
                              checkmarkColor: const Color(0xff4338CA),
                              side: BorderSide(
                                color: selected
                                    ? const Color(0xff818CF8)
                                    : const Color(0xffCBD5E1),
                              ),
                            );
                          })
                          .toList(growable: false),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _ZoneDateTimeField(
                            label: 'Handover starts',
                            value: formatter.format(_start),
                            icon: Icons.login_rounded,
                            onTap: _submitting
                                ? null
                                : () => _pickDateTime(true),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(10, 24, 10, 0),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            color: Color(0xff818CF8),
                          ),
                        ),
                        Expanded(
                          child: _ZoneDateTimeField(
                            label: 'Expected return',
                            value: formatter.format(_end),
                            icon: Icons.logout_rounded,
                            onTap: _submitting
                                ? null
                                : () => _pickDateTime(false),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const _ZoneFormLabel('Reason and handover note'),
                    const SizedBox(height: 7),
                    TextField(
                      controller: _reason,
                      enabled: !_submitting,
                      minLines: 3,
                      maxLines: 5,
                      maxLength: 500,
                      decoration: _zoneHandoverInput(
                        Icons.notes_rounded,
                        'Example: Annual leave. Please monitor daily and additional orders.',
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: _error == null
                          ? const SizedBox.shrink()
                          : Container(
                              key: ValueKey(_error),
                              width: double.infinity,
                              padding: const EdgeInsets.all(11),
                              decoration: BoxDecoration(
                                color: const Color(0xffFEF2F2),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xffFCA5A5),
                                ),
                              ),
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  color: Color(0xffB91C1C),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      transitionBuilder: (child, animation) => SizeTransition(
                        sizeFactor: animation,
                        alignment: Alignment.topCenter,
                        child: FadeTransition(opacity: animation, child: child),
                      ),
                      child: _submitting
                          ? Container(
                              key: const ValueKey('handover-sending'),
                              width: double.infinity,
                              margin: const EdgeInsets.only(top: 12),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xffEEF2FF),
                                    Color(0xffF5F3FF),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xffC7D2FE),
                                ),
                              ),
                              child: const Row(
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      color: Color(0xff4F46E5),
                                    ),
                                  ),
                                  SizedBox(width: 11),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Sending handover request…',
                                          style: TextStyle(
                                            color: Color(0xff312E81),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        SizedBox(height: 2),
                                        Text(
                                          'Saving the request and notifying the receiving manager.',
                                          style: TextStyle(
                                            color: Color(0xff6366F1),
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : const SizedBox.shrink(
                              key: ValueKey('handover-idle'),
                            ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _submitting
                              ? null
                              : () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 9),
                        FilledButton.icon(
                          onPressed: _submitting ? null : _submit,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xff4F46E5),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                          ),
                          icon: _submitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.send_rounded, size: 18),
                          label: Text(
                            _submitting
                                ? 'Sending Request…'
                                : 'Send Handover Request',
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
}

List<String> _zoneStringList(dynamic value) {
  if (value is List) {
    return value.map((item) => item.toString()).toList(growable: false);
  }
  return const [];
}

InputDecoration _zoneHandoverInput(IconData icon, String hint) =>
    InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: const Color(0xff6366F1), size: 20),
      filled: true,
      fillColor: const Color(0xffF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xffCBD5E1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xffCBD5E1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xff6366F1), width: 1.5),
      ),
    );

class _ZoneFormLabel extends StatelessWidget {
  final String text;
  const _ZoneFormLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: Color(0xff334155),
      fontSize: 12,
      fontWeight: FontWeight.w800,
    ),
  );
}

class _ZoneDateTimeField extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;

  const _ZoneDateTimeField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _ZoneFormLabel(label),
      const SizedBox(height: 7),
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xffF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xffCBD5E1)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 19, color: const Color(0xff6366F1)),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xff1E293B),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Icon(
                Icons.edit_calendar_outlined,
                size: 17,
                color: Color(0xff94A3B8),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _ZoneCoverageOverview extends StatelessWidget {
  final List<String> permanentZones;
  final List<Map<String, dynamic>> activeRows;
  final String Function(String) managerName;
  final List<String> Function(dynamic) zonesOf;
  final DateTime? Function(dynamic) dateOf;

  const _ZoneCoverageOverview({
    required this.permanentZones,
    required this.activeRows,
    required this.managerName,
    required this.zonesOf,
    required this.dateOf,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xffD7E0EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.shield_outlined, color: Color(0xff4F46E5)),
              SizedBox(width: 9),
              Text(
                'My Zone Coverage',
                style: TextStyle(
                  color: Color(0xff0F172A),
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          const Text(
            'PERMANENT RESPONSIBILITY',
            style: TextStyle(
              color: Color(0xff64748B),
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: .7,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: permanentZones
                .map(
                  (zone) => Chip(
                    avatar: const Icon(
                      Icons.account_tree_outlined,
                      size: 16,
                      color: Color(0xff4338CA),
                    ),
                    label: Text(zone),
                    backgroundColor: const Color(0xffEEF2FF),
                    side: const BorderSide(color: Color(0xffC7D2FE)),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 18),
          const Text(
            'TEMPORARY RESPONSIBILITY',
            style: TextStyle(
              color: Color(0xff64748B),
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: .7,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: activeRows.isEmpty
                ? const Center(
                    child: Text(
                      'No temporary zones assigned.',
                      style: TextStyle(color: Color(0xff94A3B8)),
                    ),
                  )
                : ListView.separated(
                    itemCount: activeRows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final row = activeRows[index];
                      final end = dateOf(row['end_at']);
                      return Container(
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: const Color(0xffECFDF5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xffA7F3D0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              zonesOf(row['zones']).join(' • '),
                              style: const TextStyle(
                                color: Color(0xff065F46),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'From ${managerName((row['requester_user_id'] ?? '').toString())}${end == null ? '' : ' • until ${DateFormat('dd MMM, hh:mm a').format(end)}'}',
                              style: const TextStyle(
                                color: Color(0xff047857),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
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
  }
}

class _ZoneHandoverHistory extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final String currentUserId;
  final String Function(String) managerName;
  final List<String> Function(dynamic) zonesOf;
  final DateTime? Function(dynamic) dateOf;
  final String Function(Map<String, dynamic>) statusOf;
  final bool busy;
  final ValueChanged<String> onCancel;
  final Future<void> Function(String, bool) onRespond;

  const _ZoneHandoverHistory({
    required this.rows,
    required this.currentUserId,
    required this.managerName,
    required this.zonesOf,
    required this.dateOf,
    required this.statusOf,
    required this.busy,
    required this.onCancel,
    required this.onRespond,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xffD7E0EC)),
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 15, 18, 13),
            child: Row(
              children: [
                Icon(Icons.history_rounded, color: Color(0xff0EA5E9)),
                SizedBox(width: 9),
                Text(
                  'Responsibility History',
                  style: TextStyle(
                    color: Color(0xff0F172A),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: rows.isEmpty
                ? const Center(
                    child: Text(
                      'No handover records yet.',
                      style: TextStyle(color: Color(0xff94A3B8)),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(14),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 9),
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      final outgoing =
                          (row['requester_user_id'] ?? '').toString() ==
                          currentUserId;
                      final otherId =
                          (row[outgoing
                                      ? 'recipient_user_id'
                                      : 'requester_user_id'] ??
                                  '')
                              .toString();
                      final status = statusOf(row);
                      final statusColor = _zoneHandoverStatusColor(status);
                      final start = dateOf(row['start_at']);
                      final end = dateOf(row['end_at']);
                      final canCancel =
                          outgoing &&
                          (status == 'pending' ||
                              status == 'active' ||
                              status == 'scheduled');
                      final canRespond = !outgoing && status == 'pending';
                      return Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: const Color(0xffF8FAFC),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(color: const Color(0xffE2E8F0)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: .11),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: Icon(
                                outgoing
                                    ? Icons.north_east_rounded
                                    : Icons.south_west_rounded,
                                color: statusColor,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${outgoing ? 'To' : 'From'} ${managerName(otherId)} • ${zonesOf(row['zones']).join(', ')}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xff0F172A),
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                      _ZoneHandoverStatusPill(
                                        status: status,
                                        color: statusColor,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${start == null ? '—' : DateFormat('dd MMM, hh:mm a').format(start)}  →  ${end == null ? '—' : DateFormat('dd MMM, hh:mm a').format(end)}',
                                    style: const TextStyle(
                                      color: Color(0xff64748B),
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    (row['reason'] ?? '').toString(),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xff334155),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (canRespond) ...[
                              const SizedBox(width: 10),
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  FilledButton.icon(
                                    onPressed: busy
                                        ? null
                                        : () => onRespond(
                                            (row['id'] ?? '').toString(),
                                            true,
                                          ),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xff059669),
                                      minimumSize: const Size(94, 34),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    icon: const Icon(
                                      Icons.check_rounded,
                                      size: 17,
                                    ),
                                    label: const Text('Accept'),
                                  ),
                                  const SizedBox(height: 5),
                                  OutlinedButton.icon(
                                    onPressed: busy
                                        ? null
                                        : () => onRespond(
                                            (row['id'] ?? '').toString(),
                                            false,
                                          ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xffDC2626),
                                      side: const BorderSide(
                                        color: Color(0xffFCA5A5),
                                      ),
                                      minimumSize: const Size(94, 32),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 16,
                                    ),
                                    label: const Text('Decline'),
                                  ),
                                ],
                              ),
                            ] else if (canCancel) ...[
                              const SizedBox(width: 8),
                              IconButton(
                                onPressed: busy
                                    ? null
                                    : () => onCancel(
                                        (row['id'] ?? '').toString(),
                                      ),
                                tooltip: 'Cancel handover',
                                icon: const Icon(
                                  Icons.cancel_outlined,
                                  color: Color(0xffDC2626),
                                  size: 20,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ZoneHandoverConfirmDialog extends StatelessWidget {
  final _ZoneHandoverConfirmAction action;
  final String managerName;
  final List<String> zones;
  final String reason;
  final DateTime? startAt;
  final DateTime? endAt;

  const _ZoneHandoverConfirmDialog({
    required this.action,
    required this.managerName,
    required this.zones,
    required this.reason,
    required this.startAt,
    required this.endAt,
  });

  @override
  Widget build(BuildContext context) {
    final isDecline = action == _ZoneHandoverConfirmAction.decline;
    final accent = isDecline
        ? const Color(0xffDC2626)
        : const Color(0xffEA580C);
    final soft = isDecline ? const Color(0xffFEF2F2) : const Color(0xffFFF7ED);
    final border = isDecline
        ? const Color(0xffFCA5A5)
        : const Color(0xffFDBA74);
    final title = isDecline
        ? 'Decline this coverage request?'
        : 'Cancel this handover?';
    final description = isDecline
        ? 'The request will be declined and $managerName will be notified immediately.'
        : 'The temporary coverage request assigned to $managerName will be cancelled.';
    final actionLabel = isDecline ? 'Yes, Decline' : 'Cancel Handover';
    final period = startAt == null || endAt == null
        ? ''
        : '${DateFormat('dd MMM, hh:mm a').format(startAt!)}  →  ${DateFormat('dd MMM, hh:mm a').format(endAt!)}';

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 500,
          margin: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Color(0x380F172A),
                blurRadius: 44,
                offset: Offset(0, 20),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(22, 20, 18, 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [soft, Colors.white],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border(bottom: BorderSide(color: border)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: .11),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: accent.withValues(alpha: .20),
                        ),
                      ),
                      child: Icon(
                        isDecline
                            ? Icons.mark_email_unread_outlined
                            : Icons.event_busy_outlined,
                        color: accent,
                        size: 25,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: Color(0xff0F172A),
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            description,
                            style: const TextStyle(
                              color: Color(0xff64748B),
                              fontSize: 11.5,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context, false),
                      tooltip: 'Close',
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Color(0xff64748B),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xffF8FAFC),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: const Color(0xffE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.person_outline_rounded,
                                size: 18,
                                color: Color(0xff6366F1),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  managerName,
                                  style: const TextStyle(
                                    color: Color(0xff0F172A),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              if (zones.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xffEEF2FF),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    zones.join(' • '),
                                    style: const TextStyle(
                                      color: Color(0xff4338CA),
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          if (period.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                const Icon(
                                  Icons.schedule_rounded,
                                  size: 16,
                                  color: Color(0xff64748B),
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    period,
                                    style: const TextStyle(
                                      color: Color(0xff475569),
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (reason.isNotEmpty) ...[
                            const SizedBox(height: 9),
                            Text(
                              reason,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xff334155),
                                fontSize: 11,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xff475569),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 13,
                            ),
                          ),
                          child: const Text('Go Back'),
                        ),
                        const SizedBox(width: 9),
                        FilledButton.icon(
                          onPressed: () => Navigator.pop(context, true),
                          style: FilledButton.styleFrom(
                            backgroundColor: accent,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 13,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: Icon(
                            isDecline
                                ? Icons.close_rounded
                                : Icons.event_busy_outlined,
                            size: 18,
                          ),
                          label: Text(actionLabel),
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
}

class _ZoneHandoverStatusPill extends StatelessWidget {
  final String status;
  final Color color;
  const _ZoneHandoverStatusPill({required this.status, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: .28)),
    ),
    child: Text(
      status.toUpperCase(),
      style: TextStyle(
        color: color,
        fontSize: 9,
        fontWeight: FontWeight.w900,
        letterSpacing: .4,
      ),
    ),
  );
}

Color _zoneHandoverStatusColor(String status) => switch (status) {
  'active' => const Color(0xff059669),
  'scheduled' => const Color(0xff0EA5E9),
  'accepted' => const Color(0xff059669),
  'pending' => const Color(0xffD97706),
  'rejected' => const Color(0xffDC2626),
  'cancelled' => const Color(0xff64748B),
  'expired' => const Color(0xff7C3AED),
  _ => const Color(0xff64748B),
};

class _ZoneHandoverSetupRequired extends StatelessWidget {
  final VoidCallback onRetry;
  const _ZoneHandoverSetupRequired({required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 620,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xffC7D2FE)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.storage_rounded, size: 44, color: Color(0xff4F46E5)),
          const SizedBox(height: 14),
          const Text(
            'Zone Handover setup required',
            style: TextStyle(
              color: Color(0xff0F172A),
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Run supabase/sql/zone_manager_multi_zone_delegation.sql once in Supabase, then retry.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xff64748B), height: 1.5),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xff4F46E5),
            ),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry Setup Check'),
          ),
        ],
      ),
    ),
  );
}
