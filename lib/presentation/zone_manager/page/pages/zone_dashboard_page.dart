part of '../zone_manager_page.dart';

extension _ZoneDashboardPageView on _ZoneManagerPageState {
  Widget buildZoneDashboardPage() {
    final submitted = _branches
        .where(
          (branch) => _submissions.containsKey(_key(branch['branch_name'])),
        )
        .length;
    final rejected = _additional
        .where((row) => _text(row['status']).toLowerCase().contains('reject'))
        .length;
    final pending = _additional
        .where((row) => _text(row['status']).toLowerCase().contains('pending'))
        .length;
    final sent = _additional
        .where((row) => _text(row['status']).toLowerCase() == 'sent_to_store')
        .length;
    return Column(
      children: [
        _ModernPageHero(
          icon: Icons.hub_rounded,
          eyebrow: 'ZONE OPERATIONS',
          title: '${widget.zoneName} Control Center',
          subtitle:
              'Live branch activity for ${_displayDate(widget.runDate)} • select any branch to inspect its operation.',
          accent: AppColors.primaryColor,
          metrics: [
            _HeroMetric('Branches', '${_branches.length}'),
            _HeroMetric('Submitted', '$submitted'),
            _HeroMetric('Order Edits', '${_edits.length}'),
          ],
          actions: [
            OutlinedButton.icon(
              onPressed: () => _changePage(5),
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text('View Edits'),
            ),
            FilledButton.icon(
              onPressed: () => _changePage(3),
              icon: const Icon(Icons.shopping_cart_checkout_rounded),
              label: const Text('Open Daily Order'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _StatsRow(
          cards: [
            _Stat(
              Icons.store_rounded,
              'Zone Branches',
              '${_branches.length}',
              Colors.deepPurple,
            ),
            _Stat(
              Icons.inventory_rounded,
              'Submitted Orders',
              '$submitted / ${_branches.length}',
              Colors.green,
            ),
            _Stat(
              Icons.add_box_rounded,
              'Additional Today',
              '${_additional.length}',
              Colors.orange,
            ),
            _Stat(
              Icons.cancel_rounded,
              'Rejected Additional',
              '$rejected',
              Colors.redAccent,
            ),
            _Stat(
              Icons.hourglass_bottom_rounded,
              'Pending / Sent To Store',
              '$pending / $sent',
              Colors.deepOrange,
              subtitle: 'Additional workflow',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                SizedBox(
                  width: constraints.maxWidth * .44,
                  child: _BranchGrid(
                    branches: _branches,
                    submissions: _submissions,
                    edits: _edits,
                    additional: _additional,
                    selectedBranch: _selectedBranch,
                    onOpen: _openBranch,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _AdditionalPanel(
                    rows: _filtered(_additional, 'branch_name'),
                    onViewAll: () => _changePage(4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
