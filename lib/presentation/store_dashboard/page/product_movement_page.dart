import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';

class ProductMovementPage extends StatefulWidget {
  const ProductMovementPage({super.key});

  @override
  State<ProductMovementPage> createState() => _ProductMovementPageState();
}

class _ProductMovementPageState extends State<ProductMovementPage> {
  final client = Supabase.instance.client;

  List<String> branches = [];

  String? selectedBranch;

  final searchController = TextEditingController();

  Timer? searchDebounce;

  List<Map<String, dynamic>> suggestions = [];

  List<Map<String, dynamic>> movements = [];

  bool isLoading = false;

  @override
  void initState() {
    super.initState();

    loadBranches();
  }

  @override
  void dispose() {
    searchDebounce?.cancel();

    searchController.dispose();

    super.dispose();
  }

  // =====================================
  // LOAD BRANCHES
  // =====================================

  Future<void> loadBranches() async {
    final res = await client
        .from('branches')
        .select('branch_name')
        .eq('is_active', true)
        .order('branch_name');

    final loadedBranches = List<Map<String, dynamic>>.from(
      res,
    ).map((e) => e['branch_name'].toString()).toList();

    loadedBranches.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    setState(() {
      branches = loadedBranches;
    });
  }

  // =====================================
  // SEARCH PRODUCTS
  // =====================================

  Future<void> searchProducts(String query) async {
    if (selectedBranch == null) {
      return;
    }

    if (query.trim().isEmpty) {
      setState(() {
        suggestions = [];
      });

      return;
    }

    final res = await client
        .from('product_movement_history')
        .select('item_code,item_name')
        .eq('branch', selectedBranch!)
        .or(
          'item_name.ilike.%$query%,'
          'item_code.ilike.%$query%',
        )
        .limit(20);

    final rows = List<Map<String, dynamic>>.from(res);

    final unique = <String, Map<String, dynamic>>{};

    for (final row in rows) {
      unique[row['item_code']] = row;
    }

    setState(() {
      suggestions = unique.values.toList();
    });
  }

  // =====================================
  // LOAD MOVEMENT
  // =====================================

  Future<void> loadMovement(String itemCode) async {
    if (selectedBranch == null) {
      return;
    }

    setState(() {
      isLoading = true;
    });

    final res = await client
        .from('product_movement_history')
        .select()
        .eq('branch', selectedBranch!)
        .eq('item_code', itemCode)
        .order('created_at', ascending: false);

    setState(() {
      movements = List<Map<String, dynamic>>.from(res);

      suggestions = [];

      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xffF4F7FB),

      child: Padding(
        padding: const EdgeInsets.all(24),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            // =====================================
            // TITLE
            // =====================================
            const Text(
              'Product Movement',

              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
            ),

            const SizedBox(height: 24),

            // =====================================
            // BRANCH
            // =====================================
            DropdownButtonFormField<String>(
              value: selectedBranch,

              items: branches
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),

              onChanged: (v) {
                setState(() {
                  selectedBranch = v;

                  movements = [];

                  suggestions = [];

                  searchController.clear();
                });
              },

              decoration: InputDecoration(
                labelText: 'Branch',

                filled: true,

                fillColor: Colors.white,

                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AppColors.primaryColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AppColors.primaryColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AppColors.primaryColor),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // =====================================
            // SEARCH
            // =====================================
            TextField(
              controller: searchController,

              onChanged: (v) {
                searchDebounce?.cancel();

                searchDebounce = Timer(const Duration(milliseconds: 400), () {
                  searchProducts(v);
                });
              },

              decoration: InputDecoration(
                labelText: 'Search Product',

                prefixIcon: const Icon(Icons.search),

                filled: true,

                fillColor: Colors.white,

                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AppColors.primaryColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AppColors.primaryColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AppColors.primaryColor),
                ),
              ),
            ),

            // =====================================
            // SUGGESTIONS
            // =====================================
            if (suggestions.isNotEmpty)
              Container(
                width: double.infinity,

                constraints: const BoxConstraints(maxHeight: 320),

                margin: const EdgeInsets.only(top: 6),

                decoration: BoxDecoration(
                  color: Colors.white,

                  borderRadius: BorderRadius.circular(14),

                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
                ),

                child: ListView.separated(
                  shrinkWrap: true,

                  itemCount: suggestions.length,

                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: Colors.grey.shade200),

                  itemBuilder: (_, i) {
                    final item = suggestions[i];

                    return InkWell(
                      onTap: () {
                        searchController.text = item['item_name'];

                        loadMovement(item['item_code']);
                      },

                      child: Padding(
                        padding: const EdgeInsets.all(14),

                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [
                            Text(
                              item['item_name'] ?? '',

                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),

                            const SizedBox(height: 4),

                            Text(
                              item['item_code'] ?? '',

                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

            const SizedBox(height: 24),

            // =====================================
            // CONTENT
            // =====================================
            Expanded(
              child: Builder(
                builder: (_) {
                  // =====================================
                  // SELECT BRANCH FIRST
                  // =====================================

                  if (selectedBranch == null) {
                    return const Center(
                      child: Text(
                        'Please select branch first',

                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }

                  // =====================================
                  // SEARCH FIRST
                  // =====================================

                  if (searchController.text.trim().isEmpty &&
                      movements.isEmpty) {
                    return const Center(
                      child: Text(
                        'Search product first',

                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }

                  // =====================================
                  // LOADING
                  // =====================================

                  if (isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  // =====================================
                  // NO MOVEMENT
                  // =====================================

                  if (movements.isEmpty) {
                    return const Center(
                      child: Text(
                        'No movement found',

                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }

                  // =====================================
                  // MOVEMENT LIST
                  // =====================================

                  return ListView.builder(
                    itemCount: movements.length,

                    itemBuilder: (_, i) {
                      final item = movements[i];

                      final isDaily = item['movement_type'] == 'daily_order';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),

                        padding: const EdgeInsets.all(18),

                        decoration: BoxDecoration(
                          color: Colors.white,

                          borderRadius: BorderRadius.circular(18),

                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),

                        child: Row(
                          children: [
                            // =====================================
                            // ICON
                            // =====================================
                            Container(
                              width: 48,
                              height: 48,

                              decoration: BoxDecoration(
                                color: isDaily
                                    ? Colors.blue.shade50
                                    : Colors.orange.shade50,

                                shape: BoxShape.circle,
                              ),

                              child: Icon(
                                isDaily ? Icons.shopping_cart : Icons.add_box,

                                color: isDaily ? Colors.blue : Colors.orange,
                              ),
                            ),

                            const SizedBox(width: 16),

                            // =====================================
                            // INFO
                            // =====================================
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,

                                children: [
                                  Text(
                                    isDaily
                                        ? 'Daily Order'
                                        : 'Additional Request',

                                    style: const TextStyle(
                                      fontSize: 17,

                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),

                                  const SizedBox(height: 4),

                                  Text(item['movement_date'].toString()),
                                ],
                              ),
                            ),

                            // =====================================
                            // QTY
                            // =====================================
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 10,
                              ),

                              decoration: BoxDecoration(
                                color: Colors.green.shade50,

                                borderRadius: BorderRadius.circular(14),
                              ),

                              child: Text(
                                'Qty ${item['qty']}',

                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
