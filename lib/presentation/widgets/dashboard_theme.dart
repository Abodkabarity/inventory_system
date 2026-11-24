import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Colors vary by page; geometry and motion stay shared.
class DashboardPalette {
  const DashboardPalette({
    required this.header,
    required this.accent,
    required this.wave,
    required this.edge,
    required this.glow,
    required this.surface,
    required this.border,
  });
  final List<Color> header;
  final Color accent, wave, edge, glow, surface, border;
  static const teal = DashboardPalette(
    header: [Color(0xFF003D4B), Color(0xFF005466), Color(0xFF003744)],
    accent: Color(0xFF007F90),
    wave: Color(0xFF21B9C3),
    edge: Color(0xFF6AF6EC),
    glow: Color(0xFF20D6D4),
    surface: Color(0xFFF4F9FF),
    border: Color(0xFFC6DAED),
  );
  static const indigo = DashboardPalette(
    header: [Color(0xFF25204F), Color(0xFF42347E), Color(0xFF201D49)],
    accent: Color(0xFF6651C8),
    wave: Color(0xFF9780F2),
    edge: Color(0xFFD0BFFF),
    glow: Color(0xFFB89AFF),
    surface: Color(0xFFF6F5FD),
    border: Color(0xFFDCD7F0),
  );
}

class DashboardMetricCard extends StatefulWidget {
  const DashboardMetricCard({
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
    this.keyPrefix = 'dashboard-metric',
    this.displayValue,
  });

  final String id, title, keyPrefix;
  final String? displayValue;
  final int count;
  final IconData icon;
  final Color color;
  final List<Color> background;
  final bool small, selected, cube;
  final VoidCallback? onTap;

  @override
  State<DashboardMetricCard> createState() => _DashboardMetricCardState();
}

class _DashboardMetricCardState extends State<DashboardMetricCard> {
  bool _hovered = false, _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final color = widget.color;
    final small = widget.small;
    return MouseRegion(
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
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
            key: ValueKey('${widget.keyPrefix}-${widget.id}-scale'),
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
                                    '${widget.keyPrefix}-${widget.id}-icon',
                                  ),
                                  angle: -.12 * motion,
                                  child: Transform.scale(
                                    scale: 1 + .10 * motion,
                                    child: widget.cube
                                        ? DashboardCubeIcon(
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
                                        '${widget.keyPrefix}-${widget.id}-number',
                                      ),
                                      alignment: Alignment.centerLeft,
                                      scale: 1 + .035 * motion,
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          widget.displayValue ??
                                              NumberFormat.decimalPattern()
                                                  .format(widget.count),
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
                            DashboardMetricBars(color: color, activity: motion),
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

class DashboardCubeIcon extends StatelessWidget {
  const DashboardCubeIcon({super.key, required this.color, required this.size});
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
class DashboardWaveHeader extends StatelessWidget {
  const DashboardWaveHeader({
    super.key,
    required this.child,
    this.modal = false,
    this.palette = DashboardPalette.teal,
  });
  final Widget child;
  final bool modal;
  final DashboardPalette palette;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: palette.header,
      ),
    ),
    child: ClipRect(
      child: CustomPaint(
        painter: _HeaderWaves(modal: modal, palette: palette),
        child: child,
      ),
    ),
  );
}

class _HeaderWaves extends CustomPainter {
  _HeaderWaves({this.modal = false, required this.palette});
  final DashboardPalette palette;
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
          ..shader = LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              palette.wave.withValues(alpha: .38),
              palette.wave.withValues(alpha: .87),
              palette.wave.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromLTWH(w * .60, 0, w * .43, h)),
      );
      final edge = Path()
        ..moveTo(w * .61, h)
        ..cubicTo(w * .78, h * .94, w * .84, h * .46, w * .88, 0);
      canvas.drawPath(
        edge,
        Paint()
          ..color = palette.edge.withValues(alpha: .82)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      return;
    }
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          palette.glow.withValues(alpha: .33),
          palette.glow.withValues(alpha: 0),
        ],
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
        ..shader = LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            palette.wave.withValues(alpha: .06),
            palette.wave.withValues(alpha: .53),
            palette.wave.withValues(alpha: 0),
          ],
        ).createShader(Offset.zero & size),
    );
    final edge = Path()
      ..moveTo(w * .64, h)
      ..cubicTo(w * .75, h * 1.06, w * .79, h * .17, w * .83, -h * .12);
    canvas.drawPath(
      edge,
      Paint()
        ..color = palette.edge.withValues(alpha: .67)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );
    final lower = Path()
      ..moveTo(w * .68, h)
      ..cubicTo(w * .77, h * .93, w * .80, h * .48, w * .86, -h * .12)
      ..lineTo(w * .92, -h * .12)
      ..cubicTo(w * .84, h * .73, w * .82, h * 1.3, w * .68, h)
      ..close();
    canvas.drawPath(
      lower,
      Paint()..color = palette.glow.withValues(alpha: .06),
    );
  }

  @override
  bool shouldRepaint(_HeaderWaves oldDelegate) =>
      oldDelegate.modal != modal || oldDelegate.palette != palette;
}

class DashboardMetricBars extends StatelessWidget {
  const DashboardMetricBars({
    super.key,
    required this.color,
    this.activity = 0,
  });
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
