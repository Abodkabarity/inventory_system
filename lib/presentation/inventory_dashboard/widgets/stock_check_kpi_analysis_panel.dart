import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/stock_check_excel_exporter.dart';
import '../../../core/utils/stock_check_kpi_export_worker.dart';
import '../../../domain/entities/stock_check_campaign.dart';
import '../../../domain/entities/stock_check_kpi_report.dart';
import '../../../domain/entities/stock_check_task.dart';

String _percent(double? value) =>
    value == null ? '—' : '${value.toStringAsFixed(1)}%';
String _qty(num? value) => value == null
    ? '—'
    : value.toStringAsFixed(6).replaceFirst(RegExp(r'\.?0+$'), '');

class StockCheckKpiAnalysisPanel extends StatefulWidget {
  final List<StockCheckCampaign> projects;
  final List<StockCheckTask> rows;
  final VoidCallback onSelectProjects;
  final bool isLoading;
  final String loadError;
  final int loadedProjects;
  final VoidCallback? onRetry;
  final Future<void> Function({
    required StockCheckKpiReport report,
    KpiExportJob? job,
    void Function(KpiExportProgress)? onProgress,
  })
  exportReport;

  const StockCheckKpiAnalysisPanel({
    super.key,
    required this.projects,
    required this.rows,
    required this.onSelectProjects,
    this.isLoading = false,
    this.loadError = '',
    this.loadedProjects = 0,
    this.onRetry,
    this.exportReport = StockCheckExcelExporter.exportKpiAnalysis,
  });

  @override
  State<StockCheckKpiAnalysisPanel> createState() =>
      _StockCheckKpiAnalysisPanelState();
}

class _StockCheckKpiAnalysisPanelState
    extends State<StockCheckKpiAnalysisPanel> {
  late StockCheckKpiReport _report;
  String _search = '';
  bool _exporting = false;
  KpiExportJob? _exportJob;
  KpiExportProgress? _exportProgress;

  @override
  void initState() {
    super.initState();
    _report = StockCheckKpiReport(projects: const [], rows: const []);
    _refresh();
  }

  @override
  void didUpdateWidget(covariant StockCheckKpiAnalysisPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isLoading != widget.isLoading ||
        oldWidget.loadError != widget.loadError ||
        !identical(oldWidget.rows, widget.rows) ||
        !listEquals(oldWidget.projects, widget.projects)) {
      _refresh();
    }
  }

  void _refresh() {
    // Commit complete results together. Partial loads must not replace the
    // last valid KPI score or look like products absent from another quarter.
    if (widget.isLoading || widget.loadError.isNotEmpty) return;
    _report = StockCheckKpiReport(projects: widget.projects, rows: widget.rows);
  }

  Future<void> _export() async {
    if (_exporting || widget.isLoading || widget.loadError.isNotEmpty) return;
    final report = _report;
    final job = KpiExportJob();
    setState(() {
      _exporting = true;
      _exportJob = job;
      _exportProgress = KpiExportProgress(
        KpiExportStage.preparing,
        total: report.total,
      );
    });
    try {
      // Paint feedback before preparing any export data.
      await WidgetsBinding.instance.endOfFrame;
      job.checkCancelled();
      await widget.exportReport(
        report: report,
        job: job,
        onProgress: (progress) {
          if (mounted && identical(_exportJob, job) && !job.cancelled) {
            setState(() => _exportProgress = progress);
          }
        },
      );
      job.checkCancelled();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('KPI report is ready. Download started.'),
          ),
        );
      }
    } on KpiExportCancelled {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Export cancelled.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not export KPI report: $error')),
        );
      }
    } finally {
      if (mounted && identical(_exportJob, job)) {
        setState(() {
          _exporting = false;
          _exportJob = null;
          _exportProgress = null;
        });
      }
    }
  }

  final _scroll = ScrollController();

  @override
  void dispose() {
    _exportJob?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final branches = _report.branches.entries
        .where(
          (branch) =>
              branch.key.toLowerCase().contains(_search.trim().toLowerCase()),
        )
        .toList();
    return Container(
      decoration: BoxDecoration(
        color: _kpiCanvas,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xffe1e8f0)),
        boxShadow: [
          BoxShadow(
            color: _kpiInk.withValues(alpha: .04),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1250
              ? 3
              : constraints.maxWidth >= 780
              ? 2
              : 1;
          return Scrollbar(
            controller: _scroll,
            child: CustomScrollView(
              controller: _scroll,
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                    child: _KpiEntrance(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _header(),
                          AnimatedSize(
                            duration: _kpiDuration(context, 220),
                            alignment: Alignment.topCenter,
                            child:
                                widget.isLoading || widget.loadError.isNotEmpty
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 20),
                                    child: _projectLoadStatus(),
                                  )
                                : const SizedBox(width: double.infinity),
                          ),
                          if (_report.projects.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                for (
                                  var i = 0;
                                  i < _report.projects.length;
                                  i++
                                )
                                  _projectBadge(_report.projects[i], i),
                              ],
                            ),
                          ],
                          if (_exporting) ...[
                            const SizedBox(height: 20),
                            _exportStatus(),
                          ],
                          const SizedBox(height: 22),
                          _summary(constraints.maxWidth - 48),
                          const SizedBox(height: 16),
                          _ruleNote(),
                          if (_report.incompleteProjectIds.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _notice(
                              'Project data is incomplete. Select projects and Apply again to load all counts before calculating KPI: ${_report.projects.where((p) => _report.incompleteProjectIds.contains(p.id)).map((p) => p.title).join(', ')}',
                              isError: true,
                            ),
                          ],
                          if (_report.awaiting > 0) ...[
                            const SizedBox(height: 10),
                            _notice(
                              '${_report.awaiting} products are awaiting submitted counts or review and are excluded from the score.',
                            ),
                          ],
                          const SizedBox(height: 26),
                          _branchToolbar(
                            branches.length,
                            constraints.maxWidth - 48,
                          ),
                          const SizedBox(height: 18),
                        ],
                      ),
                    ),
                  ),
                ),
                if (branches.isEmpty && widget.isLoading)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                    sliver: SliverGrid(
                      delegate: SliverChildBuilderDelegate(
                        (_, _) => const _KpiBranchPlaceholder(),
                        childCount: columns * 2,
                      ),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        mainAxisExtent: 250,
                      ),
                    ),
                  )
                else if (branches.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _emptyState(),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                    sliver: SliverGrid(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final branch = branches[index];
                        return _KpiEntrance(
                          key: ValueKey(branch.key),
                          delay: (index % columns) * 65,
                          child: _branchCard(branch.key, branch.value),
                        );
                      }, childCount: branches.length),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        mainAxisExtent: 250,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _header() => LayoutBuilder(
    builder: (context, constraints) {
      final heading = Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_kpiBlue, _kpiTeal]),
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: _kpiBlue.withValues(alpha: .22),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: const Icon(
              Icons.insights_rounded,
              color: Colors.white,
              size: 27,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'INVENTORY PERFORMANCE',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.8,
                    color: _kpiMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Stock Check KPI Analysis',
                  style: TextStyle(
                    fontSize: 23,
                    color: _kpiInk,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
      final actions = Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: widget.isLoading ? null : widget.onSelectProjects,
            style: OutlinedButton.styleFrom(
              foregroundColor: _kpiInk,
              backgroundColor: Colors.white,
              side: const BorderSide(color: Color(0xffdce4ef)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.folder_open_rounded, size: 19),
            label: Text('${widget.projects.length} Projects'),
          ),
          FilledButton.icon(
            onPressed:
                _report.total == 0 ||
                    _exporting ||
                    widget.isLoading ||
                    widget.loadError.isNotEmpty
                ? null
                : _export,
            style: FilledButton.styleFrom(
              backgroundColor: _kpiBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.file_download_outlined, size: 19),
            label: Text(_exporting ? 'Exporting...' : 'Export KPI Report'),
          ),
        ],
      );
      if (constraints.maxWidth < 850) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [heading, const SizedBox(height: 16), actions],
        );
      }
      return Row(
        children: [
          Expanded(child: heading),
          const SizedBox(width: 16),
          actions,
        ],
      );
    },
  );

  Widget _projectLoadStatus() {
    final failed = widget.loadError.isNotEmpty;
    final color = failed ? const Color(0xffb45309) : _kpiBlue;
    final total = widget.projects.length;
    final loaded = widget.loadedProjects.clamp(0, total);
    final periods = widget.projects
        .map((p) => p.period.isEmpty ? p.title : p.period)
        .join(' · ');
    return Container(
      key: const ValueKey('kpi-project-loading-status'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: failed
              ? [const Color(0xfffff8ef), const Color(0xfffffcf7)]
              : [const Color(0xffeef5ff), const Color(0xffeefaf7)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: .16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: failed
                    ? Icon(Icons.cloud_off_rounded, color: color, size: 20)
                    : CircularProgressIndicator(strokeWidth: 2.5, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      failed
                          ? 'Could not update KPI analysis'
                          : 'Updating KPI analysis',
                      style: const TextStyle(
                        color: _kpiInk,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      failed
                          ? 'Please retry loading the selected projects.'
                          : '$periods · $loaded of $total projects loaded',
                      style: const TextStyle(color: _kpiMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (failed && widget.onRetry != null) ...[
                const SizedBox(width: 10),
                TextButton.icon(
                  onPressed: widget.onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Retry'),
                  style: TextButton.styleFrom(foregroundColor: color),
                ),
              ],
            ],
          ),
          if (_report.projects.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              failed
                  ? 'Previous results remain visible. Retry to update them.'
                  : 'Showing previous results until the update completes.',
              style: const TextStyle(fontSize: 12, color: _kpiMuted),
            ),
          ],
          if (!failed) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                minHeight: 5,
                value: total == 0 || loaded == 0 ? null : loaded / total,
                color: _kpiTeal,
                backgroundColor: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _exportStatus() {
    final progress = _exportProgress!;
    final stage = progress.stage;
    final label = switch (stage) {
      KpiExportStage.preparing => 'Preparing your KPI report',
      KpiExportStage.writing => 'Building the Excel worksheets',
      KpiExportStage.packaging => 'Compressing and finishing your file',
      KpiExportStage.downloading => 'Starting your download',
    };
    final fraction = progress.total == 0
        ? 0.0
        : progress.processed / progress.total;
    return Container(
      key: const ValueKey('kpi-export-status'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xffeef5ff), Color(0xffeefaf7)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xffd4e5f3)),
        boxShadow: [
          BoxShadow(
            color: _kpiBlue.withValues(alpha: .07),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: _kpiBlue,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: _kpiInk,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      stage == KpiExportStage.writing
                          ? '${progress.processed} / ${progress.total} products · ${(fraction * 100).round()}%'
                          : 'You can continue browsing while your report is being prepared.',
                      style: const TextStyle(fontSize: 12, color: _kpiMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => _exportJob?.cancel(),
                style: TextButton.styleFrom(foregroundColor: _kpiMuted),
                child: const Text('Cancel'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: stage == KpiExportStage.writing ? fraction : null,
              color: _kpiTeal,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 20,
            runSpacing: 8,
            children: [
              for (var i = 0; i < 3; i++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      stage.index > i
                          ? Icons.check_circle_rounded
                          : Icons.circle,
                      size: 13,
                      color: stage.index >= i
                          ? _kpiTeal
                          : const Color(0xffb6c5d5),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      ['Prepare', 'Build worksheets', 'Finish file'][i],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: stage.index >= i ? _kpiInk : _kpiMuted,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _projectBadge(StockCheckCampaign project, int index) {
    final color = index.isEven ? _kpiBlue : _kpiTeal;
    return Tooltip(
      message: project.title,
      child: Container(
        width: 180,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: .14)),
        ),
        child: Row(
          children: [
            Container(
              width: 39,
              height: 39,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .09),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(Icons.calendar_month_rounded, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                project.period.isEmpty ? project.title : project.period,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
            Icon(Icons.check_circle_rounded, color: color, size: 17),
          ],
        ),
      ),
    );
  }

  Widget _summary(double width) {
    final hero = _accuracyCard();
    final cards = [
      _metricCard(
        '100% / scored products',
        '${_report.correct} / ${_report.scored}',
        'Products earning full marks',
        Icons.verified_outlined,
        _kpiTeal,
      ),
      _metricCard(
        'Shared products',
        '${_report.shared}',
        'Across multiple projects',
        Icons.layers_outlined,
        _kpiBlue,
      ),
      _metricCard(
        'Single-project products',
        '${_report.standalone}',
        'Counted individually',
        Icons.inventory_2_outlined,
        const Color(0xff8056c9),
      ),
      _metricCard(
        'Awaiting / review',
        '${_report.awaiting}',
        'Excluded until completed',
        Icons.hourglass_top_rounded,
        const Color(0xffbb7a19),
      ),
    ];
    if (width >= 1180) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 17, child: hero),
          const SizedBox(width: 14),
          for (var i = 0; i < cards.length; i++) ...[
            Expanded(flex: 10, child: cards[i]),
            if (i != cards.length - 1) const SizedBox(width: 14),
          ],
        ],
      );
    }
    final count = width >= 720
        ? 4
        : width >= 430
        ? 2
        : 1;
    final cardWidth = (width - 14 * (count - 1)) / count;
    return Column(
      children: [
        hero,
        const SizedBox(height: 14),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final card in cards) SizedBox(width: cardWidth, child: card),
          ],
        ),
      ],
    );
  }

  Widget _accuracyCard() => Container(
    height: 172,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xff18354e), Color(0xff24576b), Color(0xff237d87)],
      ),
      boxShadow: [
        BoxShadow(
          color: _kpiTeal.withValues(alpha: .20),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Final KPI accuracy',
                  style: TextStyle(
                    color: Color(0xffc8e4ec),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _percent(_report.accuracy),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 39,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 12),
                const Row(
                  children: [
                    Icon(
                      Icons.auto_graph_rounded,
                      color: Color(0xff85e8d3),
                      size: 17,
                    ),
                    SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        'All selected projects',
                        style: TextStyle(
                          color: Color(0xffc8e4ec),
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (constraints.maxWidth > 225) ...[
            const SizedBox(width: 10),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: (_report.accuracy ?? 0) / 100),
              duration: _kpiDuration(context, 850),
              curve: Curves.easeOutCubic,
              builder: (_, value, _) => SizedBox(
                width: 72,
                height: 72,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ExcludeSemantics(
                      child: SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: value,
                          strokeWidth: 6,
                          strokeCap: StrokeCap.round,
                          backgroundColor: Colors.white.withValues(alpha: .14),
                          valueColor: const AlwaysStoppedAnimation(
                            Color(0xff89efda),
                          ),
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.track_changes_rounded,
                      color: Colors.white,
                      size: 29,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _metricCard(
    String label,
    String value,
    String subtitle,
    IconData icon,
    Color color,
  ) => Container(
    height: 172,
    padding: const EdgeInsets.all(17),
    decoration: _kpiSurface(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 19, color: color),
        ),
        const SizedBox(height: 12),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _kpiMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: const TextStyle(
              color: _kpiInk,
              fontSize: 25,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const Spacer(),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: _kpiMuted, fontSize: 10),
        ),
      ],
    ),
  );

  Widget _ruleNote() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(Icons.info_outline_rounded, size: 17, color: _kpiBlue),
      const SizedBox(width: 8),
      const Expanded(
        child: Text(
          'One score per product, per branch. 100% requires zero Difference in every project containing that product.',
          style: TextStyle(color: _kpiMuted, fontSize: 12, height: 1.4),
        ),
      ),
      Tooltip(
        message:
            'Shared products must have zero Difference in every included project. Single-project products are evaluated on their own. Missing products do not lower the score.',
        child: const Icon(
          Icons.help_outline_rounded,
          size: 17,
          color: _kpiMuted,
        ),
      ),
    ],
  );

  Widget _notice(String message, {bool isError = false}) {
    final color = isError ? const Color(0xffb94747) : const Color(0xffa46a16);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .13)),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.schedule_rounded,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _branchToolbar(int count, double width) {
    final heading = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Branch performance',
          style: TextStyle(
            color: _kpiInk,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 10),
        _kpiPill('$count branches', _kpiBlue),
      ],
    );
    final search = SizedBox(
      width: width < 620 ? width : 290,
      child: TextField(
        decoration: _kpiInput('Search branch', Icons.search_rounded),
        onChanged: (value) => setState(() => _search = value),
      ),
    );
    return width < 620
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [heading, const SizedBox(height: 12), search],
          )
        : Row(children: [heading, const Spacer(), search]);
  }

  Widget _branchCard(String branch, StockCheckKpiTotals totals) {
    final color = _kpiScoreColor(totals.accuracy);
    return _KpiHoverCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _kpiBlue.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.storefront_rounded,
                    color: _kpiBlue,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Tooltip(
                    message: branch,
                    child: Text(
                      branch,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _kpiInk,
                        fontSize: 14,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _kpiPill(_percent(totals.accuracy), color, large: true),
              ],
            ),
            const SizedBox(height: 17),
            Text(
              '${totals.correct} / ${totals.scored} scored',
              style: const TextStyle(
                color: _kpiMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 9),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: (totals.accuracy ?? 0) / 100),
              duration: _kpiDuration(context, 750),
              curve: Curves.easeOutCubic,
              builder: (_, value, _) => ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: ExcludeSemantics(
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: 6,
                    backgroundColor: const Color(0xffeef2f7),
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 15),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _kpiPill('${totals.shared} shared', _kpiBlue),
                _kpiPill(
                  '${totals.standalone} single',
                  const Color(0xff8056c9),
                ),
                _kpiPill(
                  '${totals.awaiting} awaiting',
                  totals.awaiting == 0 ? _kpiMuted : const Color(0xffa46a16),
                ),
              ],
            ),
            const Spacer(),
            const Divider(height: 16, color: Color(0xffedf1f6)),
            Row(
              children: [
                Icon(
                  totals.awaiting == 0
                      ? Icons.check_circle_outline_rounded
                      : Icons.schedule_rounded,
                  size: 15,
                  color: totals.awaiting == 0
                      ? _kpiTeal
                      : const Color(0xffa46a16),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    totals.awaiting == 0
                        ? 'Counts complete'
                        : 'Counts in progress',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _kpiMuted, fontSize: 11),
                  ),
                ),
                TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => _KpiProductDialog(
                      branch: branch,
                      totals: totals,
                      projects: _report.projects,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: _kpiBlue,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Product details',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 5),
                      Icon(Icons.arrow_forward_rounded, size: 15),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() => Padding(
    padding: const EdgeInsets.all(30),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            color: _kpiBlue.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(22),
          ),
          child: const Icon(
            Icons.query_stats_rounded,
            color: _kpiBlue,
            size: 32,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          widget.loadError.isNotEmpty && _report.projects.isEmpty
              ? 'Your analysis will appear once the projects are loaded.'
              : _report.projects.isEmpty
              ? 'Select KPI projects to compare.'
              : 'No matching branches.',
          style: const TextStyle(
            color: _kpiInk,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _report.projects.isEmpty
              ? 'Choose your quarters to see accuracy and branch performance.'
              : 'Try another branch name or check the selected projects.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: _kpiMuted, fontSize: 13),
        ),
      ],
    ),
  );
}

class _KpiBranchPlaceholder extends StatelessWidget {
  const _KpiBranchPlaceholder();

  @override
  Widget build(BuildContext context) {
    Widget block(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xffeaf0f7),
        borderRadius: BorderRadius.circular(8),
      ),
    );
    return Semantics(
      label: 'Loading branch performance',
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: _kpiSurface(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                block(40, 40),
                const SizedBox(width: 12),
                Expanded(child: block(120, 14)),
                const SizedBox(width: 24),
                block(58, 28),
              ],
            ),
            const SizedBox(height: 23),
            block(120, 12),
            const SizedBox(height: 12),
            const FractionallySizedBox(
              widthFactor: 1,
              child: SizedBox(
                height: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: Color(0xffedf2f8)),
                ),
              ),
            ),
            const SizedBox(height: 19),
            Wrap(
              spacing: 9,
              children: [block(62, 23), block(55, 23), block(64, 23)],
            ),
            const Spacer(),
            block(110, 13),
          ],
        ),
      ),
    );
  }
}

const _kpiInk = Color(0xff182f48);
const _kpiMuted = Color(0xff708197);
const _kpiBlue = Color(0xff397cce);
const _kpiTeal = Color(0xff178f85);
const _kpiCanvas = Color(0xfff5f8fc);

Duration _kpiDuration(BuildContext context, int milliseconds) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

Color _kpiScoreColor(double? accuracy) => accuracy == null
    ? _kpiMuted
    : accuracy >= 90
    ? _kpiTeal
    : accuracy >= 75
    ? _kpiBlue
    : const Color(0xffc17e24);

BoxDecoration _kpiSurface({bool hovered = false}) => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(18),
  border: Border.all(
    color: hovered ? const Color(0xffb5cdeb) : const Color(0xffe6ecf4),
  ),
  boxShadow: [
    BoxShadow(
      color: _kpiInk.withValues(alpha: hovered ? .10 : .045),
      blurRadius: hovered ? 22 : 14,
      offset: Offset(0, hovered ? 9 : 4),
    ),
  ],
);

Widget _kpiPill(String text, Color color, {bool large = false}) => Container(
  padding: EdgeInsets.symmetric(
    horizontal: large ? 11 : 9,
    vertical: large ? 7 : 5,
  ),
  decoration: BoxDecoration(
    color: color.withValues(alpha: .09),
    borderRadius: BorderRadius.circular(9),
  ),
  child: Text(
    text,
    style: TextStyle(
      color: color,
      fontSize: large ? 17 : 10,
      fontWeight: FontWeight.w700,
    ),
  ),
);

InputDecoration _kpiInput(String label, IconData icon) => InputDecoration(
  labelText: label,
  prefixIcon: Icon(icon, size: 20, color: _kpiMuted),
  filled: true,
  fillColor: Colors.white,
  labelStyle: const TextStyle(color: _kpiMuted, fontSize: 13),
  isDense: true,
  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: Color(0xffdce5f0)),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: _kpiBlue, width: 1.5),
  ),
);

class _KpiEntrance extends StatelessWidget {
  final Widget child;
  final int delay;
  const _KpiEntrance({super.key, required this.child, this.delay = 0});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: _kpiDuration(context, 400 + delay),
    curve: Curves.easeOutCubic,
    child: child,
    builder: (_, value, child) => Opacity(
      opacity: value,
      child: Transform.translate(
        offset: Offset(0, 12 * (1 - value)),
        child: child,
      ),
    ),
  );
}

class _KpiHoverCard extends StatefulWidget {
  final Widget child;
  const _KpiHoverCard({required this.child});
  @override
  State<_KpiHoverCard> createState() => _KpiHoverCardState();
}

class _KpiHoverCardState extends State<_KpiHoverCard> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: AnimatedContainer(
      duration: _kpiDuration(context, 180),
      curve: Curves.easeOut,
      transform: Matrix4.translationValues(0, _hovered ? -3 : 0, 0),
      decoration: _kpiSurface(hovered: _hovered),
      child: widget.child,
    ),
  );
}

class _KpiProductDialog extends StatefulWidget {
  final String branch;
  final StockCheckKpiTotals totals;
  final List<StockCheckCampaign> projects;
  const _KpiProductDialog({
    required this.branch,
    required this.totals,
    required this.projects,
  });

  @override
  State<_KpiProductDialog> createState() => _KpiProductDialogState();
}

class _KpiProductDialogState extends State<_KpiProductDialog> {
  final _horizontal = ScrollController();
  String _search = '';
  String _filter = 'All products';

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final needle = _search.trim().toLowerCase();
    final items = widget.totals.items
        .where(
          (item) =>
              (item.code.toLowerCase().contains(needle) ||
                  item.name.toLowerCase().contains(needle)) &&
              switch (_filter) {
                '100%' => item.score == 100,
                '0%' => item.score == 0,
                'Awaiting / review' => !item.scorable,
                'Shared' => item.shared,
                'Single project' => !item.shared,
                _ => true,
              },
        )
        .toList();
    final tableWidth = 580.0 + 260 * widget.projects.length;
    return Dialog(
      backgroundColor: Colors.white,
      elevation: 24,
      shadowColor: _kpiInk.withValues(alpha: .18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: math.min(1600, screen.width - 48),
        height: screen.height * .85,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _kpiBlue.withValues(alpha: .09),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.inventory_2_outlined,
                      color: _kpiBlue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${widget.branch} — ${_percent(widget.totals.accuracy)} KPI accuracy',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: _kpiInk,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Close',
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Text(
                'Difference = Actual − System. Difference between quarters = largest − smallest included Difference; a single-project product uses its own Difference. Missing products do not lower the score.',
                style: TextStyle(color: _kpiMuted, fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: _kpiInput(
                        'Search item code or name',
                        Icons.search_rounded,
                      ),
                      onChanged: (value) => setState(() => _search = value),
                    ),
                  ),
                  const SizedBox(width: 16),
                  DropdownButton<String>(
                    borderRadius: BorderRadius.circular(14),
                    dropdownColor: Colors.white,
                    style: const TextStyle(color: _kpiInk, fontSize: 13),
                    underline: const SizedBox(),
                    value: _filter,
                    items:
                        [
                              'All products',
                              '100%',
                              '0%',
                              'Awaiting / review',
                              'Shared',
                              'Single project',
                            ]
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                    onChanged: (value) => setState(() => _filter = value!),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${items.length} products shown • ${widget.totals.correct} / ${widget.totals.scored} scored in this branch',
                style: const TextStyle(color: _kpiMuted, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => Scrollbar(
                    controller: _horizontal,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _horizontal,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: math.max(tableWidth, constraints.maxWidth),
                        height: constraints.maxHeight - 12,
                        child: Column(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: _kpiInk,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              height: 60,
                              child: Row(
                                children: [
                                  _cell(
                                    320,
                                    const Text(
                                      'Product / item code',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  for (final project in widget.projects)
                                    _cell(
                                      _projectWidth(constraints.maxWidth),
                                      Text(
                                        project.period.isEmpty
                                            ? project.title
                                            : project.period,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  _cell(
                                    160,
                                    Tooltip(
                                      message: widget.projects
                                          .map(
                                            (project) => project.period.isEmpty
                                                ? project.title
                                                : project.period,
                                          )
                                          .join(' vs '),
                                      child: const Text(
                                        'Difference between quarters',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                  _cell(
                                    100,
                                    const Text(
                                      'Accuracy %',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: items.isEmpty
                                  ? const Center(
                                      child: Text('No matching products.'),
                                    )
                                  : ListView.builder(
                                      itemCount: items.length,
                                      itemExtent: 122,
                                      itemBuilder: (_, index) {
                                        final item = items[index];
                                        return Container(
                                          decoration: BoxDecoration(
                                            color: index.isEven
                                                ? Colors.white
                                                : const Color(0xfff8fafc),
                                            border: const Border(
                                              bottom: BorderSide(
                                                color: Color(0xffe2e8f0),
                                              ),
                                            ),
                                          ),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              _cell(
                                                320,
                                                Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      item.name,
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                    Text(item.code),
                                                    Text(
                                                      item.shared
                                                          ? 'Shared • ${item.projectCount} projects'
                                                          : 'Single project',
                                                      style: const TextStyle(
                                                        color: Color(
                                                          0xff64748b,
                                                        ),
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              for (final project
                                                  in widget.projects)
                                                _projectCell(
                                                  item,
                                                  project,
                                                  width: _projectWidth(
                                                    constraints.maxWidth,
                                                  ),
                                                ),
                                              _cell(
                                                160,
                                                Text(
                                                  _qty(
                                                    item.comparisonDifference,
                                                  ),
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    color:
                                                        item.comparisonDifference !=
                                                                null &&
                                                            item.comparisonDifference!
                                                                    .abs() >
                                                                StockCheckKpiItem
                                                                    .tolerance
                                                        ? const Color(
                                                            0xffb91c1c,
                                                          )
                                                        : _kpiInk,
                                                  ),
                                                ),
                                              ),
                                              _cell(
                                                100,
                                                _kpiPill(
                                                  item.score == null
                                                      ? 'Awaiting /\nreview'
                                                      : '${item.score}%',
                                                  item.accurate
                                                      ? _kpiTeal
                                                      : item.scorable
                                                      ? const Color(0xffb94747)
                                                      : const Color(0xffa46a16),
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
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cell(double width, Widget child) => SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Align(alignment: Alignment.centerLeft, child: child),
    ),
  );

  double _projectWidth(double available) => widget.projects.isEmpty
      ? 260
      : math.max(260, (available - 580) / widget.projects.length);

  Widget _projectCell(
    StockCheckKpiItem item,
    StockCheckCampaign project, {
    double width = 260,
  }) {
    final row = item.rowFor(project.id);
    if (row == null) {
      return _cell(
        width,
        const Text('Not included', style: TextStyle(color: Color(0xff64748b))),
      );
    }
    final counted = StockCheckKpiItem.counted(row);
    final difference = counted ? row.variance : null;
    return _cell(
      width,
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'System: ${_qty(row.systemQty)}  Actual: ${_qty(row.actualQty)}',
          ),
          Text(
            'Difference: ${_qty(difference)}',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: difference == null
                  ? const Color(0xff64748b)
                  : difference.abs() <= StockCheckKpiItem.tolerance
                  ? const Color(0xff15803d)
                  : const Color(0xffb91c1c),
            ),
          ),
          if (!counted || item.hasDuplicates)
            Text(
              item.hasDuplicates
                  ? 'Duplicate rows — needs review'
                  : 'Awaiting submitted count',
              style: const TextStyle(fontSize: 12, color: Color(0xffa16207)),
            ),
        ],
      ),
    );
  }
}
