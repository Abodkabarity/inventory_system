import 'package:flutter/material.dart';

import '../../../domain/entities/online_overview.dart';
import 'online_overview_grid.dart';
import 'stock_catalog_visuals.dart';

const onlineGuideText = TextStyle(color: catalogInk, fontSize: 18, height: 1.5);

class OnlineGuideIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const OnlineGuideIcon({
    super.key,
    required this.icon,
    this.color = catalogTeal,
    this.size = 60,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [color.withValues(alpha: .07), color.withValues(alpha: .18)],
      ),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Icon(icon, color: color, size: size * .5),
  );
}

class OnlineGuideSummary extends StatelessWidget {
  final OnlineRank rank;
  final String title, body;
  final bool embedded;
  const OnlineGuideSummary({
    super.key,
    required this.rank,
    required this.title,
    required this.body,
    this.embedded = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = onlineRankColor(rank);
    return LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxWidth < 560;
        final badge = Container(
          width: compact ? 56 : 70,
          height: compact ? 56 : 70,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color, Color.lerp(color, catalogInk, .3)!],
            ),
            borderRadius: BorderRadius.circular(15),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: .14),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: rank == OnlineRank.review
              ? const Icon(
                  Icons.manage_search_rounded,
                  color: Colors.white,
                  size: 30,
                )
              : Text(
                  rank.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                  ),
                ),
        );
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: embedded
                ? BorderRadius.zero
                : BorderRadius.circular(20),
            border: embedded
                ? null
                : Border.all(color: color.withValues(alpha: .3)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                Color.alphaBlend(color.withValues(alpha: .045), Colors.white),
              ],
            ),
          ),
          child: CustomPaint(
            painter: _GuideWaves(color),
            child: Padding(
              padding: EdgeInsets.all(compact ? 18 : 26),
              child: compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            badge,
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                title,
                                style: onlineGuideText.copyWith(
                                  fontSize: 25,
                                  fontWeight: FontWeight.w800,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(body, style: onlineGuideText),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        badge,
                        const SizedBox(width: 28),
                        Container(
                          width: 1,
                          height: 76,
                          color: color.withValues(alpha: .25),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: onlineGuideText.copyWith(
                                  fontSize: 29,
                                  fontWeight: FontWeight.w800,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(body, style: onlineGuideText),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}

class OnlineGuideRule extends StatelessWidget {
  final IconData icon;
  final String title, body;
  final bool divider;
  const OnlineGuideRule({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.divider = true,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final compact = box.maxWidth < 560;
      final heading = Text(
        title,
        style: onlineGuideText.copyWith(
          color: const Color(0xFF006E70),
          fontSize: 23,
          fontWeight: FontWeight.w800,
          height: 1.25,
        ),
      );
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          border: divider
              ? const Border(bottom: BorderSide(color: Color(0xFFDFE6EF)))
              : null,
        ),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      OnlineGuideIcon(icon: icon, size: 48),
                      const SizedBox(width: 14),
                      Expanded(child: heading),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(body, style: onlineGuideText),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(width: 18),
                  OnlineGuideIcon(icon: icon),
                  const SizedBox(width: 30),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        heading,
                        const SizedBox(height: 4),
                        Text(body, style: onlineGuideText),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
      );
    },
  );
}

class OnlineGuideNote extends StatelessWidget {
  final String title, body;
  final IconData icon;
  const OnlineGuideNote({
    super.key,
    required this.title,
    required this.body,
    this.icon = Icons.balance_rounded,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final compact = box.maxWidth < 560;
      final text = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: onlineGuideText.copyWith(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 8),
          Text(body, style: onlineGuideText),
        ],
      );
      return Container(
        padding: EdgeInsets.all(compact ? 18 : 24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF3F8FD), Color(0xFFE3EFF9)],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE1EDF7)),
        ),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: const Color(0xFF087D7C), size: 34),
                  const SizedBox(height: 12),
                  text,
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 12,
                    ),
                    child: Icon(icon, color: const Color(0xFF087D7C), size: 40),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.only(left: 22),
                      decoration: const BoxDecoration(
                        border: Border(
                          left: BorderSide(color: Color(0xFFC5D9EB)),
                        ),
                      ),
                      child: text,
                    ),
                  ),
                ],
              ),
      );
    },
  );
}

class OnlineGuideExample extends StatelessWidget {
  final OnlineOverviewRow? product;
  final Color color;
  final bool embedded;
  const OnlineGuideExample({
    super.key,
    required this.product,
    this.color = catalogTeal,
    this.embedded = false,
  });

  @override
  Widget build(BuildContext context) {
    final row = product;
    if (row == null) {
      return Padding(
        padding: embedded
            ? const EdgeInsets.all(20)
            : const EdgeInsets.symmetric(vertical: 16),
        child: const Text(
          'No current example for this rank.',
          style: onlineGuideText,
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        final details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Text(
                'Current example · ${row.item.code}',
                style: onlineGuideText.copyWith(
                  color: Color.lerp(color, catalogInk, .3),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              row.item.name,
              style: onlineGuideText.copyWith(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(onlinePlainReason(row), style: onlineGuideText),
          ],
        );
        return Container(
          padding: EdgeInsets.all(box.maxWidth < 560 ? 18 : 22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: embedded
                ? BorderRadius.zero
                : BorderRadius.circular(18),
            border: embedded
                ? null
                : Border.all(color: const Color(0xFFBFCDE0), width: 1.2),
          ),
          child: box.maxWidth < 560
              ? details
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OnlineGuideIcon(
                      icon: Icons.inventory_2_outlined,
                      color: color,
                      size: 72,
                    ),
                    const SizedBox(width: 24),
                    Expanded(child: details),
                  ],
                ),
        );
      },
    );
  }
}

class OnlineGuideFrame extends StatelessWidget {
  final OnlineRank rank;
  final Widget child;
  const OnlineGuideFrame({super.key, required this.rank, required this.child});

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey('online-guide-card-${rank.name}'),
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: onlineRankColor(rank).withValues(alpha: .26)),
      boxShadow: [
        BoxShadow(
          color: onlineRankColor(rank).withValues(alpha: .035),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: child,
  );
}

class OnlineGuideRankCard extends StatelessWidget {
  final OnlineRank rank;
  final String title, body;
  final OnlineOverviewRow? product;
  const OnlineGuideRankCard({
    super.key,
    required this.rank,
    required this.title,
    required this.body,
    required this.product,
  });

  @override
  Widget build(BuildContext context) => OnlineGuideFrame(
    rank: rank,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OnlineGuideSummary(
          rank: rank,
          title: title,
          body: body,
          embedded: true,
        ),
        Divider(
          height: 1,
          thickness: 1,
          color: onlineRankColor(rank).withValues(alpha: .16),
        ),
        OnlineGuideExample(
          product: product,
          color: onlineRankColor(rank),
          embedded: true,
        ),
      ],
    ),
  );
}

class _GuideWaves extends CustomPainter {
  final Color color;
  const _GuideWaves(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final edge = size.width;
    for (final (width, opacity) in [(190.0, .02), (100.0, .03)]) {
      final path = Path()
        ..moveTo(edge - width, 0)
        ..quadraticBezierTo(
          edge - 40,
          size.height * .15,
          edge,
          size.height * .75,
        )
        ..lineTo(edge, 0)
        ..close();
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: opacity));
    }
  }

  @override
  bool shouldRepaint(_GuideWaves oldDelegate) => color != oldDelegate.color;
}
