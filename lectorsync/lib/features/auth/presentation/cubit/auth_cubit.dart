import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/remote_auth_repository.dart';
import '../../domain/repositories/auth_repository.dart';
import 'auth_state.dart';

class AuthCubit extends Cubit<AuthState> {
  AuthCubit(this._authRepository) : super(const AuthInitial());

  final AuthRepository _authRepository;
  VoidCallback? _sessionListener;

  void listenSessionExpired(ValueNotifier<bool> notifier) {
    _sessionListener = () {
      if (state is! Unauthenticated) {
        emit(const Unauthenticated());
      }
    };
    notifier.addListener(_sessionListener!);
  }

  @override
  Future<void> close() {
    _sessionListener = null;
    return super.close();
  }

  Future<void> checkAuthStatus() async {
    try {
      if (_authRepository is RemoteAuthRepository) {
        final hasSession = await _authRepository.hasValidSession();
        if (hasSession) {
          emit(const Authenticated());
        } else {
          emit(const Unauthenticated());
        }
      } else {
        emit(const Unauthenticated());
      }
    } catch (_) {
      emit(const Unauthenticated());
    }
  }

  Future<void> login(String email, String password) async {
    emit(const AuthLoading());
    try {
      final success = await _authRepository.login(
        email: email,
        password: password,
      );

      if (success) {
        emit(const Authenticated());
      } else {
        emit(const AuthError('Correo o contraseña incorrectos.'));
        emit(const Unauthenticated());
      }
    } on AuthException catch (e) {
      emit(AuthError(e.message));
      emit(const Unauthenticated());
    } catch (_) {
      emit(const AuthError('Error al iniciar sesión. Intenta de nuevo.'));
      emit(const Unauthenticated());
    }
  }

  Future<void> register(String name, String email, String password) async {
    emit(const AuthLoading());
    try {
      final success = await _authRepository.register(
        name: name,
        email: email,
        password: password,
      );

      if (success) {
        await login(email, password);
      } else {
        emit(const AuthError('No se pudo crear la cuenta. Intenta de nuevo.'));
        emit(const Unauthenticated());
      }
    } on AuthException catch (e) {
      emit(AuthError(e.message));
      emit(const Unauthenticated());
    } catch (_) {
      emit(const AuthError('Error de conexión. Verifica tu red.'));
      emit(const Unauthenticated());
    }
  }

  Future<void> logout() async {
    if (_authRepository is RemoteAuthRepository) {
      await _authRepository.logout();
    }
    emit(const Unauthenticated());
  }
}
