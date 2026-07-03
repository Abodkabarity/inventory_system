import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/app_theme.dart';
import '../bloc/mobile_order_bloc.dart';
import 'branch_select_page.dart';
import 'category_select_page.dart';
import 'login_page.dart';
import 'pick_list_page.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MobileOrderBloc, MobileOrderState>(
      builder: (context, state) {
        if (state.status == MobileOrderStatus.unauthenticated) {
          return const LoginPage();
        }

        if (state.status == MobileOrderStatus.authenticating) {
          return const LoginPage();
        }

        if (state.status == MobileOrderStatus.booting) {
          return const LoadingPage(text: 'Opening store picking...');
        }

        final Widget page;
        if (state.status == MobileOrderStatus.categorySelection) {
          page = const CategorySelectPage();
        } else if (state.status == MobileOrderStatus.picking) {
          page = const PickListPage();
        } else {
          page = const BranchSelectPage();
        }

        return Stack(
          children: [
            page,
            _MessageBanner(state: state),
            if (state.busyMessage.isNotEmpty &&
                state.status != MobileOrderStatus.picking)
              _BusyOverlay(message: state.busyMessage),
          ],
        );
      },
    );
  }
}

class LoadingPage extends StatelessWidget {
  final String text;

  const LoadingPage({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.blue, AppTheme.deepBlue],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Card(
            elevation: 14,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 18),
                  Text(
                    text,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.navy,
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

class _BusyOverlay extends StatelessWidget {
  final String message;

  const _BusyOverlay({required this.message});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          ModalBarrier(
            dismissible: false,
            color: Colors.black.withValues(alpha: 0.18),
          ),
          Center(
            child: Material(
              elevation: 18,
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 18,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                    const SizedBox(width: 14),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 240),
                      child: Text(
                        message,
                        style: const TextStyle(
                          color: AppTheme.navy,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBanner extends StatelessWidget {
  final MobileOrderState state;

  const _MessageBanner({required this.state});

  @override
  Widget build(BuildContext context) {
    final isError = state.error.isNotEmpty;
    final text = isError ? state.error : state.info;
    if (text.isEmpty) return const SizedBox.shrink();

    final color = isError ? Colors.red : AppTheme.mint;
    final icon = isError ? Icons.error_outline : Icons.check_circle_outline;

    return Positioned(
      top: MediaQuery.paddingOf(context).top + 8,
      left: 14,
      right: 14,
      child: Material(
        elevation: 16,
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isError ? Colors.red.shade50 : const Color(0xffecfdf5),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.45)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    color: isError
                        ? Colors.red.shade800
                        : Colors.green.shade800,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () =>
                    context.read<MobileOrderBloc>().add(MessageCleared()),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.close,
                    color: isError
                        ? Colors.red.shade700
                        : Colors.green.shade700,
                    size: 18,
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
