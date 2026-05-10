# LectorSync Project Architecture

## High Level Overview

```mermaid
graph TD
  A[Flutter App (iOS, Android, macOS, Web, Windows)] <-->|HTTPS/REST JSON| B(Fastify Node.js Backend)
  A <-->|Secure Storage JWT| C[(Local Token Store)]
  B <-->|Postgres SQL Drizzle ORM| D[(PostgreSQL DB)]
```

## Workflows Completed

### Authentication Flow (Completed April 2026)
1. User interacts with Flutter `LoginPage`/`RegisterPage`.
2. Widget triggers `AuthCubit.login(email, password)`.
3. `AuthCubit` communicates with `RemoteAuthRepository.login()`.
4. `RemoteAuthRepository` performs HTTP POST `/api/v1/auth/login` via `DioApiClient`.
5. Dio intercepts response, storing tokens in `SecureStorage`.
6. State emits `Authenticated()`.
7. `GoRouter` instantly redirects user to `/library`.

### Next Areas (Planned)
*   **Book Importing Workflow** (`LibraryBloc` handling `.epub` picking).
*   **Reader Engine**: The actual rendering logic inside Flutter parsing chapters.
*   **Sync Engine**: Websockets or long-polling syncing between multiple devices tracking exactly what current page and audio position the user is on.
*   **Sensory UI**: Enhancing UI for book-reading to include custom dark modes, ambient sound, reading progress animations.
