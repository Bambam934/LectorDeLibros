abstract final class RouteConstants {
  static const String login = '/auth/login';
  static const String register = '/auth/register';
  static const String library = '/library';
  static const String bookReadPath = '/books/:bookId/read';

  static String bookRead(String bookId) => '/books/$bookId/read';
}
