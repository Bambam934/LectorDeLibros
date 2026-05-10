# LectorSync App (Flutter)

Cliente Flutter para LectorSync. Consume el backend local en `http://10.0.2.2:3000` cuando se ejecuta en emulador Android.

## Requisitos

- Flutter 3.24+
- Dart SDK compatible con la version del proyecto
- Emulador Android o dispositivo fisico
- Backend de LectorSync corriendo en local

## Arranque rapido

```bash
cd lectorsync
flutter pub get
flutter run -d emulator-5554
```

## Flujo implementado

- Login con email/password
- Registro con nombre/email/password
- Login automatico despues de registro exitoso
- Manejo de usuario existente (`409`) para continuar a login automatico
- Logout con limpieza de tokens en almacenamiento seguro
- Redireccion automatica por estado de autenticacion con `GoRouter`

## Pantallas principales

- `LoginPage`
- `RegisterPage`
- `LibraryPage`

## Validaciones de formulario (UI)

- Campos requeridos
- Email con formato valido
- Password con minimo 8 caracteres

## Integracion con backend

- Login espera y persiste:
  - `access_token`
  - `refresh_token`
- Endpoints usados en auth:
  - `POST /api/v1/auth/register`
  - `POST /api/v1/auth/login`
  - `POST /api/v1/auth/logout`

## Verificacion recomendada (E2E manual)

1. Levantar backend y PostgreSQL:
   - `cd ../backend`
   - `npm run db:up`
   - `npm run dev`
2. Levantar app Flutter:
   - `cd ../lectorsync`
   - `flutter run -d emulator-5554`
3. Probar:
   - registrar usuario nuevo
   - validar redireccion a library
   - cerrar sesion
   - iniciar sesion con la misma cuenta

## Comando de calidad

```bash
flutter analyze
```
