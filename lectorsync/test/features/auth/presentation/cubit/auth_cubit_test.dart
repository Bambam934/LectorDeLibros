import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/features/auth/data/repositories/local_auth_repository.dart';
import 'package:lectorsync/features/auth/domain/repositories/auth_repository.dart';
import 'package:lectorsync/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:lectorsync/features/auth/presentation/cubit/auth_state.dart';

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
  group('AuthCubit', () {
    test('LocalAuthRepository autentica directo y no permite cerrar sesion',
        () async {
      final cubit = AuthCubit(LocalAuthRepository());

      await cubit.checkAuthStatus();

      expect(cubit.state, const Authenticated());
      expect(cubit.canLogout, false);

      await cubit.close();
    });

    test('repositorio falso emite Unauthenticated y permite cerrar sesion',
        () async {
      final cubit = AuthCubit(_FakeAuthRepository());

      await cubit.checkAuthStatus();

      expect(cubit.state, const Unauthenticated());
      expect(cubit.canLogout, true);

      await cubit.close();
    });
  });
}
