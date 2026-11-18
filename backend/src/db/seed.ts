import { and, eq } from 'drizzle-orm';

import { hashPassword } from '../core/password.js';
import { getDb } from './client.js';
import { books, readingProgress, users } from './schema.js';

async function main() {
  // El usuario demo es de desarrollo: en producción sería una cuenta con
  // contraseña conocida por cualquiera que lea este repo (que es público).
  if (process.env.NODE_ENV === 'production') {
    throw new Error('El seed no se ejecuta con NODE_ENV=production.');
  }
  const demoPassword = process.env.SEED_DEMO_PASSWORD ?? '';
  if (demoPassword.length < 12) {
    throw new Error('Define SEED_DEMO_PASSWORD (mínimo 12 caracteres) para crear el usuario demo.');
  }

  const db = getDb();
  if (!db) {
    throw new Error('DATABASE_URL no configurado. No se puede ejecutar seed.');
  }

  const demoEmail = 'demo@lectorsync.app';
  // Nunca un usuario sin password_hash: es una cuenta sin dueño.
  const passwordHash = await hashPassword(demoPassword);

  const existingUser = await db
    .select({ id: users.id })
    .from(users)
    .where(eq(users.email, demoEmail))
    .limit(1);

  if (existingUser[0]) {
    await db.update(users).set({ passwordHash }).where(eq(users.id, existingUser[0].id));
  }

  const userId = existingUser[0]?.id
    ? existingUser[0].id
    : (
        await db
          .insert(users)
          .values({
            email: demoEmail,
            name: 'demo-user',
            passwordHash
          })
          .returning({ id: users.id })
      )[0]!.id;

  const existingBook = await db
    .select({ id: books.id })
    .from(books)
    .where(and(eq(books.userId, userId), eq(books.title, 'Libro de prueba seed')))
    .limit(1);

  const bookId = existingBook[0]?.id
    ? existingBook[0].id
    : (
        await db
          .insert(books)
          .values({
            userId,
            title: 'Libro de prueba seed',
            author: 'LectorSync',
            language: 'es',
            fileFormat: 'epub',
            status: 'ready',
            totalWords: 2000,
            totalChapters: 1
          })
          .returning({ id: books.id })
      )[0]!.id;

  await db
    .insert(readingProgress)
    .values({
      userId,
      bookId,
      chapterId: null,
      wordIndex: 100,
      audioPositionMs: 5000,
      percentage: 5,
      lastReadAt: new Date()
    })
    .onConflictDoUpdate({
      target: [readingProgress.userId, readingProgress.bookId],
      set: {
        wordIndex: 100,
        audioPositionMs: 5000,
        percentage: 5,
        lastReadAt: new Date()
      }
    });

  console.log('Seed completado: usuario y libro demo listos.');
}

main().catch((error) => {
  console.error('Error en seed:', error);
  process.exit(1);
});
