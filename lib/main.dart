import 'package:daily_order/presentation/app/bloc/app_event.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/supabase_config.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_colors.dart';
import 'data/datasources/remote/supabase_auth_remote_ds.dart';
import 'data/datasources/remote/supabase_branch_remote_ds.dart';
import 'data/datasources/remote/supabase_item_remote_ds.dart';
import 'data/repositories/auth_repository_impl.dart';
import 'data/repositories/branch_repository_impl.dart';
import 'data/repositories/item_repository_impl.dart';
import 'domain/usecases/get_catalog_items_for_branch.dart';
import 'domain/usecases/get_me.dart';
import 'domain/usecases/get_my_branch.dart';
import 'domain/usecases/sign_in.dart';
import 'domain/usecases/sign_out.dart';
import 'presentation/app/bloc/app_bloc.dart';
import 'presentation/auth/bloc/auth_bloc.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  SupabaseConfig.validate();
  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    anonKey: SupabaseConfig.anonKey,

    authOptions: const FlutterAuthClientOptions(autoRefreshToken: true),
  );
  // DataSources
  final authDs = SupabaseAuthRemoteDs(Supabase.instance.client);
  final branchDs = SupabaseBranchRemoteDs(Supabase.instance.client);
  final itemDs = SupabaseItemRemoteDs(Supabase.instance.client);

  // Repositories
  final authRepo = AuthRepositoryImpl(authDs);
  final branchRepo = BranchRepositoryImpl(branchDs);
  final itemRepo = ItemRepositoryImpl(itemDs);

  // Usecases
  final signIn = SignIn(authRepo);
  final signOut = SignOut(authRepo);
  final getMe = GetMe(authRepo);
  final getMyBranch = GetMyBranch(branchRepo);
  final getCatalog = GetCatalogItemsForBranch(itemRepo);

  final router = AppRouter.createRouter();

  runApp(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: getMyBranch),
        RepositoryProvider.value(value: getCatalog),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) => AppBloc(getMe: getMe)..add(const AppStarted()),
          ),
          BlocProvider(
            create: (_) => AuthBloc(signIn: signIn, signOut: signOut),
          ),
        ],
        child: MyApp(router: router),
      ),
    ),
  );
}

class MyApp extends StatelessWidget {
  final GoRouter router;
  static const double _appUiScale = 0.81;

  const MyApp({super.key, required this.router});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(1600, 800),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp.router(
          debugShowCheckedModeBanner: false,
          routerConfig: router,
          builder: (context, child) {
            return _ScaledAppShell(
              scale: _appUiScale,
              child: child ?? const SizedBox.shrink(),
            );
          },
          theme: ThemeData(
            useMaterial3: true,

            textSelectionTheme: const TextSelectionThemeData(
              selectionColor: AppColors.primaryColor,
              selectionHandleColor: AppColors.primaryColor,
              cursorColor: AppColors.primaryColor,
            ),
          ),
        );
      },
    );
  }
}

class _ScaledAppShell extends StatelessWidget {
  final double scale;
  final Widget child;

  const _ScaledAppShell({required this.scale, required this.child});

  @override
  Widget build(BuildContext context) {
    if (scale == 1) return child;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
          return Transform.scale(
            scale: scale,
            alignment: Alignment.topLeft,
            child: child,
          );
        }

        final width = constraints.maxWidth / scale;
        final height = constraints.maxHeight / scale;
        final media = MediaQuery.maybeOf(context);
        final scaledChild = media == null
            ? child
            : MediaQuery(
                data: media.copyWith(size: Size(width, height)),
                child: child,
              );

        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: width,
            maxWidth: width,
            minHeight: height,
            maxHeight: height,
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.topLeft,
              child: SizedBox(width: width, height: height, child: scaledChild),
            ),
          ),
        );
      },
    );
  }
}
