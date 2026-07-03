import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app_theme.dart';
import 'core/supabase_config.dart';
import 'data/mobile_order_local_data_source.dart';
import 'data/mobile_order_remote_data_source.dart';
import 'data/mobile_order_repository_impl.dart';
import 'domain/mobile_order_repository.dart';
import 'presentation/bloc/mobile_order_bloc.dart';
import 'presentation/pages/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    publishableKey: SupabaseConfig.anonKey,
  );

  final repository = MobileOrderRepositoryImpl(
    MobileOrderRemoteDataSource(Supabase.instance.client),
    MobileOrderLocalDataSource(),
  );

  runApp(MobileOrderPickingApp(repository: repository));
}

class MobileOrderPickingApp extends StatelessWidget {
  final MobileOrderRepository repository;

  const MobileOrderPickingApp({super.key, required this.repository});

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider.value(
      value: repository,
      child: BlocProvider(
        create: (_) => MobileOrderBloc(repository)..add(AppStarted()),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Store Picking',
          theme: AppTheme.light(),
          home: const AppShell(),
        ),
      ),
    );
  }
}
