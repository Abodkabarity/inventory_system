import 'package:flutter/material.dart';

import 'glass_container.dart';

class TopBranchesCard extends StatefulWidget {
  final List<Map<String, dynamic>> branches;

  const TopBranchesCard({super.key, required this.branches});

  @override
  State<TopBranchesCard> createState() => _TopBranchesCardState();
}

class _TopBranchesCardState extends State<TopBranchesCard> {
  String _search = '';
  bool _ascending = false;

  List<Map<String, dynamic>> get _filtered {
    var list = widget.branches.where((b) {
      final name = (b['branch_name'] ?? '').toString().toLowerCase();
      return name.contains(_search.toLowerCase());
    }).toList();

    list.sort((a, b) {
      final va = (a['requests'] as num?) ?? 0;
      final vb = (b['requests'] as num?) ?? 0;
      return _ascending ? va.compareTo(vb) : vb.compareTo(va);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;

    final maxRequests = list.isNotEmpty
        ? ((list.first['requests'] as num?) ?? 1).toDouble()
        : 1.0;

    return GlassContainer(
      child: Column(
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.store, color: Color(0xff06B6D4)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'All Active Branches',
                  style: TextStyle(
                    color: Color(0xff1E293B),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              // Branches count badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xff06B6D4).withOpacity(0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xff06B6D4).withOpacity(0.3),
                  ),
                ),
                child: Text(
                  '${widget.branches.length} branches',
                  style: const TextStyle(
                    color: Color(0xff06B6D4),
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Sort toggle
              GestureDetector(
                onTap: () => setState(() => _ascending = !_ascending),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xffF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _ascending ? Icons.arrow_upward : Icons.arrow_downward,
                        size: 14,
                        color: const Color(0xff06B6D4),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _ascending ? 'Lowest' : 'Highest',
                        style: const TextStyle(
                          color: Color(0xff06B6D4),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Search
          TextField(
            onChanged: (v) => setState(() => _search = v),
            style: const TextStyle(color: Color(0xff1E293B)),
            decoration: InputDecoration(
              hintText: 'Search branch...',
              hintStyle: const TextStyle(color: Color(0xff94A3B8)),
              prefixIcon: const Icon(Icons.search, color: Color(0xff94A3B8)),
              filled: true,
              fillColor: const Color(0xffF1F5F9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
          const SizedBox(height: 12),

          // List
          Expanded(
            child: list.isEmpty
                ? const Center(
                    child: Text(
                      'No branches found',
                      style: TextStyle(color: Color(0xff94A3B8)),
                    ),
                  )
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final row = list[i];
                      final requests = (row['requests'] as num?) ?? 0;
                      final hasRequests = requests > 0;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: hasRequests
                              ? const Color(0xffF8FAFC)
                              : const Color(0xffF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                          border: hasRequests
                              ? Border.all(color: const Color(0xffE2E8F0))
                              : Border.all(
                                  color: const Color(0xffCBD5E1),
                                  width: 0.5,
                                ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: _rankColor(
                                      i + 1,
                                      hasRequests,
                                    ).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '#${i + 1}',
                                    style: TextStyle(
                                      color: _rankColor(i + 1, hasRequests),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    row['branch_name']?.toString() ?? '',
                                    style: TextStyle(
                                      color: hasRequests
                                          ? const Color(0xff1E293B)
                                          : const Color(0xff94A3B8),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: hasRequests
                                        ? const Color(0xff0891B2)
                                        : const Color(0xffE2E8F0),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    hasRequests
                                        ? '$requests Requests'
                                        : 'No Requests',
                                    style: TextStyle(
                                      color: hasRequests
                                          ? Colors.white
                                          : const Color(0xff94A3B8),
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: maxRequests > 0
                                    ? (requests / maxRequests).clamp(0.0, 1.0)
                                    : 0,
                                minHeight: 4,
                                backgroundColor: const Color(0xffE2E8F0),
                                color: hasRequests
                                    ? const Color(0xff06B6D4)
                                    : const Color(0xffCBD5E1),
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

  Color _rankColor(int rank, bool hasRequests) {
    if (!hasRequests) return const Color(0xff94A3B8);
    if (rank == 1) return const Color(0xffF59E0B);
    if (rank == 2) return const Color(0xff64748B);
    if (rank == 3) return const Color(0xffB45309);
    return const Color(0xff64748B);
  }
}
