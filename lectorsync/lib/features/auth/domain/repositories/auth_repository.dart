abstract interface class AuthRepository {
  Future<bool> login({
    required String email,
    required String password,
  });

  Future<bool> register({
    required String email,
    required String password,
    required String name,
  });
}
