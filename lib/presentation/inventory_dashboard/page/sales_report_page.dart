import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/datasources/remote/sales_report_remote_ds.dart';
import '../widgets/sales_report_workspace.dart';

class SalesReportPage extends StatefulWidget {
  final SalesReportRemoteDs? dataSource;
  final bool zonal;
  const SalesReportPage({super.key, this.dataSource, this.zonal = false});

  @override
  State<SalesReportPage> createState() => _SalesReportPageState();
}

class _SalesReportPageState extends State<SalesReportPage> {
  late final SalesReportRemoteDs _remote;
  final Set<String> _selected = {};
  Map<String, dynamic>? _state;
  String? _error;
  bool _loading = true;
  bool _busy = false;
  bool _polling = false;
  bool _monthlyPending = false;
  bool _monthlyRequestNeeded = false;
  bool _monthlyChecking = false;
  Map<String, dynamic>? _dailyState;
  String? _dailyError;
  bool _dailyPolling = false;
  bool _dailyBusy = false;
  bool _dailyPending = false;
  bool _dailyRequestNeeded = false;
  bool _dailyChecking = false;
  SalesReportDownloadPhase _downloadPhase = SalesReportDownloadPhase.idle;
  String _downloadLabel = 'Sales report CSV';

  bool get _startingDownload =>
      _downloadPhase == SalesReportDownloadPhase.starting;

  Map<String, dynamic>? get _dailyJob => _dailyState?['job'] == null
      ? null
      : Map<String, dynamic>.from(_dailyState!['job'] as Map);
  int _selectionVersion = 0;
  Timer? _timer;

  List<Map<String, dynamic>> get _months =>
      List<Map<String, dynamic>>.from(_state?['months'] as List? ?? const []);
  Map<String, dynamic>? get _job => _state?['job'] == null
      ? null
      : Map<String, dynamic>.from(_state!['job'] as Map);
  List<String> get _selection => _selected.toList()
    ..sort(
      (a, b) => '${a.substring(3)}${a.substring(0, 2)}'.compareTo(
        '${b.substring(3)}${b.substring(0, 2)}',
      ),
    );

  @override
  void initState() {
    super.initState();
    _remote =
        widget.dataSource ?? SalesReportRemoteDs(Supabase.instance.client);
    _refresh();
    _refreshDaily();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _syncPreparationTimer() {
    if (!mounted) return;
    if (!_monthlyPending && !_dailyPending) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer.periodic(const Duration(seconds: 5), (_) {
      if (_monthlyPending) _refresh(silent: true);
      if (_dailyPending) _refreshDaily();
    });
  }

  Future<void> _refresh({bool silent = false}) async {
    if (_polling || _busy) return;
    final version = _selectionVersion;
    final selection = _selection;
    final request = _monthlyPending && _monthlyRequestNeeded;
    if (request) _monthlyRequestNeeded = false;
    var download = false;
    _polling = true;
    if (!silent) {
      setState(() {
        _loading = _state == null;
        _error = null;
      });
    }
    try {
      final data = await _remote.fetch(months: selection, request: request);
      if (!mounted || version != _selectionVersion) return;
      setState(() {
        _state = data;
        _error = null;
        if (request) _monthlyChecking = false;
        if (_monthlyPending &&
            !_monthlyRequestNeeded &&
            _job?['status'] == 'failed') {
          _monthlyPending = false;
          _monthlyRequestNeeded = false;
          _monthlyChecking = false;
          _error = 'Preparation interrupted. Tap download to try again.';
        }
      });
      download =
          _monthlyPending &&
          !_startingDownload &&
          data['awaiting_update'] != true &&
          _job?['status'] == 'ready' &&
          _job?['is_current'] == true;
    } catch (error) {
      if (mounted && version == _selectionVersion) {
        setState(() {
          _error = error.toString();
          _monthlyPending = false;
          _monthlyRequestNeeded = false;
          _monthlyChecking = false;
        });
      }
    } finally {
      _polling = false;
      if (mounted) {
        _syncPreparationTimer();
        if (version != _selectionVersion) {
          unawaited(_refresh());
        } else {
          setState(() => _loading = false);
        }
      }
    }
    if (!mounted || version != _selectionVersion) return;
    if (download && _monthlyPending && !_startingDownload) {
      await _download();
    } else if (_monthlyPending && _monthlyRequestNeeded) {
      // A click can arrive during a background poll. Send its preparation
      // request after that response, rather than losing the user's intent.
      unawaited(_refresh(silent: true));
    }
  }

  void _select(VoidCallback change) {
    setState(() {
      change();
      _selectionVersion++;
      _monthlyPending = false;
      _monthlyRequestNeeded = false;
      _monthlyChecking = false;
      _state = {...?_state, 'job': null};
      _error = null;
    });
    _syncPreparationTimer();
    // An in-flight response belongs to the previous selection and is ignored.
    if (!_polling) _refresh(silent: true);
  }

  Future<void> _requestMonthly() async {
    if (_busy || _startingDownload || _monthlyPending || _selected.isEmpty) {
      return;
    }
    setState(() {
      _monthlyPending = true;
      _monthlyRequestNeeded = true;
      _monthlyChecking = true;
      _downloadPhase = SalesReportDownloadPhase.idle;
      _error = null;
    });
    _syncPreparationTimer();
    await _refresh(silent: true);
  }

  Future<void> _download() async {
    if (_busy || _startingDownload) return;
    String? downloadError;
    setState(() {
      _busy = true;
      _monthlyPending = false;
      _monthlyRequestNeeded = false;
      _monthlyChecking = false;
      _error = null;
    });
    _syncPreparationTimer();
    try {
      final selection = _selection;
      await _startDownload(
        'Monthly sales CSV',
        () => _remote.downloadUrl(selection),
      );
    } catch (error) {
      downloadError = error.toString();
    } finally {
      if (mounted) setState(() => _busy = false);
      if (mounted) await _refresh(silent: true);
      if (mounted && downloadError != null) {
        setState(() => _error = downloadError);
      }
    }
  }

  @override
  Widget build(BuildContext context) => SalesReportWorkspace(
    downloadPhase: _downloadPhase,
    downloadLabel: _downloadLabel,
    onDismissDownloadNotice: () =>
        setState(() => _downloadPhase = SalesReportDownloadPhase.idle),
    dailyFrom: _dailyState?['period_from'] as String?,
    dailyThrough: _dailyState?['period_through'] as String?,
    awaitingUpdate: _dailyState?['awaiting_update'] == true,
    dailyJob: _dailyJob,
    dailyLoading: _dailyState == null,
    dailyBusy: _dailyBusy || _dailyPending || _startingDownload,
    dailyChecking: _dailyChecking,
    dailyError: _dailyError,
    onDailyDownload: _requestDaily,
    months: _months,
    selected: Set.unmodifiable(_selected),
    job: _job,
    loading: _loading,
    busy: _busy || _startingDownload,
    monthlyPending: _monthlyPending,
    monthlyChecking: _monthlyChecking,
    awaitingMonthlyUpdate: _state?['awaiting_update'] == true,
    metadataCurrent: _state?['metadata_current'] == true,
    zonal: widget.zonal || _state?['scope_kind'] == 'zone',
    scopeLabel: _state?['scope_label'] as String?,
    currentMonth: _state?['current_month'] as String?,
    currentMonthLastDay: _state?['current_month_last_day'] as String?,
    error: _error,
    onToggle: (month) => _select(() {
      _selected.contains(month)
          ? _selected.remove(month)
          : _selected.add(month);
    }),
    onPreset: (months) => _select(() {
      _selected
        ..clear()
        ..addAll(months);
    }),
    onRefresh: () {
      _refresh();
      _refreshDaily();
    },
    onDownload: _requestMonthly,
  );

  Future<void> _requestDaily() async {
    if (_dailyBusy || _dailyPending || _startingDownload) {
      return;
    }
    setState(() {
      _dailyPending = true;
      _dailyRequestNeeded = true;
      _dailyChecking = true;
      _dailyError = null;
      _downloadPhase = SalesReportDownloadPhase.idle;
    });
    _syncPreparationTimer();
    await _refreshDaily();
  }

  Future<void> _refreshDaily() async {
    if (_dailyPolling || _dailyBusy) return;
    final request = _dailyPending && _dailyRequestNeeded;
    if (request) _dailyRequestNeeded = false;
    _dailyPolling = true;
    var download = false;
    try {
      final data = await _remote.fetchDaily(request: request);
      if (!mounted) return;
      setState(() {
        _dailyState = data;
        _dailyError = null;
        if (request) _dailyChecking = false;
        if (_dailyJob?['status'] == 'failed' && !_dailyRequestNeeded) {
          _dailyPending = false;
          _dailyRequestNeeded = false;
          _dailyChecking = false;
          _dailyError = 'Preparation interrupted. Tap download to try again.';
        }
      });
      download =
          _dailyPending &&
          !_startingDownload &&
          data['awaiting_update'] != true &&
          _dailyJob?['status'] == 'ready' &&
          _dailyJob?['is_current'] == true;
    } catch (error) {
      if (mounted) {
        setState(() {
          _dailyError = error.toString();
          _dailyPending = false;
          _dailyRequestNeeded = false;
          _dailyChecking = false;
        });
      }
    } finally {
      _dailyPolling = false;
      _syncPreparationTimer();
      if (mounted) setState(() {});
    }
    if (!mounted) return;
    if (download) {
      await _downloadDaily();
    } else if (_dailyPending && _dailyRequestNeeded) {
      // Keep clicks accepted during a status poll; they join or prepare the
      // report when that poll ends, without disabling the button in between.
      unawaited(_refreshDaily());
    }
  }

  Future<void> _downloadDaily() async {
    if (_dailyBusy || _startingDownload) return;
    setState(() {
      _dailyBusy = true;
      _dailyPending = false;
      _dailyRequestNeeded = false;
      _dailyChecking = false;
    });
    _syncPreparationTimer();
    try {
      // Revalidate source version and zone scope immediately before signing.
      await _startDownload('Sales 45 Days CSV', _remote.downloadDailyUrl);
    } catch (error) {
      if (mounted) setState(() => _dailyError = error.toString());
    } finally {
      if (mounted) setState(() => _dailyBusy = false);
    }
  }

  Future<void> _startDownload(
    String label,
    Future<Uri> Function() getUrl,
  ) async {
    setState(() {
      _downloadLabel = label;
      _downloadPhase = SalesReportDownloadPhase.starting;
    });
    // Paint feedback before URL validation or handing navigation to the browser.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    try {
      final uri = await getUrl();
      if (!mounted) return;
      if (!await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_self',
      )) {
        throw StateError('Could not start the CSV download.');
      }
      // The browser owns the transfer. A persistent notice must not claim it
      // has completed or report invented download progress.
      if (mounted) {
        setState(() => _downloadPhase = SalesReportDownloadPhase.requested);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _downloadPhase = SalesReportDownloadPhase.idle);
      }
      rethrow;
    }
  }
}
