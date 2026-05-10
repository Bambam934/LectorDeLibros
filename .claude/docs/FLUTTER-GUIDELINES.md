# Flutter Development Guidelines

**Version:** 3.4+ / Dart 3+

## Rules & Patterns

1.  **Architecture**: Follow Clean Architecture strictly.
    *   **Presentation**: Only UI (Widgets), State Management (Cubit, BLoC), and Route arguments. Do not call APIs directly. Access the network layer through domain repositories.
    *   **Domain**: Contracts. Entities, Repositories abstractions (e.g., `AuthRepository`), and Use Cases (if the feature demands it).
    *   **Data**: Concrete repository implementations (e.g., `RemoteAuthRepository`), API clients, DataSources, Models (with `fromJson`/`toJson`).

2.  **State Management**: 
    *   Use `flutter_bloc`.
    *   Use `Cubit` for simple operations (like Login: loading, success, error).
    *   Use `Bloc` for complex flows where tracing events (like complex synchronization over audio & text) is needed.

3.  **UI & Styling**:
    *   Material 3. Ensure apps work seamlessly in Light/Dark themes using `Theme.of(context).colorScheme`.
    *   **Never use `ColorScheme.background`**. It is deprecated in favor of `ColorScheme.surface`.
    *   Responsive layouts must constraint widths (e.g. `ConstrainedBox(maxWidth: 420)`) for login on desktops/web.

4.  **Networking & Auth**:
    *   `Dio` as the HTTP client. Access and interceptors mapped via GetIt.
    *   JWT Tokens saved securely in `flutter_secure_storage`.
    *   Routing handled declaratively with `go_router`. Utilize a nested Router mapping inside the root BLoC provider to auto-redirect unauthenticated users to `/login`.
