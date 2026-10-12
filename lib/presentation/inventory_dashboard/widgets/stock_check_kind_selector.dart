import 'package:flutter/material.dart';

/// Shared check-type navigation for the workspace and accuracy analysis.
class StockCheckKindSelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const StockCheckKindSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF0F7),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFDCE5F0)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 390;
              final regular = _CheckKindButton(
                label: 'Regular Stock Checks',
                icon: Icons.inventory_2_outlined,
                selected: value == 'regular',
                compact: compact,
                colors: const [Color(0xFF397CCE), Color(0xFF2563AB)],
                onTap: () => onChanged('regular'),
              );
              final kpi = _CheckKindButton(
                label: 'KPI Stock Checks',
                icon: Icons.insights_rounded,
                selected: value == 'kpi',
                compact: compact,
                colors: const [Color(0xFF178F85), Color(0xFF11736F)],
                onTap: () => onChanged('kpi'),
              );
              if (constraints.maxWidth < 320) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [regular, const SizedBox(height: 5), kpi],
                );
              }
              return Row(
                children: [
                  Expanded(child: regular),
                  const SizedBox(width: 5),
                  Expanded(child: kpi),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CheckKindButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool compact;
  final List<Color> colors;
  final VoidCallback onTap;

  const _CheckKindButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.compact,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200);
    final foreground = selected ? Colors.white : const Color(0xFF52647B);
    return Semantics(
      selected: selected,
      button: true,
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: selected
                ? colors
                : const [Color(0xFFEAF0F7), Color(0xFFEAF0F7)],
          ),
          boxShadow: [
            BoxShadow(
              color: colors.last.withValues(alpha: selected ? .22 : 0),
              blurRadius: selected ? 12 : 0,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(13),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(13),
            mouseCursor: SystemMouseCursors.click,
            hoverColor: foreground.withValues(alpha: .06),
            focusColor: foreground.withValues(alpha: .12),
            splashColor: foreground.withValues(alpha: .14),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 8 : 14,
                vertical: 12,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedContainer(
                    duration: duration,
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: selected
                          ? Colors.white.withValues(alpha: .16)
                          : Colors.white.withValues(alpha: .6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 18, color: foreground),
                  ),
                  SizedBox(width: compact ? 6 : 9),
                  Flexible(
                    child: AnimatedDefaultTextStyle(
                      duration: duration,
                      style: TextStyle(
                        color: foreground,
                        fontSize: compact ? 12 : 13,
                        fontWeight: FontWeight.w600,
                      ),
                      child: Text(label, maxLines: 1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
