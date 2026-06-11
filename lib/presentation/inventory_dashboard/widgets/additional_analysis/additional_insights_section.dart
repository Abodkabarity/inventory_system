import 'package:flutter/material.dart';

import 'glass_container.dart';

class AdditionalInsightsSection extends StatelessWidget {
  final Map<String, dynamic> data;

  const AdditionalInsightsSection({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final reasons = List<Map<String, dynamic>>.from(data['reasons'] ?? []);
    final statusDist = List<Map<String, dynamic>>.from(
      data['status_distribution'] ?? [],
    );
    final zones = List<Map<String, dynamic>>.from(data['zone_analysis'] ?? []);
    final purchaseTypes = List<Map<String, dynamic>>.from(
      data['purchase_types'] ?? [],
    );
    final topUsers = List<Map<String, dynamic>>.from(data['top_users'] ?? []);
    final branchPerf = List<Map<String, dynamic>>.from(
      data['branch_performance'] ?? [],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Additional Insights',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _ReasonsCard(reasons: reasons)),
            const SizedBox(width: 24),
            Expanded(child: _StatusCard(statuses: statusDist)),
          ],
        ),
        const SizedBox(height: 24),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _ZoneCard(zones: zones)),
            const SizedBox(width: 24),
            Expanded(child: _PurchaseTypeCard(types: purchaseTypes)),
          ],
        ),
        const SizedBox(height: 24),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 1, child: _TopUsersCard(users: topUsers)),
            const SizedBox(width: 24),
            Expanded(
              flex: 2,
              child: _BranchPerformanceCard(branches: branchPerf),
            ),
          ],
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REASONS CARD
// ─────────────────────────────────────────────────────────────────────────────
class _ReasonsCard extends StatelessWidget {
  final List<Map<String, dynamic>> reasons;
  const _ReasonsCard({required this.reasons});

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            Icons.info_outline,
            'Most Common Reasons',
            const Color(0xffF59E0B),
          ),
          const SizedBox(height: 16),
          if (reasons.isEmpty)
            const _EmptyState()
          else
            ...reasons.map((r) {
              final pct = (r['percent'] ?? 0.0) as num;
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            r['reason']?.toString() ?? 'Unknown',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${r['count']}  •  ${pct.toStringAsFixed(1)}%',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (pct / 100).clamp(0.0, 1.0),
                        minHeight: 6,
                        backgroundColor: const Color(0xff374151),
                        color: const Color(0xffF59E0B),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STATUS DISTRIBUTION CARD
// ─────────────────────────────────────────────────────────────────────────────
class _StatusCard extends StatelessWidget {
  final List<Map<String, dynamic>> statuses;
  const _StatusCard({required this.statuses});

  static const _statusColors = <String, Color>{
    'submitted': Color(0xff6B7280),
    'pending_inventory': Color(0xffF59E0B),
    'approved': Color(0xff10B981),
    'rejected': Color(0xffEF4444),
    'sent_to_store': Color(0xff3B82F6),
    'done': Color(0xff06B6D4),
  };

  static const _statusLabels = <String, String>{
    'submitted': 'Submitted',
    'pending_inventory': 'Pending Inventory',
    'approved': 'Approved',
    'rejected': 'Rejected',
    'sent_to_store': 'Sent to Store',
    'done': 'Done',
  };

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            Icons.donut_large,
            'Status Distribution',
            const Color(0xff3B82F6),
          ),
          const SizedBox(height: 16),
          if (statuses.isEmpty)
            const _EmptyState()
          else
            ...statuses.map((s) {
              final statusKey = s['status']?.toString() ?? '';
              final color = _statusColors[statusKey] ?? const Color(0xff6B7280);
              final label = _statusLabels[statusKey] ?? _capitalize(statusKey);
              final pct = (s['percent'] ?? 0.0) as num;
              final count = s['count'] ?? 0;

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Text(
                          '$count',
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 44,
                          child: Text(
                            '${pct.toStringAsFixed(1)}%',
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (pct / 100).clamp(0.0, 1.0),
                        minHeight: 5,
                        backgroundColor: const Color(0xff374151),
                        color: color,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1).replaceAll('_', ' ');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ZONE ANALYSIS CARD
// ─────────────────────────────────────────────────────────────────────────────
class _ZoneCard extends StatelessWidget {
  final List<Map<String, dynamic>> zones;
  const _ZoneCard({required this.zones});

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            Icons.map_outlined,
            'Zone Analysis',
            const Color(0xff14B8A6),
          ),
          const SizedBox(height: 16),
          if (zones.isEmpty)
            const _EmptyState()
          else ...[
            // Table header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xff1F2937),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Zone',
                      style: TextStyle(
                        color: Colors.white60,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Requests',
                      style: TextStyle(
                        color: Colors.white60,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Qty',
                      style: TextStyle(
                        color: Colors.white60,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Approval %',
                      style: TextStyle(
                        color: Colors.white60,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            ...zones.map((z) {
              final rate = (z['approval_rate'] ?? 0.0) as num;
              final rateColor = rate >= 70
                  ? const Color(0xff10B981)
                  : rate >= 40
                  ? const Color(0xffF59E0B)
                  : const Color(0xffEF4444);

              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                  color: const Color(0xff111827),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        z['zone']?.toString() ?? '—',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${z['requests']}',
                        style: const TextStyle(
                          color: Color(0xff06B6D4),
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${z['qty']}',
                        style: const TextStyle(
                          color: Color(0xff14B8A6),
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: rateColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${rate.toStringAsFixed(1)}%',
                            style: TextStyle(
                              color: rateColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PURCHASE TYPE CARD
// ─────────────────────────────────────────────────────────────────────────────
class _PurchaseTypeCard extends StatelessWidget {
  final List<Map<String, dynamic>> types;
  const _PurchaseTypeCard({required this.types});

  static const _palette = [
    Color(0xff8B5CF6),
    Color(0xffF97316),
    Color(0xff06B6D4),
    Color(0xff10B981),
    Color(0xffF59E0B),
    Color(0xffEF4444),
    Color(0xff3B82F6),
    Color(0xffEC4899),
  ];

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            Icons.category_outlined,
            'Purchase Type Analysis',
            const Color(0xff8B5CF6),
          ),
          const SizedBox(height: 16),
          if (types.isEmpty)
            const _EmptyState()
          else
            ...types.asMap().entries.map((entry) {
              final i = entry.key;
              final t = entry.value;
              final color = _palette[i % _palette.length];
              final requests = (t['requests'] as num?) ?? 0;
              final qty = (t['qty'] as num?) ?? 0;

              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: const Color(0xff111827),
                  borderRadius: BorderRadius.circular(10),
                  border: Border(left: BorderSide(color: color, width: 3)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        t['type']?.toString() ?? 'Unknown',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _pill('$requests req', color),
                    const SizedBox(width: 6),
                    _pill('Qty $qty', const Color(0xff14B8A6)),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TOP USERS CARD
// ─────────────────────────────────────────────────────────────────────────────
class _TopUsersCard extends StatelessWidget {
  final List<Map<String, dynamic>> users;
  const _TopUsersCard({required this.users});

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            Icons.people_outline,
            'Top Requesting Users',
            const Color(0xff06B6D4),
          ),
          const SizedBox(height: 16),
          if (users.isEmpty)
            const _EmptyState()
          else
            ...users.asMap().entries.map((entry) {
              final i = entry.key;
              final u = entry.value;
              final requests = (u['requests'] as num?) ?? 0;

              final rankColor = i == 0
                  ? const Color(0xffF59E0B)
                  : i == 1
                  ? const Color(0xff9CA3AF)
                  : i == 2
                  ? const Color(0xffB45309)
                  : const Color(0xff4B5563);

              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: const Color(0xff111827),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: rankColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '#${i + 1}',
                        style: TextStyle(
                          color: rankColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        u['user']?.toString() ?? '—',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xff06B6D4).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xff06B6D4).withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        '$requests',
                        style: const TextStyle(
                          color: Color(0xff06B6D4),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BRANCH PERFORMANCE CARD
// ─────────────────────────────────────────────────────────────────────────────
class _BranchPerformanceCard extends StatefulWidget {
  final List<Map<String, dynamic>> branches;
  const _BranchPerformanceCard({required this.branches});

  @override
  State<_BranchPerformanceCard> createState() => _BranchPerformanceCardState();
}

class _BranchPerformanceCardState extends State<_BranchPerformanceCard> {
  String _search = '';
  String _sortBy = 'total';
  bool _ascending = false;

  List<Map<String, dynamic>> get _filtered {
    var list = widget.branches.where((b) {
      return (b['branch_name'] ?? '').toString().toLowerCase().contains(
        _search.toLowerCase(),
      );
    }).toList();

    list.sort((a, b) {
      final va = (a[_sortBy] ?? 0) as num;
      final vb = (b[_sortBy] ?? 0) as num;
      return _ascending ? va.compareTo(vb) : vb.compareTo(va);
    });

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;

    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              const Icon(Icons.leaderboard, color: Color(0xffF97316), size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Branch Performance',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              // Sort by dropdown
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xff1F2937),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButton<String>(
                  value: _sortBy,
                  dropdownColor: const Color(0xff1F2937),
                  underline: const SizedBox(),
                  isDense: true,
                  style: const TextStyle(
                    color: Color(0xffF97316),
                    fontSize: 12,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'total',
                      child: Text('Sort: Total'),
                    ),
                    DropdownMenuItem(
                      value: 'approved',
                      child: Text('Sort: Approved'),
                    ),
                    DropdownMenuItem(
                      value: 'rejected',
                      child: Text('Sort: Rejected'),
                    ),
                    DropdownMenuItem(value: 'done', child: Text('Sort: Done')),

                    DropdownMenuItem(
                      value: 'completion_rate',
                      child: Text('Sort: Completion %'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _sortBy = v);
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Asc/Desc toggle
              GestureDetector(
                onTap: () => setState(() => _ascending = !_ascending),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xff1F2937),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _ascending ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 14,
                    color: const Color(0xffF97316),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Search
              SizedBox(
                width: 180,
                child: TextField(
                  onChanged: (v) => setState(() => _search = v),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Filter branch...',
                    hintStyle: const TextStyle(
                      color: Colors.white38,
                      fontSize: 13,
                    ),
                    prefixIcon: const Icon(
                      Icons.search,
                      color: Colors.white38,
                      size: 16,
                    ),
                    filled: true,
                    fillColor: const Color(0xff1F2937),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (list.isEmpty)
            const _EmptyState()
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStatePropertyAll(
                  const Color(0xff1F2937),
                ),
                dataRowColor: WidgetStatePropertyAll(const Color(0xff111827)),
                dividerThickness: 1,
                horizontalMargin: 16,
                columnSpacing: 32,
                headingTextStyle: const TextStyle(
                  color: Colors.white60,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                columns: const [
                  DataColumn(label: Text('Branch')),
                  DataColumn(label: Text('Total'), numeric: true),
                  DataColumn(label: Text('Approved'), numeric: true),
                  DataColumn(label: Text('Rejected'), numeric: true),
                  DataColumn(label: Text('Done'), numeric: true),
                  DataColumn(label: Text('Approval %'), numeric: true),
                  DataColumn(label: Text('Completion %'), numeric: true),
                ],
                rows: list.map((b) {
                  final approvalRate = (b['approval_rate'] ?? 0.0) as num;
                  final completionRate = (b['completion_rate'] ?? 0.0) as num;

                  return DataRow(
                    cells: [
                      DataCell(
                        Text(
                          b['branch_name']?.toString() ?? '',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          '${b['total']}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                      DataCell(
                        Text(
                          '${b['approved']}',
                          style: const TextStyle(
                            color: Color(0xff10B981),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          '${b['rejected']}',
                          style: const TextStyle(
                            color: Color(0xffEF4444),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          '${b['done']}',
                          style: const TextStyle(
                            color: Color(0xff06B6D4),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      DataCell(
                        _pctBadge(approvalRate, const Color(0xff10B981)),
                      ),
                      DataCell(
                        _pctBadge(completionRate, const Color(0xff3B82F6)),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pctBadge(num value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '${value.toStringAsFixed(1)}%',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED HELPERS
// ─────────────────────────────────────────────────────────────────────────────
Widget _sectionHeader(IconData icon, String title, Color color) {
  return Row(
    children: [
      Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 16),
      ),
      const SizedBox(width: 10),
      Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.bold,
        ),
      ),
    ],
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.inbox_outlined, color: Colors.white12, size: 36),
            SizedBox(height: 8),
            Text(
              'No data available',
              style: TextStyle(color: Colors.white24, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
