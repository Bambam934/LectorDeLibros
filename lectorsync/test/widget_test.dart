import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lectorsync/features/auth/domain/repositories/auth_repository.dart';
import 'package:lectorsync/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:lectorsync/features/auth/presentation/pages/login_page.dart';

/// Repositorio mínimo para tests de widget: evita `RemoteAuthRepository`,
/// `FlutterSecureStorage` y canales de plataforma que pueden colgar `pumpAndSettle`.
class _FakeAuthRepository implements AuthRepository {
  @override
  Future<bool> login({
    required String email,
    required String password,
  }) async =>
      false;

  @override
  Future<bool> register({
    required String name,
    required String email,
    required String password,
  }) async =>
      false;
}

void main() {
  testWidgets('shows login as initial screen', (WidgetTester tester) async {
    final cubit = AuthCubit(_FakeAuthRepository());
    await cubit.checkAuthStatus();

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<AuthCubit>.value(
          value: cubit,
          child: const LoginPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('LectorSync'), findsOneWidget);
    expect(find.text('Inicia sesión'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsOneWidget);

    await cubit.close();
  });
}

