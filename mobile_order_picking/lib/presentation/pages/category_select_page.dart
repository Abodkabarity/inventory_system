import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_theme.dart';
import '../../domain/entities.dart';
import '../bloc/mobile_order_bloc.dart';
import '../widgets/brand_header.dart';

class CategorySelectPage extends StatelessWidget {
  const CategorySelectPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () =>
              context.read<MobileOrderBloc>().add(BranchesRequested()),
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          IconButton(
            onPressed: () =>
                context.read<MobileOrderBloc>().add(LogoutRequested()),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: BlocBuilder<MobileOrderBloc, MobileOrderState>(
        builder: (context, state) {
          final medicine = state.countFor(PickCategory.medicine);
          final general = state.countFor(PickCategory.general);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              BrandHeader(
                title: state.selectedBranch,
                subtitle: 'Prepared by ${state.pickerName}',
              ),
              const SizedBox(height: 22),
              _SummaryCard(total: state.items.length),
              const SizedBox(height: 18),
              _CategoryCard(
                title: 'Medicine',
                subtitle: 'Items sorted by classification, supplier, then name',
                count: medicine,
                submitted: state.submittedCategories.contains(
                  PickCategory.medicine,
                ),
                color: AppTheme.deepBlue,
                icon: Icons.medication_liquid,
                onTap: medicine == 0
                    ? null
                    : () => context.read<MobileOrderBloc>().add(
                        const CategorySelected(PickCategory.medicine),
                      ),
              ),
              const SizedBox(height: 14),
              _CategoryCard(
                title: 'General',
                subtitle: 'Items sorted by category, supplier, then name',
                count: general,
                submitted: state.submittedCategories.contains(
                  PickCategory.general,
                ),
                color: AppTheme.orange,
                icon: Icons.inventory_2_outlined,
                onTap: general == 0
                    ? null
                    : () => context.read<MobileOrderBloc>().add(
                        const CategorySelected(PickCategory.general),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final int total;

  const _SummaryCard({required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.blue, AppTheme.deepBlue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          const Icon(Icons.fact_check_outlined, color: Colors.white, size: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              '$total item(s) ready for picking',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final int count;
  final bool submitted;
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;

  const _CategoryCard({
    required this.title,
    required this.subtitle,
    required this.count,
    required this.submitted,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Ink(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.10),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, color: color, size: 34),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppTheme.navy,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.blueGrey.shade700),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: submitted
                    ? AppTheme.mint.withValues(alpha: 0.14)
                    : color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (submitted) ...[
                    const Icon(
                      Icons.check_circle,
                      color: AppTheme.mint,
                      size: 20,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    submitted ? 'Sent' : '$count',
                    style: TextStyle(
                      color: submitted ? AppTheme.mint : color,
                      fontSize: submitted ? 15 : 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
