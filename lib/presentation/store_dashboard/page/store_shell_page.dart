import 'package:daily_order/presentation/store_dashboard/page/store_dashboard_page.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import 'product_movement_page.dart';

class StoreShellPage extends StatefulWidget {
  final String runDate;

  const StoreShellPage({super.key, required this.runDate});

  @override
  State<StoreShellPage> createState() => _StoreShellPageState();
}

class _StoreShellPageState extends State<StoreShellPage> {
  int selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      StoreDashboardPage(runDate: widget.runDate),

      const ProductMovementPage(),
    ];

    return Scaffold(
      backgroundColor: const Color(0xffF4F7FB),

      body: Row(
        children: [
          // =====================================
          // SIDEBAR
          // =====================================
          Container(
            width: 270,

            decoration: BoxDecoration(
              color: Colors.white,

              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .05),

                  blurRadius: 20,

                  offset: const Offset(4, 0),
                ),
              ],
            ),

            child: Column(
              children: [
                // =====================================
                // HEADER
                // =====================================
                Container(
                  width: double.infinity,

                  padding: const EdgeInsets.fromLTRB(24, 40, 24, 30),

                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.blue.shade50, Colors.white],

                      begin: Alignment.topLeft,

                      end: Alignment.bottomRight,
                    ),

                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),

                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      // =====================================
                      // LOGO
                      // =====================================
                      Center(
                        child: Container(
                          width: 120,
                          height: 70,

                          decoration: const BoxDecoration(
                            image: DecorationImage(
                              image: AssetImage("assets/images/logo1.png"),

                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // =====================================
                      // TITLE
                      // =====================================
                      const Text(
                        "Store Dashboard",

                        style: TextStyle(
                          fontSize: 28,

                          fontWeight: FontWeight.w900,

                          color: AppColors.secondaryColor,
                        ),
                      ),

                      const SizedBox(height: 6),

                      Center(
                        child: Text(
                          "Store Management",

                          style: TextStyle(
                            fontSize: 14,

                            color: Colors.grey.shade600,

                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // =====================================
                // MENU
                // =====================================
                _buildMenuItem(
                  index: 0,

                  icon: Icons.dashboard_rounded,

                  title: "Dashboard",
                ),

                const SizedBox(height: 8),

                _buildMenuItem(
                  index: 1,

                  icon: Icons.move_down,

                  title: "Product Movement",
                ),

                const Spacer(),

                // =====================================
                // FOOTER
                // =====================================
                Padding(
                  padding: const EdgeInsets.all(20),

                  child: Container(
                    padding: const EdgeInsets.all(16),

                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,

                      borderRadius: BorderRadius.circular(18),
                    ),

                    child: Row(
                      children: [
                        Container(
                          width: 45,
                          height: 45,

                          decoration: BoxDecoration(
                            color: AppColors.primaryColor,

                            borderRadius: BorderRadius.circular(14),
                          ),

                          child: const Icon(Icons.store, color: Colors.white),
                        ),

                        const SizedBox(width: 12),

                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,

                            children: [
                              const Text(
                                "Store System",

                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),

                              Text(
                                "ERP Dashboard",

                                style: TextStyle(
                                  fontSize: 12,

                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // =====================================
          // PAGE
          // =====================================
          Expanded(child: pages[selectedIndex]),
        ],
      ),
    );
  }

  // =====================================
  // MENU ITEM
  // =====================================

  Widget _buildMenuItem({
    required int index,

    required IconData icon,

    required String title,
  }) {
    final selected = selectedIndex == index;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),

      child: InkWell(
        borderRadius: BorderRadius.circular(18),

        onTap: () {
          setState(() {
            selectedIndex = index;
          });
        },

        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),

          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),

          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),

            gradient: selected
                ? LinearGradient(
                    colors: [
                      AppColors.primaryColor,

                      AppColors.primaryColor.withValues(alpha: .8),
                    ],
                  )
                : null,

            color: selected ? null : Colors.transparent,

            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.primaryColor.withValues(alpha: .25),

                      blurRadius: 18,

                      offset: const Offset(0, 6),
                    ),
                  ]
                : [],
          ),

          child: Row(
            children: [
              Icon(
                icon,

                color: selected ? Colors.white : Colors.grey.shade700,

                size: 24,
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Text(
                  title,

                  style: TextStyle(
                    fontSize: 16,

                    fontWeight: FontWeight.w700,

                    color: selected ? Colors.white : Colors.grey.shade800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
