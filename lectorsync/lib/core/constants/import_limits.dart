/// Límite de tamaño para importar un libro en bytes (50 MiB).
///
/// Debe mantenerse alineado con el límite del backend (V-12, `fileSize` en
/// `backend/src/app.ts`).
const int kMaxImportBytes = 50 * 1024 * 1024;
