import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/di/injection_container.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_cubit.dart';
import 'features/auth/presentation/cubit/auth_cubit.dart';

class LectorSyncApp extends StatelessWidget {
  const LectorSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthCubit>(
          create: (_) {
            final cubit = sl<AuthCubit>()..checkAuthStatus();
            cubit.listenSessionExpired(sessionExpiredNotifier);
            return cubit;
          },
        ),
        BlocProvider<ThemeCubit>(
          create: (_) => ThemeCubit(),
        ),
      ],
      child: Builder(
        builder: (context) {
          final authCubit = context.read<AuthCubit>();
          final router = buildRouter(authCubit);

          return BlocBuilder<ThemeCubit, ThemeMode>(
            builder: (context, themeMode) {
              return MaterialApp.router(
                title: 'LectorSync',
                debugShowCheckedModeBanner: false,
                theme: AppTheme.light,
                darkTheme: AppTheme.dark,
                themeMode: themeMode,
                routerConfig: router,
              );
            },
          );
        },
      ),
    );
  }
}
