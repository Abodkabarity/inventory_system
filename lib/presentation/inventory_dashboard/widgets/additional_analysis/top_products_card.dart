import 'package:flutter/material.dart';

import 'glass_container.dart';
import 'product_branch_dialog.dart';

class TopProductsCard extends StatefulWidget {
  final List<Map<String, dynamic>> products;

  const TopProductsCard({super.key, required this.products});

  @override
  State<TopProductsCard> createState() => _TopProductsCardState();
}

class _TopProductsCardState extends State<TopProductsCard> {
  String _search = '';
  bool _sortByQty = false;
  bool _ascending = false;

  List<Map<String, dynamic>> get _filtered {
    var list = widget.products.where((p) {
      final name = (p['item_name'] ?? '').toString().toLowerCase();
      final code = (p['item_code'] ?? '').toString().toLowerCase();
      final q = _search.toLowerCase();
      return name.contains(q) || code.contains(q);
    }).toList();

    list.sort((a, b) {
      final va = _sortByQty
          ? (a['qty'] as num?) ?? 0
          : (a['requests'] as num?) ?? 0;
      final vb = _sortByQty
          ? (b['qty'] as num?) ?? 0
          : (b['requests'] as num?) ?? 0;
      return _ascending ? va.compareTo(vb) : vb.compareTo(va);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;

    return GlassContainer(
      child: Column(
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.medication, color: Color(0xff8B5CF6)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Most Requested Products',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              // Sort mode
              GestureDetector(
                onTap: () => setState(() => _sortByQty = !_sortByQty),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xff1F2937),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _sortByQty ? 'By Qty' : 'By Requests',
                    style: const TextStyle(
                      color: Color(0xff8B5CF6),
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Asc/Desc
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
                    color: const Color(0xff8B5CF6),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Search
          TextField(
            onChanged: (v) => setState(() => _search = v),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search by code or name...',
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.search, color: Colors.white38),
              filled: true,
              fillColor: const Color(0xff1F2937),
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
                      'No products found',
                      style: TextStyle(color: Colors.white38),
                    ),
                  )
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final row = list[i];
                      return InkWell(
                        onTap: () => showDialog(
                          context: context,
                          builder: (_) => ProductBranchDialog(
                            itemName:
                                '${row['item_code'] ?? ''} — ${row['item_name'] ?? ''}',
                            branches: List<Map<String, dynamic>>.from(
                              row['product_branches'] ?? [],
                            ),
                          ),
                        ),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xff1F2937),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xff8B5CF6,
                                  ).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.medication,
                                  color: Color(0xff8B5CF6),
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      row['item_name']?.toString() ?? '',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      row['item_code']?.toString() ?? '',
                                      style: const TextStyle(
                                        color: Colors.white38,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  _badge(
                                    '${row['requests']} req',
                                    const Color(0xff0891B2),
                                  ),
                                  const SizedBox(height: 4),
                                  _badge(
                                    'Qty ${row['qty']}',
                                    const Color(0xff059669),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.chevron_right,
                                color: Colors.white24,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 11)),
    );
  }
}
