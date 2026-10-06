import 'package:flutter/material.dart';

/// Shared catalog warning shown only for a blocked product.
class ItemsTrackerBlockBadge extends StatelessWidget {
  const ItemsTrackerBlockBadge({super.key});

  @override
  Widget build(BuildContext context) {
    const red = Color(0xffb42318);
    return Semantics(
      label: 'Blocked product',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xfffff1f0),
          border: Border.all(color: const Color(0xfffecdca)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.block_rounded, size: 14, color: red),
            SizedBox(width: 5),
            Text(
              'Block',
              style: TextStyle(
                color: red,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Keeps the warning with the name in both the grid and product cards.
class ItemsTrackerProductName extends StatelessWidget {
  final Widget name;
  final bool isBlocked;
  const ItemsTrackerProductName({
    super.key,
    required this.name,
    required this.isBlocked,
  });

  @override
  Widget build(BuildContext context) => isBlocked
      ? Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            name,
            const SizedBox(height: 5),
            const ItemsTrackerBlockBadge(),
          ],
        )
      : name;
}
