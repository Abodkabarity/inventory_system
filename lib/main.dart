import 'package:daily_order/presentation/app/bloc/app_event.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/supabase_config.dart';
import 'core/router/app_router.dart';
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

  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    anonKey: SupabaseConfig.anonKey,
  );
  final user = Supabase.instance.client.auth.currentUser;
  print('AUTH USER (startup): ${user?.id}');
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
    MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => AppBloc(getMe: getMe)..add(const AppStarted()),
        ),
        BlocProvider(
          create: (_) => AuthBloc(signIn: signIn, signOut: signOut),
        ),
        // CatalogBloc will be created in HomePage (needs branchId)
      ],
      child: MyApp(
        router: router,
        getMyBranch: getMyBranch,
        getCatalog: getCatalog,
      ),
    ),
  );
}

class MyApp extends StatelessWidget {
  final GoRouter router;
  final GetMyBranch getMyBranch;
  final GetCatalogItemsForBranch getCatalog;

  const MyApp({
    super.key,
    required this.router,
    required this.getMyBranch,
    required this.getCatalog,
  });

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider.value(
      value: getMyBranch,
      child: RepositoryProvider.value(
        value: getCatalog,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          routerConfig: router,
          theme: ThemeData(useMaterial3: true),
        ),
      ),
    );
  }
}
