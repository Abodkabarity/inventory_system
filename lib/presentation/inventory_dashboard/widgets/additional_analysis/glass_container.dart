import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

class GlassContainer extends StatelessWidget {
  final Widget child;

  const GlassContainer({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xff374151)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(.25), blurRadius: 25),
        ],
      ),
      child: child,
    );
  }
}
