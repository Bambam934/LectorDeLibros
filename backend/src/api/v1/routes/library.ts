import { and, eq } from 'drizzle-orm';
import fs from 'node:fs';
import type { FastifyInstance } from 'fastify';

import { requireAccessToken } from '../../../core/auth.js';
import { getAuthenticatedUser } from '../../../core/jwt.js';
import { detectFormat, isSupportedFormat, parseBookFile } from '../../../core/parsers/index.js';
import { getDb } from '../../../db/client.js';
import { books, chapterAudio, chapters, readingProgress } from '../../../db/schema.js';
import {
  bookParamsSchema,
  dbUnavailableReply,
  getAudioFilePath,
  isDbConnectionError
} from './shared.js';

export function registerLibraryRoutes(app: FastifyInstance): void {
  app.get('/api/v1/library', { preHandler: requireAccessToken }, async (request, reply) => {
    const authUser = getAuthenticatedUser(request);
    const db = getDb();
    if (!db) {
      return [];
    }

    try {
      const rows = await db
        .select({
          id: books.id,
          title: books.title,
          author: books.author,
          fileFormat: books.fileFormat,
          status: books.status,
          totalChapters: books.totalChapters,
          totalWords: books.totalWords,
          chapterId: readingProgress.chapterId,
          wordIndex: readingProgress.wordIndex,
          audioPositionMs: readingProgress.audioPositionMs,
          percentage: readingProgress.percentage
        })
        .from(books)
        .leftJoin(
          readingProgress,
          and(eq(readingProgress.bookId, books.id), eq(readingProgress.userId, authUser.sub))
        )
        .where(eq(books.userId, authUser.sub));

      return rows.map((row) => ({
        id: row.id,
        title: row.title,
        author: row.author,
        file_format: row.fileFormat,
        status: row.status,
        total_chapters: row.totalChapters,
        total_words: row.totalWords,
        progress: row.chapterId
          ? {
              chapter_id: row.chapterId,
              word_index: row.wordIndex ?? 0,
              audio_position_ms: row.audioPositionMs ?? 0,
              percentage: row.percentage ?? 0
            }
          : null
      }));
    } catch (err) {
      if (isDbConnectionError(err)) {
        return reply.code(503).send(dbUnavailableReply());
      }
      throw err;
    }
  });

  app.post('/api/v1/library/import', { preHandler: requireAccessToken }, async (request, reply) => {
    const authUser = getAuthenticatedUser(request);

    const file = await request.file();
    if (!file) {
      return reply.code(400).send({
        error: 'BadRequest',
        message: 'No se recibió ningún archivo. Envía el archivo con el campo "file".'
      });
    }

    const format = detectFormat(file.filename, file.mimetype);
    if (!isSupportedFormat(format)) {
      return reply.code(400).send({
        error: 'BadRequest',
        message: 'Formato no soportado. Se admiten: EPUB, PDF, TXT, Markdown.'
      });
    }

    const buffer = await file.toBuffer();

    let parsed;
    try {
      parsed = await parseBookFile(buffer, format, file.filename);
    } catch (err) {
      request.log.error(err, 'Error al parsear archivo');
      return reply.code(400).send({
        error: 'InvalidFile',
        message: err instanceof Error ? err.message : 'No se pudo procesar el archivo.'
      });
    }

    if (parsed.chapters.length === 0) {
      return reply.code(400).send({
        error: 'EmptyFile',
        message: 'El archivo no contiene capítulos legibles.'
      });
    }

    if (parsed.chapters.length > 500) {
      return reply.code(400).send({
        error: 'TooManyChapters',
        message: 'El archivo excede el límite de 500 capítulos.'
      });
    }

    if (parsed.totalWords > 5_000_000) {
      return reply.code(400).send({
        error: 'FileTooLarge',
        message: 'El archivo excede el límite de 5 millones de palabras.'
      });
    }

    const db = getDb();
    if (!db) {
      return reply.code(503).send(dbUnavailableReply());
    }

    try {
      const inserted = await db
        .insert(books)
        .values({
          userId: authUser.sub,
          title: parsed.title,
          author: parsed.author,
          language: parsed.language,
          fileFormat: parsed.fileFormat,
          status: 'ready',
          totalWords: parsed.totalWords,
          totalChapters: parsed.chapters.length
        })
        .returning({
          id: books.id,
          title: books.title,
          author: books.author,
          status: books.status,
          language: books.language,
          fileFormat: books.fileFormat,
          totalChapters: books.totalChapters,
          totalWords: books.totalWords
        });

      const createdBook = inserted[0];
      if (!createdBook) {
        return reply.code(500).send({
          error: 'InsertFailed',
          message: 'No se pudo guardar el libro en la base de datos.'
        });
      }

      await db.insert(chapters).values(
        parsed.chapters.map((c) => ({
          bookId: createdBook.id,
          title: c.title,
          orderIndex: c.orderIndex,
          wordCount: c.wordCount,
          textContent: c.text
        }))
      );

      return reply.code(201).send({
        id: createdBook.id,
        title: createdBook.title,
        author: createdBook.author,
        status: createdBook.status,
        language: createdBook.language,
        file_format: createdBook.fileFormat,
        total_chapters: createdBook.totalChapters,
        total_words: createdBook.totalWords
      });
    } catch (err) {
      if (isDbConnectionError(err)) {
        return reply.code(503).send(dbUnavailableReply());
      }
      throw err;
    }
  });

  app.delete('/api/v1/books/:bookId', { preHandler: requireAccessToken }, async (request, reply) => {
    const params = bookParamsSchema.parse(request.params);
    const authUser = getAuthenticatedUser(request);
    const db = getDb();

    if (!db) {
      return reply.code(503).send(dbUnavailableReply());
    }

    try {
      const audioFiles = await db
        .select({ chapterId: chapterAudio.chapterId, voiceId: chapterAudio.voiceId })
        .from(chapterAudio)
        .innerJoin(chapters, eq(chapters.id, chapterAudio.chapterId))
        .where(eq(chapters.bookId, params.bookId));

      const result = await db
        .delete(books)
        .where(and(eq(books.id, params.bookId), eq(books.userId, authUser.sub)))
        .returning({ id: books.id });

      if (result.length === 0) {
        return reply.code(404).send({
          error: 'NotFound',
          message: 'El libro no existe o no pertenece al usuario autenticado.'
        });
      }

      for (const af of audioFiles) {
        try {
          const filePath = getAudioFilePath(af.chapterId, af.voiceId);
          await fs.promises.unlink(filePath);
        } catch {
          // File may not exist on disk
        }
      }

      return reply.code(204).send();
    } catch (err) {
      if (isDbConnectionError(err)) {
        return reply.code(503).send(dbUnavailableReply());
      }
      throw err;
    }
  });
}
