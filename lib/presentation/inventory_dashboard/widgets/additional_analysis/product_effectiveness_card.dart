import 'package:flutter/material.dart';

import 'glass_container.dart';
import 'product_effectiveness_dialog.dart';

class ProductEffectivenessCard extends StatefulWidget {
  final List<Map<String, dynamic>> products;

  const ProductEffectivenessCard({super.key, required this.products});

  @override
  State<ProductEffectivenessCard> createState() =>
      _ProductEffectivenessCardState();
}

class _ProductEffectivenessCardState extends State<ProductEffectivenessCard> {
  String search = '';

  @override
  Widget build(BuildContext context) {
    final list =
        widget.products.where((e) {
          final name = (e['item_name'] ?? '').toString().toLowerCase();

          final code = (e['item_code'] ?? '').toString().toLowerCase();

          return name.contains(search.toLowerCase()) ||
              code.contains(search.toLowerCase());
        }).toList()..sort((a, b) {
          final reqA = (a['requests'] ?? 0) as num;

          final reqB = (b['requests'] ?? 0) as num;

          final rateA = (a['sales_rate'] ?? 0) as num;

          final rateB = (b['sales_rate'] ?? 0) as num;

          final scoreA = reqA * (100 - rateA);

          final scoreB = reqB * (100 - rateB);

          return scoreB.compareTo(scoreA);
        });

    return GlassContainer(
      child: Column(
        children: [
          Row(
            children: const [
              Icon(Icons.medication, color: Color(0xff8B5CF6)),
              SizedBox(width: 8),
              Text(
                'Products Requested by Branches',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),

          const SizedBox(height: 12),

          TextField(
            onChanged: (v) {
              setState(() => search = v);
            },
            decoration: InputDecoration(
              hintText: 'Search product...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: const Color(0xffF1F5F9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),

          const SizedBox(height: 12),

          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (context, index) {
                final p = list[index];
                final salesRate = (p['sales_rate'] ?? 0) as num;

                final notSoldRate = (p['not_sold_rate'] ?? 0) as num;
                return InkWell(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (_) => ProductEffectivenessDialog(
                        itemCode: p['item_code'] ?? '',
                        itemName: p['item_name'] ?? '',
                        branches: List<Map<String, dynamic>>.from(
                          p['branches'] ?? [],
                        ),
                      ),
                    );
                  },

                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),

                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xffE2E8F0)),
                    ),

                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: const Color(0xff8B5CF6).withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
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
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                p['item_name'] ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),

                              const SizedBox(height: 2),

                              Text(
                                p['item_code'] ?? '',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xff94A3B8),
                                ),
                              ),

                              const SizedBox(height: 6),

                              Row(
                                children: [
                                  _miniBadge(
                                    '${p['requests']} Req',
                                    const Color(0xff3B82F6),
                                  ),

                                  const SizedBox(width: 6),

                                  _miniBadge(
                                    'Qty ${p['qty']}',
                                    const Color(0xff64748B),
                                  ),

                                  const SizedBox(width: 6),

                                  _miniBadge(
                                    '${salesRate.toStringAsFixed(0)}% Sold',
                                    salesRate >= 70
                                        ? Colors.green
                                        : salesRate >= 40
                                        ? Colors.orange
                                        : Colors.red,
                                  ),
                                ],
                              ),
                            ],
                          ),
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
}

Widget _miniBadge(String text, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
    ),
  );
}
