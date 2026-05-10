# Backend API & Architecture

**Version:** Node.js / TypeScript / Fastify

## Rules & Patterns

1.  **Framework Stack**: Fastify for the HTTP layer, Drizzle ORM for PostgreSQL queries, local Docker for local dev PostgreSQL, and Postman for automated routes testing.
2.  **Architecture Setup**: Modular/Monolithic. Contains defined API routes (`routes.ts`) linked into isolated modules: controllers, services, database models.
3.  **Authentication Rules**:
    *   Passwords generated through bcrypt.
    *   Auth uses HTTP POST payload containing: `email`, `password`, and optionally `name`.
    *   API returns `accessToken` and `refreshToken` securely via a JSON body to Mobile clients (or HTTP-Only cookies to web if configured).

## Endpoints Created (v1)

### `POST /api/v1/auth/register`
Creates a user.
- **Request Body**: `{ "name": "...", "email": "...", "password": "..." }`
- **Response**: Code `201 Created` with tokens.

### `POST /api/v1/auth/login`
Logs an existing user.
- **Request Body**: `{ "email": "...", "password": "..." }`
- **Response**: Code `200 OK` with JSON `{ "accessToken": "...", "refreshToken": "..." }`.

### `POST /api/v1/auth/logout`
Deletes/revokes the session.
- **Request Body**: `{ "refreshToken": "..." }`

## Work left to do
- Synchronization engine logic.
- Book imports and library.
