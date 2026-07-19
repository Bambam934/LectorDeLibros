import { and, asc, eq } from 'drizzle-orm';
import fs from 'node:fs';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';

import { requireAccessToken } from '../../../core/auth.js';
import { env } from '../../../core/env.js';
import { getAuthenticatedUser } from '../../../core/jwt.js';
import { realtimeBus } from '../../../core/realtime-bus.js';
import { createTtsProvider } from '../../../core/tts/index.js';
import { getDatabaseUnavailableReason, getDb } from '../../../db/client.js';
import { books, chapterAudio, chapters, readingProgress } from '../../../db/schema.js';
import {
  bookParamsSchema,
  dbUnavailableReply,
  getAudioFilePath,
  getAudioUrlPath,
  isDbConnectionError,
  readClientId,
  saveAudioFile
} from './shared.js';

const chapterParamsSchema = z.object({
  bookId: z.string().uuid(),
  chapterId: z.string().uuid()
});

const chapterAudioSchema = z.object({
  voice_id: z
    .string()
    .min(1)
    .max(100)
    .regex(/^[a-zA-Z0-9_-]+$/, 'voice_id contains invalid characters')
    .optional(),
  provider: z.enum(['elevenlabs', 'mock']).default('mock')
});

const chapterAudioParamsSchema = z.object({
  bookId: z.string().uuid(),
  chapterId: z.string().uuid()
});

const saveProgressSchema = z.object({
  chapter_id: z.string().uuid(),
  word_index: z.number().int().min(0),
  audio_position_ms: z.number().int().min(0)
});

const audioParamsSchema = z.object({
  chapterId: z.string().uuid(),
  voiceId: z.string().min(1).max(100).regex(/^[a-zA-Z0-9_-]+$/)
});

export function registerReaderRoutes(app: FastifyInstance): void {
  app.get('/api/v1/books/:bookId/chapters', { preHandler: requireAccessToken }, async (request, reply) => {
    const params = bookParamsSchema.parse(request.params);
    const authUser = getAuthenticatedUser(request);
    const db = getDb();

    if (!db) {
      return reply.send([]);
    }

    try {
      const ownedBook = await db
        .select({ id: books.id })
        .from(books)
        .where(and(eq(books.id, params.bookId), eq(books.userId, authUser.sub)))
        .limit(1);

      if (!ownedBook[0]) {
        return reply.code(404).send({
          error: 'NotFound',
          message: 'El libro no existe o no pertenece al usuario autenticado.'
        });
      }

      const rows = await db
        .select({
          id: chapters.id,
          title: chapters.title,
          orderIndex: chapters.orderIndex,
          wordCount: chapters.wordCount
        })
        .from(chapters)
        .where(eq(chapters.bookId, params.bookId))
        .orderBy(asc(chapters.orderIndex));

      return reply.send(
        rows.map((r) => ({
          id: r.id,
          title: r.title,
          order_index: r.orderIndex,
          word_count: r.wordCount
        }))
      );
    } catch (err) {
      if (isDbConnectionError(err)) {
        return reply.code(503).send(dbUnavailableReply());
      }
      throw err;
    }
  });

  app.get('/api/v1/books/:bookId/chapters/:chapterId', { preHandler: requireAccessToken }, async (request, reply) => {
    const params = chapterParamsSchema.parse(request.params);
    const authUser = getAuthenticatedUser(request);
    const db = getDb();

    if (!db) {
      return reply.code(404).send({
        error: 'NotFound',
        message: getDatabaseUnavailableReason()
      });
    }

    try {
      const ownedBook = await db
        .select({ id: books.id })
        .from(books)
        .where(and(eq(books.id, params.bookId), eq(books.userId, authUser.sub)))
        .limit(1);

      if (!ownedBook[0]) {
        return reply.code(404).send({
          error: 'NotFound',
          message: 'El libro no existe o no pertenece al usuario autenticado.'
        });
      }

      const rows = await db
        .select({
          id: chapters.id,
          title: chapters.title,
          orderIndex: chapters.orderIndex,
          wordCount: chapters.wordCount,
          textContent: chapters.textContent
        })
        .from(chapters)
        .where(and(eq(chapters.id, params.chapterId), eq(chapters.bookId, params.bookId)))
        .limit(1);

      const chapter = rows[0];
      if (!chapter) {
        return reply.code(404).send({
          error: 'NotFound',
          message: 'Capítulo no encontrado.'
        });
      }

      return reply.send({
        id: chapter.id,
        title: chapter.title,
        order_index: chapter.orderIndex,
        word_count: chapter.wordCount,
        text: chapter.textContent ?? ''
      });
    } catch (err) {
      if (isDbConnectionError(err)) {
        return reply.code(503).send(dbUnavailableReply());
      }
      throw err;
    }
  });

  app.post('/api/v1/books/:bookId/chapters/:chapterId/audio', { preHandler: requireAccessToken }, async (request, reply) => {
    const params = chapterAudioParamsSchema.parse(request.params);
    const body = chapterAudioSchema.parse(request.body ?? {});
    const authUser = getAuthenticatedUser(request);
    const db = getDb();

    if (!db) {
      const ttsProvider = createTtsProvider();
      const voiceId = body.voice_id ?? env.ELEVENLABS_DEFAULT_VOICE_ID;
      if (!voiceId) {
        return reply.code(400).send({
          error: 'BadRequest',
          message: 'voice_id is required when ELEVENLABS_DEFAULT_VOICE_ID is not configured.'
        });
      }
      return reply.send({
        book_id: params.bookId,
        chapter_id: params.chapterId,
        provider: ttsProvider.name,
        audio_url: null,
        duration_ms: 0,
        word_timestamps: [],
        source: 'fallback',
        warning: getDatabaseUnavailableReason()
      });
    }

    try {
      const ownedBook = await db
        .select({ id: books.id })
        .from(books)
        .where(and(eq(books.id, params.bookId), eq(books.userId, authUser.sub)))
        .limit(1);

      if (!ownedBook[0]) {
        return reply.code(404).send({
          error: 'NotFound',
          message: 'El libro no existe o no pertenece al usuario autenticado.'
        });
      }

      const existingChapter = await db
        .select({ id: chapters.id, textContent: chapters.textContent })
        .from(chapters)
        .where(and(eq(chapters.id, params.chapterId), eq(chapters.bookId, params.bookId)))
        .limit(1);

      if (!existingChapter[0]) {
        return reply.code(404).send({
          error: 'NotFound',
          message: 'Capítulo no encontrado.'
        });
      }

      const voiceId = body.voice_id ?? env.ELEVENLABS_DEFAULT_VOICE_ID;
      if (!voiceId) {
        return reply.code(400).send({
          error: 'BadRequest',
          message: 'voice_id is required when ELEVENLABS_DEFAULT_VOICE_ID is not configured.'
        });
      }
      const providerName = body.provider;

      const cachedAudio = await db
        .select({
          audioKey: chapterAudio.audioKey,
          durationMs: chapterAudio.durationMs,
          wordTimestamps: chapterAudio.wordTimestamps
        })
        .from(chapterAudio)
        .where(
          and(
            eq(chapterAudio.chapterId, params.chapterId),
            eq(chapterAudio.voiceId, voiceId),
            eq(chapterAudio.ttsProvider, providerName)
          )
        )
        .limit(1);

      if (cachedAudio[0]) {
        const audioFilePath = getAudioFilePath(params.chapterId, voiceId);
        const fileExists = fs.existsSync(audioFilePath);

        return reply.send({
          book_id: params.bookId,
          chapter_id: params.chapterId,
          provider: providerName,
          audio_url: fileExists ? getAudioUrlPath(params.chapterId, voiceId) : null,
          duration_ms: cachedAudio[0].durationMs,
          word_timestamps: cachedAudio[0].wordTimestamps,
          source: 'cache'
        });
      }

      const chapterText = existingChapter[0].textContent ?? '';
      if (!chapterText.trim()) {
        return reply.send({
          book_id: params.bookId,
          chapter_id: params.chapterId,
          provider: providerName,
          audio_url: null,
          duration_ms: 0,
          word_timestamps: [],
          source: 'empty'
        });
      }

      const ttsProvider = createTtsProvider();
      const result = await ttsProvider.generate(chapterText, voiceId);

      const audioUrlPath = result.audioBuffer.length > 0
        ? getAudioUrlPath(params.chapterId, voiceId)
        : null;

      if (result.audioBuffer.length > 0) {
        const audioFilePath = getAudioFilePath(params.chapterId, voiceId);
        await saveAudioFile(audioFilePath, result.audioBuffer);
      }

      try {
        await db.insert(chapterAudio).values({
          chapterId: params.chapterId,
          voiceId,
          ttsProvider: providerName,
          audioKey: audioUrlPath ?? '',
          durationMs: result.durationMs,
          wordTimestamps: result.wordTimestamps
        });
      } catch (insertErr) {
        const recheck = await db
          .select({ durationMs: chapterAudio.durationMs, wordTimestamps: chapterAudio.wordTimestamps })
          .from(chapterAudio)
          .where(and(eq(chapterAudio.chapterId, params.chapterId), eq(chapterAudio.voiceId, voiceId), eq(chapterAudio.ttsProvider, providerName)))
          .limit(1);
        if (recheck[0]) {
          return reply.send({
            book_id: params.bookId, chapter_id: params.chapterId, provider: providerName,
            audio_url: audioUrlPath, duration_ms: recheck[0].durationMs,
            word_timestamps: recheck[0].wordTimestamps, source: 'cache'
          });
        }
        throw insertErr;
      }

      return reply.send({
        book_id: params.bookId,
        chapter_id: params.chapterId,
        provider: providerName,
        audio_url: audioUrlPath,
        duration_ms: result.durationMs,
        word_timestamps: result.wordTimestamps,
        source: 'generated'
      });
    } catch (err) {
      if (isDbConnectionError(err)) {
        return reply.code(503).send(dbUnavailableReply());
      }
      throw err;
    }
  });

  app.put('/api/v1/books/:bookId/progress', { preHandler: requireAccessToken }, async (request, reply) => {
    const params = bookParamsSchema.parse(request.params);
    const body = saveProgressSchema.parse(request.body);
    const authUser = getAuthenticatedUser(request);
    const db = getDb();

    if (!db) {
      return reply.code(204).send();
    }

    try {
      const ownedBook = await db
        .select({ id: books.id, totalWords: books.totalWords })
        .from(books)
        .where(and(eq(books.id, params.bookId), eq(books.userId, authUser.sub)))
        .limit(1);

      if (!ownedBook[0]) {
        return reply.code(404).send({
          error: 'NotFound',
          message: 'El libro no existe o no pertenece al usuario autenticado.'
        });
      }

      const totalWords = ownedBook[0].totalWords ?? 0;
      const percentage =
        totalWords > 0 ? Math.min((body.word_index / totalWords) * 100, 100) : 0;

      const lastReadAt = new Date();
      await db
        .insert(readingProgress)
        .values({
          userId: authUser.sub,
          bookId: params.bookId,
          chapterId: body.chapter_id,
          wordIndex: body.word_index,
          audioPositionMs: body.audio_position_ms,
          percentage,
          lastReadAt
        })
        .onConflictDoUpdate({
          target: [readingProgress.userId, readingProgress.bookId],
          set: {
            chapterId: body.chapter_id,
            wordIndex: body.word_index,
            audioPositionMs: body.audio_position_ms,
            percentage,
            lastReadAt
          }
        });

      // Fan out to every other device the user has connected via SSE.
      // The originating clientId travels along so the writer's own SSE
      // listener can drop the echo instead of double-applying its own
      // write. lastReadAt acts as the server-authoritative timestamp the
      // peers use for last-write-wins reconciliation if two devices race.
      realtimeBus.publish(authUser.sub, {
        type: 'progress.updated',
        clientId: readClientId(request),
        data: {
          bookId: params.bookId,
          chapterId: body.chapter_id,
          wordIndex: body.word_index,
          audioPositionMs: body.audio_position_ms,
          percentage,
          lastReadAt: lastReadAt.toISOString()
        }
      });

      return reply.code(204).send();
    } catch (err) {
      if (isDbConnectionError(err)) {
        return reply.code(503).send(dbUnavailableReply());
      }
      throw err;
    }
  });

  app.get('/api/v1/audio/:chapterId-:voiceId.mp3', { preHandler: requireAccessToken }, async (request, reply) => {
    const params = audioParamsSchema.parse(request.params);
    const filePath = getAudioFilePath(params.chapterId, params.voiceId);

    if (!fs.existsSync(filePath)) {
      return reply.code(404).send({
        error: 'NotFound',
        message: 'Audio no encontrado.'
      });
    }

    const stream = fs.createReadStream(filePath);
    return reply.type('audio/mpeg').send(stream);
  });
}
