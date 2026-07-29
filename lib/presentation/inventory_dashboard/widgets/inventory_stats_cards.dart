import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class InventoryStatsCards extends StatelessWidget {
  final int totalOrdersToday;
  final int submitted;
  final int additionalToday;
  final int additionalMonth;
  final int pendingInventory;
  final int sentToStore;

  const InventoryStatsCards({
    super.key,
    required this.totalOrdersToday,
    required this.submitted,
    required this.additionalToday,
    required this.additionalMonth,
    required this.pendingInventory,
    required this.sentToStore,
  });

  double get _submittedProgress {
    if (totalOrdersToday <= 0) {
      return 0;
    }

    return (submitted / totalOrdersToday).clamp(0.0, 1.0);
  }

  int get _submittedPercentage {
    return (_submittedProgress * 100).round();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth;
          final spacing = 12.w;

          final columns = _getColumnCount(availableWidth);

          final cardWidth =
              (availableWidth - (spacing * (columns - 1))) / columns;

          return Wrap(
            spacing: spacing,
            runSpacing: 14.h,
            children: [
              SizedBox(
                width: cardWidth,
                child: _AnimatedStatCard(
                  title: 'Total Orders Today',
                  value: totalOrdersToday.toString(),
                  icon: Icons.storefront_rounded,
                  color: const Color(0xFF8B5CF6),
                  footerText: 'LIVE ORDER OVERVIEW',
                ),
              ),
              SizedBox(
                width: cardWidth,
                child: _AnimatedStatCard(
                  title: 'Submitted Orders',
                  value: submitted.toString(),
                  valueSuffix: '/ $totalOrdersToday',
                  icon: Icons.task_alt_rounded,
                  color: const Color(0xFF10B981),
                  footerText: '$_submittedPercentage% COMPLETED',
                  progress: _submittedProgress,
                ),
              ),
              SizedBox(
                width: cardWidth,
                child: _AnimatedStatCard(
                  title: 'Additional Today',
                  value: additionalToday.toString(),
                  icon: Icons.add_box_rounded,
                  color: const Color(0xFFFF6B35),
                  footerText: 'LIVE ORDER OVERVIEW',
                ),
              ),
              SizedBox(
                width: cardWidth,
                child: _AnimatedStatCard(
                  title: 'Rejected Additional',
                  value: additionalMonth.toString(),
                  icon: Icons.cancel_outlined,
                  color: const Color(0xFFF43F5E),
                  footerText: 'REJECTED REQUESTS',
                ),
              ),
              SizedBox(
                width: cardWidth,
                child: _AnimatedWorkflowCard(
                  title: 'Pending / Sent To Store',
                  pendingValue: pendingInventory.toString(),
                  sentValue: sentToStore.toString(),
                  color: const Color(0xFFF59E0B),
                  icon: Icons.hourglass_bottom_rounded,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  int _getColumnCount(double width) {
    if (width >= 1300) {
      return 5;
    }

    if (width >= 900) {
      return 3;
    }

    if (width >= 580) {
      return 2;
    }

    return 1;
  }
}

class _AnimatedStatCard extends StatelessWidget {
  final String title;
  final String value;
  final String? valueSuffix;
  final String footerText;
  final IconData icon;
  final Color color;
  final double? progress;

  const _AnimatedStatCard({
    required this.title,
    required this.value,
    required this.footerText,
    required this.icon,
    required this.color,
    this.valueSuffix,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return _HoverCard(
      color: color,
      childBuilder: (context, isHovered) {
        return Padding(
          padding: EdgeInsets.fromLTRB(15.w, 14.h, 15.w, 12.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.sp,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                  ),
                  SizedBox(width: 10.w),
                  _AnimatedIconBox(
                    icon: icon,
                    color: color,
                    isHovered: isHovered,
                  ),
                ],
              ),
              SizedBox(height: 5.h),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 28.sp,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  if (valueSuffix != null) ...[
                    SizedBox(width: 5.w),
                    Padding(
                      padding: EdgeInsets.only(bottom: 2.h),
                      child: Text(
                        valueSuffix!,
                        style: TextStyle(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const Spacer(),
              if (progress != null) ...[
                _AnimatedProgressBar(progress: progress!, color: color),
                SizedBox(height: 7.h),
              ] else ...[
                Container(
                  width: isHovered ? 48.w : 28.w,
                  height: 3.h,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                SizedBox(height: 7.h),
              ],
              Text(
                footerText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 8.5.sp,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.45,
                  color: const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AnimatedWorkflowCard extends StatelessWidget {
  final String title;
  final String pendingValue;
  final String sentValue;
  final IconData icon;
  final Color color;

  const _AnimatedWorkflowCard({
    required this.title,
    required this.pendingValue,
    required this.sentValue,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return _HoverCard(
      color: color,
      childBuilder: (context, isHovered) {
        return Padding(
          padding: EdgeInsets.fromLTRB(15.w, 14.h, 15.w, 12.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.sp,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                  ),
                  SizedBox(width: 10.w),
                  _AnimatedIconBox(
                    icon: icon,
                    color: color,
                    isHovered: isHovered,
                  ),
                ],
              ),
              SizedBox(height: 6.h),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: _WorkflowValue(
                      value: pendingValue,
                      label: 'Pending',
                      valueColor: const Color(0xFFEF4444),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 33.h,
                    margin: EdgeInsets.symmetric(horizontal: 8.w),
                    color: const Color(0xFFE2E8F0),
                  ),
                  Expanded(
                    child: _WorkflowValue(
                      value: sentValue,
                      label: 'Sent',
                      valueColor: const Color(0xFF475569),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: isHovered ? 48.w : 28.w,
                    height: 3.h,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
              SizedBox(height: 7.h),
              Text(
                'ADDITIONAL WORKFLOW',
                style: TextStyle(
                  fontSize: 8.5.sp,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.45,
                  color: const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WorkflowValue extends StatelessWidget {
  final String value;
  final String label;
  final Color valueColor;

  const _WorkflowValue({
    required this.value,
    required this.label,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 23.sp,
            height: 1,
            fontWeight: FontWeight.w900,
            color: valueColor,
          ),
        ),
        SizedBox(height: 4.h),
        Text(
          label,
          style: TextStyle(
            fontSize: 9.sp,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }
}

class _HoverCard extends StatefulWidget {
  final Color color;
  final Widget Function(BuildContext context, bool isHovered) childBuilder;

  const _HoverCard({required this.color, required this.childBuilder});

  @override
  State<_HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<_HoverCard> {
  bool _isHovered = false;

  void _setHover(bool value) {
    if (_isHovered == value) {
      return;
    }

    setState(() {
      _isHovered = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _setHover(true),
      onExit: (_) => _setHover(false),
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        offset: _isHovered ? const Offset(0, -0.045) : Offset.zero,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          scale: _isHovered ? 1.018 : 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            height: 138.h,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _isHovered
                    ? [Colors.white, widget.color.withValues(alpha: 0.065)]
                    : [Colors.white, const Color(0xFFFBFCFE)],
              ),
              borderRadius: BorderRadius.circular(17.r),
              border: Border.all(
                color: _isHovered
                    ? widget.color.withValues(alpha: 0.42)
                    : const Color(0xFFE2E8F0),
                width: _isHovered ? 1.3 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: _isHovered
                      ? widget.color.withValues(alpha: 0.20)
                      : Colors.black.withValues(alpha: 0.055),
                  blurRadius: _isHovered ? 28 : 16,
                  spreadRadius: _isHovered ? 1 : 0,
                  offset: Offset(0, _isHovered ? 12 : 7),
                ),
              ],
            ),
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  right: _isHovered ? -20.w : -30.w,
                  bottom: _isHovered ? -34.h : -42.h,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 320),
                    width: _isHovered ? 112.w : 100.w,
                    height: _isHovered ? 112.w : 100.w,
                    decoration: BoxDecoration(
                      color: widget.color.withValues(
                        alpha: _isHovered ? 0.10 : 0.065,
                      ),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                  right: _isHovered ? 64.w : 55.w,
                  bottom: _isHovered ? 14.h : 7.h,
                  child: Container(
                    width: 9.w,
                    height: 9.w,
                    decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: _isHovered ? 5.w : 4.w,
                    decoration: BoxDecoration(
                      color: widget.color,
                      borderRadius: BorderRadius.only(
                        topRight: Radius.circular(8.r),
                        bottomRight: Radius.circular(8.r),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: widget.childBuilder(context, _isHovered),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedIconBox extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool isHovered;

  const _AnimatedIconBox({
    required this.icon,
    required this.color,
    required this.isHovered,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedRotation(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutBack,
      turns: isHovered ? 0.035 : 0,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutBack,
        scale: isHovered ? 1.10 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 33.w,
          height: 33.w,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: isHovered ? 0.17 : 0.10),
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(
              color: color.withValues(alpha: isHovered ? 0.36 : 0.18),
            ),
          ),
          child: Icon(icon, color: color, size: 18.sp),
        ),
      ),
    );
  }
}

class _AnimatedProgressBar extends StatelessWidget {
  final double progress;
  final Color color;

  const _AnimatedProgressBar({required this.progress, required this.color});

  @override
  Widget build(BuildContext context) {
    final safeProgress = progress.clamp(0.0, 1.0);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: safeProgress),
      duration: const Duration(milliseconds: 850),
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, child) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: animatedValue,
            minHeight: 5.h,
            backgroundColor: const Color(0xFFE2E8F0),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        );
      },
    );
  }
}
