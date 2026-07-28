import 'package:flutter/material.dart';

import '../../../core/utils/store_branch_identity_registry.dart';

export '../../../core/utils/store_branch_identity_registry.dart';

class StoreBranchLabel extends StatelessWidget {
  const StoreBranchLabel({
    super.key,
    required this.branchName,
    this.style,
    this.compactBadge = true,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.textAlign = TextAlign.start,
    this.suffix,
  });

  final String branchName;
  final TextStyle? style;
  final bool compactBadge;
  final int maxLines;
  final TextOverflow overflow;
  final MainAxisAlignment mainAxisAlignment;
  final TextAlign textAlign;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, String>>(
      valueListenable: StoreBranchIdentityRegistry.groups,
      builder: (context, groups, _) {
        final is71 = StoreBranchIdentityRegistry.isSeventyOne(
          branchName,
          groups,
        );
        return Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: mainAxisAlignment,
          children: [
            Flexible(
              child: Text(
                suffix == null ? branchName : '$branchName $suffix',
                style: style,
                maxLines: maxLines,
                overflow: overflow,
                textAlign: textAlign,
              ),
            ),
            if (is71) ...[
              const SizedBox(width: 7),
              StoreBranchBadge(compact: compactBadge),
            ],
          ],
        );
      },
    );
  }
}

class StoreBranchBadge extends StatelessWidget {
  const StoreBranchBadge({super.key, this.compact = true});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    const badgeColor = Color(0xffC2410C);
    return Tooltip(
      message: '71 branch',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 8,
          vertical: compact ? 2 : 3,
        ),
        decoration: BoxDecoration(
          color: const Color(0xffFFF3E8),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xffFDBA74)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.local_shipping_rounded,
              size: 12,
              color: badgeColor,
            ),
            const SizedBox(width: 3),
            Text(
              compact ? '71' : '71 Branch',
              style: const TextStyle(
                color: badgeColor,
                fontSize: 10,
                height: 1,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
