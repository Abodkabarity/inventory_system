import 'package:flutter/material.dart';

import '../../../core/utils/store_branch_identity_registry.dart';
import '../../../domain/entities/online_branch_availability.dart';
import '../../../domain/entities/online_overview.dart';
import 'online_overview_grid.dart';
import 'stock_catalog_visuals.dart';

class OnlineAvailabilityDialog extends StatefulWidget {
  final OnlineOverviewSnapshot snapshot;
  final Future<Map<String, dynamic>> Function() load;
  const OnlineAvailabilityDialog({
    super.key,
    required this.snapshot,
    required this.load,
  });

  @override
  State<OnlineAvailabilityDialog> createState() =>
      _OnlineAvailabilityDialogState();
}

class _OnlineAvailabilityDialogState extends State<OnlineAvailabilityDialog> {
  final _search = TextEditingController();
  OnlineAvailabilitySnapshot? _data;
  bool _loading = true, _failed = false;
  String _sort = 'a';
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _request++;
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final response = await widget.load();
      if (!mounted || request != _request) return;
      final data = OnlineAvailabilitySnapshot.fromMap(
        response,
        generation: widget.snapshot.generation,
        approvedBranches: widget.snapshot.branches,
      );
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (_) {
      if (mounted && request == _request) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
    child: SizedBox(
      width: 1100,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(22, 20, 12, 20),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE7EDF5))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE7F7F4),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.bar_chart_rounded,
                    color: catalogTeal,
                    size: 25,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Branch availability',
                        style: TextStyle(
                          color: catalogInk,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${widget.snapshot.branches.length} online branches${_data?.stockDay == null ? '' : ' · Stock as of ${catalogDate(_data!.stockDay)}'}',
                        style: const TextStyle(
                          color: catalogMuted,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close availability',
                  onPressed: () => Navigator.pop(context),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFF2F5FA),
                    foregroundColor: catalogInk,
                  ),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Flexible(
            child: _loading
                ? const SizedBox(
                    height: 280,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: catalogTeal),
                          SizedBox(height: 18),
                          Text(
                            'Loading branch availability…',
                            style: TextStyle(color: catalogInk, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  )
                : _failed
                ? SizedBox(
                    height: 280,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.cloud_off_rounded,
                              color: catalogMuted,
                              size: 38,
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Could not load availability. Try again, or close this window and reload the page.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: catalogInk,
                                fontSize: 16,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _load,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : ValueListenableBuilder<Map<String, String>>(
                    valueListenable: StoreBranchIdentityRegistry.groups,
                    builder: (context, _, _) => Scrollbar(
                      child: SingleChildScrollView(
                        primary: true,
                        padding: const EdgeInsets.all(20),
                        child: LayoutBuilder(
                          builder: (context, size) => _content(size.maxWidth),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    ),
  );

  Widget _content(double width) {
    final data = _data!;
    final query = _search.text.trim().toLowerCase();
    final branches =
        data.branches
            .where(
              (row) => StoreBranchIdentityRegistry.displayName(
                row.branch,
              ).toLowerCase().contains(query),
            )
            .toList()
          ..sort((a, b) {
            if (_sort == 'a') {
              final order = (a.ranks[OnlineRank.a]!.percent ?? 101).compareTo(
                b.ranks[OnlineRank.a]!.percent ?? 101,
              );
              if (order != 0) return order;
            }
            return StoreBranchIdentityRegistry.displayName(
              a.branch,
            ).toLowerCase().compareTo(
              StoreBranchIdentityRegistry.displayName(b.branch).toLowerCase(),
            );
          });
    final summaryWidth = (width - 20) / 3;
    final search = TextField(
      controller: _search,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: 'Search online branches',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: query.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear branch search',
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  _search.clear();
                  setState(() {});
                },
              ),
        filled: true,
        fillColor: const Color(0xFFF8FAFD),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFDDE6F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFDDE6F0)),
        ),
      ),
    );
    final sort = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDE6F0)),
      ),
      child: DropdownButton<String>(
        value: _sort,
        isExpanded: true,
        underline: const SizedBox(),
        icon: const Icon(Icons.sort_rounded, color: catalogMuted),
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: catalogInk, fontSize: 15),
        items: const [
          DropdownMenuItem(value: 'a', child: Text('Lowest A first')),
          DropdownMenuItem(value: 'name', child: Text('Branch name')),
        ],
        onChanged: (value) => setState(() => _sort = value ?? 'a'),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Average availability per branch',
          style: TextStyle(
            color: catalogInk,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final rank in onlineAvailabilityRanks)
              SizedBox(
                width: summaryWidth,
                child: _RankAverage(rank: rank, branches: data.branches),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F7FC),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'Available products ÷ all products in that rank × 100. A product is available when its stock is above 0 in that branch. Uses all A, B and C products, regardless of page filters.',
            style: TextStyle(color: catalogInk, fontSize: 14, height: 1.5),
          ),
        ),
        const SizedBox(height: 18),
        if (width >= 650)
          Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: 12),
              SizedBox(width: 210, child: sort),
            ],
          )
        else ...[
          search,
          const SizedBox(height: 10),
          sort,
        ],
        const SizedBox(height: 12),
        Text(
          '${branches.length} of ${data.branches.length} branches',
          style: const TextStyle(color: catalogMuted, fontSize: 14),
        ),
        const SizedBox(height: 12),
        if (branches.isEmpty)
          const Padding(
            padding: EdgeInsets.all(30),
            child: Text(
              'No matching branches.',
              textAlign: TextAlign.center,
              style: TextStyle(color: catalogInk, fontSize: 16),
            ),
          )
        else
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final branch in branches)
                SizedBox(
                  width: width >= 720 ? (width - 16) / 2 : width,
                  child: _BranchCard(data: branch),
                ),
            ],
          ),
      ],
    );
  }
}

class _RankAverage extends StatelessWidget {
  final OnlineRank rank;
  final List<OnlineBranchAvailability> branches;
  const _RankAverage({required this.rank, required this.branches});
  @override
  Widget build(BuildContext context) {
    final color = onlineRankColor(rank);
    final total = branches.fold<int>(
      0,
      (sum, branch) => sum + branch.ranks[rank]!.total,
    );
    final available = branches.fold<int>(
      0,
      (sum, branch) => sum + branch.ranks[rank]!.available,
    );
    final products = branches.first.ranks[rank]!.total;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withValues(alpha: .06), Colors.white),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: .2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Rank ${rank.label}',
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              total == 0
                  ? '—'
                  : '${(available * 100 / total).toStringAsFixed(1)}%',
              style: TextStyle(
                color: color,
                fontSize: 32,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${catalogQty(products)} products',
            style: const TextStyle(
              color: catalogInk,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _BranchCard extends StatelessWidget {
  final OnlineBranchAvailability data;
  const _BranchCard({required this.data});
  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey('availability-${data.branch}'),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFDFE7F1)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F5FA),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.storefront_outlined,
                color: catalogInk,
                size: 21,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                StoreBranchIdentityRegistry.displayName(data.branch),
                style: const TextStyle(
                  color: catalogInk,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        for (final (index, rank) in onlineAvailabilityRanks.indexed) ...[
          if (index > 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Divider(height: 1, color: Color(0xFFEDF1F7)),
            ),
          _RankBar(data: data.ranks[rank]!),
        ],
      ],
    ),
  );
}

class _RankBar extends StatelessWidget {
  final OnlineRankAvailability data;
  const _RankBar({required this.data});
  @override
  Widget build(BuildContext context) {
    final color = onlineRankColor(data.rank);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                data.rank.label,
                style: TextStyle(
                  color: color,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                data.total == 0
                    ? 'No products'
                    : '${catalogQty(data.available)} of ${catalogQty(data.total)} available',
                style: const TextStyle(
                  color: catalogInk,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              data.percent == null
                  ? '—'
                  : '${data.percent!.toStringAsFixed(1)}%',
              style: TextStyle(
                color: color,
                fontSize: 23,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: (data.percent ?? 0) / 100,
            minHeight: 8,
            color: color,
            backgroundColor: color.withValues(alpha: .09),
          ),
        ),
        if (data.unknown > 0) ...[
          const SizedBox(height: 6),
          Text(
            '${catalogQty(data.unknown)} stock reports missing · not counted as available',
            style: const TextStyle(
              color: Color(0xFFA56510),
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }
}
