part of '../zone_manager_page.dart';

extension _ZoneStockCheckPageView on _ZoneManagerPageState {
  Future<void> _exportStockChecks(
    List<StockCheckTask> rows,
    String title,
  ) async {
    if (rows.isEmpty) return;
    setState(() => _busy = true);
    try {
      await StockCheckExcelExporter.export(rows: rows, title: title);
    } catch (error) {
      _message('Stock Check export failed: $error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget buildZoneStockCheckPage() {
    if (_stockCheckLoading && _stockChecks.isEmpty) {
      return const _ReportLoading(label: 'Loading Stock Check results...');
    }
    if (_stockCheckError != null && _stockChecks.isEmpty) {
      return _DailyOrderError(
        title: 'Stock Check could not be loaded',
        message: _stockCheckError!,
        onRetry: _loadStockChecks,
      );
    }
    final branchRows = _stockChecks
        .where(
          (row) =>
              _selectedBranch == 'ALL' || row.branchName == _selectedBranch,
        )
        .toList(growable: false);
    if (_selectedStockCheckBatchId == null) {
      return _stockCheckProjectsOverview(branchRows);
    }
    final query = _query.trim().toLowerCase();
    final rows = branchRows
        .where((row) {
          if (row.batchId != _selectedStockCheckBatchId) return false;
          if (query.isEmpty) return true;
          return row.title.toLowerCase().contains(query) ||
              row.branchName.toLowerCase().contains(query) ||
              row.itemCode.toLowerCase().contains(query) ||
              row.itemName.toLowerCase().contains(query) ||
              row.status.toLowerCase().contains(query) ||
              row.submittedByName.toLowerCase().contains(query);
        })
        .toList(growable: false);
    final tableRows = rows
        .map(
          (row) => <String, dynamic>{
            'title': row.title,
            'branch_name': row.branchName,
            'item_code': row.itemCode,
            'item_name': row.itemName,
            'system_qty': row.systemQty,
            'actual_qty': row.actualQty,
            'diff': row.variance,
            'status': row.isSubmitted ? 'Submitted' : 'Pending',
            'submitted_by_name': row.submittedByName,
            'submitted_at': row.submittedAt?.toIso8601String(),
          },
        )
        .toList(growable: false);
    const columns = [
      _ColumnDef('title', 'Project'),
      _ColumnDef('branch_name', 'Branch'),
      _ColumnDef('item_code', 'Item Code'),
      _ColumnDef('item_name', 'Item Name'),
      _ColumnDef('system_qty', 'System Qty'),
      _ColumnDef('actual_qty', 'Actual Qty'),
      _ColumnDef('diff', 'Variance'),
      _ColumnDef('status', 'Status'),
      _ColumnDef('submitted_by_name', 'Submitted By'),
      _ColumnDef('submitted_at', 'Submitted At'),
    ];
    final submitted = rows.where((row) => row.isSubmitted).length;
    final pending = rows.length - submitted;
    final mismatches = rows
        .where((row) => (row.variance ?? 0).abs() > .01)
        .length;
    final entireProjectRows = _stockChecks
        .where((row) => row.batchId == _selectedStockCheckBatchId)
        .toList(growable: false);
    final projectTitle = entireProjectRows.isEmpty
        ? 'Stock Check Project'
        : entireProjectRows.first.title;
    return _ReportPage(
      title: projectTitle,
      subtitle:
          'Stock Check project details • ${rows.length} visible item checks.',
      accent: const Color(0xff0EA5E9),
      rows: tableRows,
      columns: columns,
      kpis: [
        _ReportKpi(
          Icons.folder_copy_outlined,
          'Items',
          '${rows.length}',
          'Items in this project',
          const Color(0xff2563EB),
        ),
        _ReportKpi(
          Icons.task_alt_rounded,
          'Submitted',
          '$submitted',
          'Completed item checks',
          const Color(0xff16A34A),
        ),
        _ReportKpi(
          Icons.pending_actions_rounded,
          'Pending',
          '$pending',
          'Awaiting branch completion',
          const Color(0xffF59E0B),
        ),
        _ReportKpi(
          Icons.warning_amber_rounded,
          'Stock Variances',
          '$mismatches',
          'Submitted items with variance',
          const Color(0xffEF4444),
        ),
      ],
      extraActions: [
        OutlinedButton.icon(
          onPressed: () => setState(() => _selectedStockCheckBatchId = null),
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Back to Projects'),
        ),
        OutlinedButton.icon(
          onPressed: entireProjectRows.isEmpty
              ? null
              : () => _exportStockChecks(
                  entireProjectRows,
                  'Stock_Check_${_safe(projectTitle)}_All_Branches',
                ),
          icon: const Icon(Icons.archive_outlined),
          label: const Text('Download Full Project'),
        ),
      ],
      exportLabel: _selectedBranch == 'ALL'
          ? 'Download Visible'
          : 'Download Branch',
      onExport: () => _exportStockChecks(
        rows,
        _selectedBranch == 'ALL'
            ? 'Stock_Check_${_safe(widget.zoneName)}_Visible'
            : 'Stock_Check_${_safe(projectTitle)}_${_safe(_selectedBranch)}',
      ),
    );
  }

  Widget _stockCheckProjectsOverview(List<StockCheckTask> branchRows) {
    final query = _query.trim().toLowerCase();
    final groups = <String, List<StockCheckTask>>{};
    for (final row in branchRows) {
      groups.putIfAbsent(row.batchId, () => []).add(row);
    }
    final projects =
        groups.entries
            .map(
              (entry) => _StockCheckProjectSummary(
                batchId: entry.key,
                rows: entry.value,
              ),
            )
            .where((project) {
              if (query.isEmpty) return true;
              return project.title.toLowerCase().contains(query) ||
                  project.branches.any(
                    (branch) => branch.toLowerCase().contains(query),
                  ) ||
                  project.rows.any(
                    (row) =>
                        row.itemCode.toLowerCase().contains(query) ||
                        row.itemName.toLowerCase().contains(query),
                  );
            })
            .toList()
          ..sort((left, right) => right.sentAt.compareTo(left.sentAt));
    final visibleRows = projects
        .expand((project) => project.rows)
        .toList(growable: false);
    final submitted = visibleRows.where((row) => row.isSubmitted).length;
    final pending = visibleRows.length - submitted;
    final variances = visibleRows
        .where((row) => (row.variance ?? 0).abs() > .01)
        .length;
    return Column(
      children: [
        _ModernPageHero(
          icon: Icons.folder_copy_outlined,
          eyebrow: 'STOCK CHECK CENTER',
          title: 'Stock Check Projects',
          subtitle:
              '${widget.zoneName} • ${_selectedBranch == 'ALL' ? 'All branches' : _selectedBranch} • Open a project to view its item details.',
          accent: const Color(0xff0EA5E9),
          metrics: const [],
          actions: [
            FilledButton.icon(
              onPressed: branchRows.isEmpty
                  ? null
                  : () => _exportStockChecks(
                      branchRows,
                      _selectedBranch == 'ALL'
                          ? 'Stock_Check_${_safe(widget.zoneName)}_All_Projects'
                          : 'Stock_Check_${_safe(_selectedBranch)}_All_Projects',
                    ),
              icon: const Icon(Icons.download_rounded),
              label: Text(
                _selectedBranch == 'ALL'
                    ? 'Download All Zone'
                    : 'Download Branch Projects',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _ReportKpiStrip(
          kpis: [
            _ReportKpi(
              Icons.folder_copy_outlined,
              'Projects',
              '${projects.length}',
              'Visible Stock Check projects',
              const Color(0xff2563EB),
            ),
            _ReportKpi(
              Icons.task_alt_rounded,
              'Submitted',
              '$submitted',
              'Completed item checks',
              const Color(0xff16A34A),
            ),
            _ReportKpi(
              Icons.pending_actions_rounded,
              'Pending',
              '$pending',
              'Awaiting completion',
              const Color(0xffF59E0B),
            ),
            _ReportKpi(
              Icons.warning_amber_rounded,
              'Stock Variances',
              '$variances',
              'Items with stock variance',
              const Color(0xffEF4444),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: projects.isEmpty
              ? const _EmptyState(color: Color(0xff0EA5E9))
              : GridView.builder(
                  padding: const EdgeInsets.only(bottom: 8),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 430,
                    mainAxisExtent: 238,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: projects.length,
                  itemBuilder: (context, index) => _StockCheckProjectCard(
                    project: projects[index],
                    onOpen: () => setState(
                      () =>
                          _selectedStockCheckBatchId = projects[index].batchId,
                    ),
                    onDownload: () => _exportStockChecks(
                      projects[index].rows,
                      'Stock_Check_${_safe(projects[index].title)}',
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _StockCheckProjectSummary {
  final String batchId;
  final List<StockCheckTask> rows;

  const _StockCheckProjectSummary({required this.batchId, required this.rows});

  String get title => rows.isEmpty ? 'Untitled Stock Check' : rows.first.title;
  Set<String> get branches => rows.map((row) => row.branchName).toSet();
  int get submitted => rows.where((row) => row.isSubmitted).length;
  int get pending => rows.length - submitted;
  int get variances =>
      rows.where((row) => (row.variance ?? 0).abs() > .01).length;
  double get completion => rows.isEmpty ? 0 : submitted / rows.length;
  DateTime get sentAt => rows
      .map((row) => row.sentAt ?? DateTime(1970))
      .fold(
        DateTime(1970),
        (latest, date) => date.isAfter(latest) ? date : latest,
      );
}

class _StockCheckProjectCard extends StatelessWidget {
  final _StockCheckProjectSummary project;
  final VoidCallback onOpen, onDownload;

  const _StockCheckProjectCard({
    required this.project,
    required this.onOpen,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final complete = project.pending == 0 && project.rows.isNotEmpty;
    final statusColor = complete
        ? const Color(0xff16A34A)
        : const Color(0xffF59E0B);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xff0F2942).withValues(alpha: .055),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
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
                  color: const Color(0xff0EA5E9).withValues(alpha: .11),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.folder_copy_outlined,
                  color: Color(0xff0284C7),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  complete ? 'Completed' : 'In Progress',
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Text(
            project.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.secondaryColor,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${project.branches.length} branch${project.branches.length == 1 ? '' : 'es'} • ${project.rows.length} items • ${DateFormat('dd MMM yyyy').format(project.sentAt.toLocal())}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.subText, fontSize: 10.5),
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              _ProjectMiniMetric(
                'Submitted',
                project.submitted,
                const Color(0xff16A34A),
              ),
              _ProjectMiniMetric(
                'Pending',
                project.pending,
                const Color(0xffF59E0B),
              ),
              _ProjectMiniMetric(
                'Variance',
                project.variances,
                const Color(0xffEF4444),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: project.completion,
              minHeight: 6,
              backgroundColor: const Color(0xffE2E8F0),
              color: statusColor,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('Open Project'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                onPressed: onDownload,
                tooltip: 'Download project',
                icon: const Icon(Icons.download_rounded, size: 19),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProjectMiniMetric extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _ProjectMiniMetric(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$value',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: color,
            fontSize: 14,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: AppColors.subText, fontSize: 9),
        ),
      ],
    ),
  );
}
