import '../../domain/repositories/auth_repository.dart';

class LocalAuthRepository implements AuthRepository {
  @override
  Future<bool> login({
    required String email,
    required String password,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    return email.isNotEmpty && password.isNotEmpty;
  }

  @override
  Future<bool> register({
    required String email,
    required String password,
    required String name,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    return email.isNotEmpty && password.isNotEmpty && name.isNotEmpty;
  }
}
