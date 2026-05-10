# Architecture Decisions for LectorSync (ADRs)

## 1. Backend Stack
- **Framework**: Fastify (Node.js) for high performance.
- **Language**: TypeScript for strict typing.
- **ORM**: Drizzle ORM for type-safe SQL queries.
- **Database**: PostgreSQL (neon.tech or local docker).
- **Authentication**: JWT access and refresh tokens, stored securely.
- **Structure**: Layered architecture (`routes`, `controllers`, `services`, `repositories`).

## 2. Frontend Stack (Mobile/Desktop)
- **Framework**: Flutter 3+.
- **State Management**: BLoC / Cubit (`flutter_bloc`). Chosen for reactive, predictable states.
- **Routing**: `go_router` for declarative routing and deep linking capabilities.
- **Dependency Injection**: `get_it`.
- **Networking**: `dio` for robust HTTP requests, configured with global interceptors for intercepting 401s and injecting JWTs.
- **Storage**: `flutter_secure_storage` to keep JWT tokens safe cryptographically.

## 3. App Architecture (Frontend)
- **Clean Architecture**: 
  - `presentation`: UI (Widgets, Pages) and State Management (Cubit/BLoC).
  - `domain`: Business Logic (UseCases, Entities, abstract Repositories).
  - `data`: External APIs, local DB, Models, and concrete Repository implementations.
- **Theming**: Strict usage of Material 3 and `ColorScheme` (e.g. `surface`, not deprecated `background`).

## 4. Current State (April 2026)
- **Backend**: Basic auth endpoints (`/login`, `/register`, `/logout`) are functioning.
- **Frontend**: Scaffolding complete.
  - Dependency Injection setup ✅
  - GoRouter setup with Auth Guard ✅
  - Material 3 Theming ✅
  - Remote Auth Repository via Dio ✅
  - AuthCubit with Secure Storage integration ✅
  - Login & Register views built and connected to BLoC ✅
  - Library View base structure ✅
