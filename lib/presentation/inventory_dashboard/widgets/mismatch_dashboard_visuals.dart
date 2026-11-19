import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class MismatchMetricCard extends StatefulWidget {
  const MismatchMetricCard({
    super.key,
    required this.id,
    required this.title,
    required this.count,
    required this.icon,
    required this.color,
    required this.background,
    required this.small,
    required this.selected,
    required this.onTap,
    this.cube = false,
  });

  final String id, title;
  final int count;
  final IconData icon;
  final Color color;
  final List<Color> background;
  final bool small, selected, cube;
  final VoidCallback onTap;

  @override
  State<MismatchMetricCard> createState() => _MismatchMetricCardState();
}

class _MismatchMetricCardState extends State<MismatchMetricCard> {
  bool _hovered = false, _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final color = widget.color;
    final small = widget.small;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: _hovered && !reduceMotion ? 1 : 0),
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        builder: (context, motion, _) => Transform.translate(
          offset: Offset(0, -4 * motion),
          transformHitTests: false,
          child: Transform.scale(
            key: ValueKey('mismatch-metric-${widget.id}-scale'),
            scale: 1 + .018 * motion,
            transformHitTests: false,
            child: AnimatedScale(
              scale: _pressed && !reduceMotion ? .985 : 1,
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 110),
              curve: Curves.easeOut,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: widget.background,
                  ),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: color.withValues(
                      alpha: widget.selected ? .55 : .19 + .15 * motion,
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: .045 + .09 * motion),
                      blurRadius: 12 + 14 * motion,
                      offset: Offset(0, 4 + 6 * motion),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(15),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(15),
                    onTap: widget.onTap,
                    onHighlightChanged: (pressed) =>
                        setState(() => _pressed = pressed),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: small ? 12 : 17,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: small ? 44 : 60,
                            height: small ? 48 : 60,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  color.withValues(alpha: .07),
                                  color.withValues(alpha: .18),
                                ],
                              ),
                            ),
                            child: Center(
                              child: Transform.translate(
                                offset: Offset(0, -2 * motion),
                                child: Transform.rotate(
                                  key: ValueKey(
                                    'mismatch-metric-${widget.id}-icon',
                                  ),
                                  angle: -.12 * motion,
                                  child: Transform.scale(
                                    scale: 1 + .10 * motion,
                                    child: widget.cube
                                        ? MismatchCubeIcon(
                                            color: color,
                                            size: small ? 27 : 33,
                                          )
                                        : Icon(
                                            widget.icon,
                                            color: color,
                                            size: small ? 27 : 33,
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: small ? 10 : 17),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Transform.translate(
                                  offset: Offset(0, -1.5 * motion),
                                  child: Transform.rotate(
                                    angle: -.012 * motion,
                                    child: Transform.scale(
                                      key: ValueKey(
                                        'mismatch-metric-${widget.id}-number',
                                      ),
                                      alignment: Alignment.centerLeft,
                                      scale: 1 + .035 * motion,
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          NumberFormat.decimalPattern().format(
                                            widget.count,
                                          ),
                                          maxLines: 1,
                                          style: TextStyle(
                                            color: color,
                                            fontSize: small ? 28 : 36,
                                            height: 1.08,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  widget.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: small ? 12 : 14,
                                    color: const Color(0xFF07283E),
                                    height: 1.15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!small) ...[
                            const SizedBox(width: 8),
                            MismatchMetricBars(color: color, activity: motion),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MismatchCubeIcon extends StatelessWidget {
  const MismatchCubeIcon({super.key, required this.color, required this.size});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _CubePainter(color));
}

class _CubePainter extends CustomPainter {
  _CubePainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 48, size.height / 48);
    final outline = Path()
      ..moveTo(24, 3)
      ..lineTo(44, 13)
      ..lineTo(44, 35)
      ..lineTo(24, 46)
      ..lineTo(4, 35)
      ..lineTo(4, 13)
      ..close();
    final seams = Path()
      ..moveTo(4, 13)
      ..lineTo(24, 24)
      ..lineTo(44, 13)
      ..moveTo(24, 24)
      ..lineTo(24, 46)
      ..moveTo(14, 8)
      ..lineTo(34, 18)
      ..lineTo(34, 26);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(outline, paint);
    canvas.drawPath(seams, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CubePainter oldDelegate) => color != oldDelegate.color;
}

/// Code-drawn decoration: no raster assets or product images are requested.
class MismatchHeaderBackdrop extends StatelessWidget {
  const MismatchHeaderBackdrop({
    super.key,
    required this.child,
    this.modal = false,
  });
  final Widget child;
  final bool modal;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF003D4B), Color(0xFF005466), Color(0xFF003744)],
      ),
    ),
    child: ClipRect(
      child: CustomPaint(
        painter: _HeaderWaves(modal: modal),
        child: child,
      ),
    ),
  );
}

class _HeaderWaves extends CustomPainter {
  _HeaderWaves({this.modal = false});
  final bool modal;
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (modal) {
      final ribbon = Path()
        ..moveTo(w * .61, h)
        ..cubicTo(w * .78, h * .94, w * .84, h * .46, w * .88, 0)
        ..lineTo(w * 1.02, 0)
        ..cubicTo(w * .98, h * .76, w * .82, h * 1.18, w * .61, h)
        ..close();
      canvas.drawPath(
        ribbon,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0x6000A3B4), Color(0xDD00B6C7), Color(0x0000718A)],
          ).createShader(Rect.fromLTWH(w * .60, 0, w * .43, h)),
      );
      final edge = Path()
        ..moveTo(w * .61, h)
        ..cubicTo(w * .78, h * .94, w * .84, h * .46, w * .88, 0);
      canvas.drawPath(
        edge,
        Paint()
          ..color = const Color(0xD045E5E3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      return;
    }
    final glow = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0x5520D6D4), Color(0x0000B8C8)],
      ).createShader(Rect.fromLTWH(w * .50, -h * .55, w * .55, h * 2.6));
    canvas.drawRect(Offset.zero & size, glow);
    final upper = Path()
      ..moveTo(w * .64, h)
      ..cubicTo(w * .72, h * .90, w * .73, h * .16, w * .80, -h * .15)
      ..lineTo(w * .89, -h * .15)
      ..cubicTo(w * .81, h * .80, w * .76, h * 1.16, w * .64, h)
      ..close();
    canvas.drawPath(
      upper,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0x1031E2DD), Color(0x8821B9C3), Color(0x0014ABBB)],
        ).createShader(Offset.zero & size),
    );
    final edge = Path()
      ..moveTo(w * .64, h)
      ..cubicTo(w * .75, h * 1.06, w * .79, h * .17, w * .83, -h * .12);
    canvas.drawPath(
      edge,
      Paint()
        ..color = const Color(0xAA6AF6EC)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );
    final lower = Path()
      ..moveTo(w * .68, h)
      ..cubicTo(w * .77, h * .93, w * .80, h * .48, w * .86, -h * .12)
      ..lineTo(w * .92, -h * .12)
      ..cubicTo(w * .84, h * .73, w * .82, h * 1.3, w * .68, h)
      ..close();
    canvas.drawPath(lower, Paint()..color = const Color(0x102DE9DC));
  }

  @override
  bool shouldRepaint(_HeaderWaves oldDelegate) => oldDelegate.modal != modal;
}

class MismatchMetricBars extends StatelessWidget {
  const MismatchMetricBars({super.key, required this.color, this.activity = 0});
  final Color color;
  final double activity;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: 46,
      height: 38,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(
          5,
          (i) => Container(
            width: 5,
            height: math.min(
              38,
              (10 + i * 6) * (1 + .08 * activity) +
                  math.sin(activity * math.pi) * (i.isEven ? 3 : -2),
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withValues(alpha: .30 + i * .12),
                  color.withValues(alpha: .12 + i * .10),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
