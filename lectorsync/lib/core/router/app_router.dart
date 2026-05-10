import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/cubit/auth_cubit.dart';
import '../../features/auth/presentation/cubit/auth_state.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/register_page.dart';
import '../../features/library/presentation/pages/library_page.dart';
import '../../features/reader/presentation/pages/reader_page.dart';
import '../constants/route_constants.dart';

GoRouter buildRouter(AuthCubit authCubit) {
  return GoRouter(
    initialLocation: RouteConstants.login,
    redirect: (context, state) {
      final bool isAuth = authCubit.state is Authenticated;
      final bool isLoggingIn =
          state.matchedLocation == RouteConstants.login ||
          state.matchedLocation == RouteConstants.register;

      if (!isAuth && !isLoggingIn) return RouteConstants.login;
      if (isAuth && isLoggingIn) return RouteConstants.library;
      return null;
    },
    refreshListenable: GoRouterRefreshStream(authCubit.stream),
    routes: <RouteBase>[
      GoRoute(
        path: RouteConstants.login,
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: RouteConstants.register,
        builder: (context, state) => const RegisterPage(),
      ),
      GoRoute(
        path: RouteConstants.library,
        builder: (context, state) => const LibraryPage(),
      ),
      GoRoute(
        path: RouteConstants.bookReadPath,
        builder: (context, state) {
          final bookId = state.pathParameters['bookId'] ?? '';

          final extras = state.extra;
          String bookTitle = 'Lector';
          String? initialChapterId;
          int initialWordIndex = 0;

          if (extras is Map<String, dynamic>) {
            final title = extras['bookTitle'];
            if (title is String && title.isNotEmpty) {
              bookTitle = title;
            }

            final chapterId = extras['initialChapterId'];
            if (chapterId is String && chapterId.isNotEmpty) {
              initialChapterId = chapterId;
            }

            final wordIndex = extras['initialWordIndex'];
            if (wordIndex is int) {
              initialWordIndex = wordIndex;
            }
          }

          return ReaderPage(
            bookId: bookId,
            bookTitle: bookTitle,
            initialChapterId: initialChapterId,
            initialWordIndex: initialWordIndex,
          );
        },
      ),
    ],
  );
}

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen(
      (dynamic _) => notifyListeners(),
    );
  }
  late final dynamic _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
