import { and, asc, eq } from 'drizzle-orm';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';

import { requireAccessToken } from '../../core/auth.js';
import {
  ACCESS_TOKEN_TTL,
  createAccessToken,
  createRefreshToken,
  getAuthenticatedUser,
  REFRESH_TOKEN_TTL
} from '../../core/jwt.js';
import { hashPassword, verifyPassword } from '../../core/password.js';
import { createTtsProvider } from '../../core/tts/index.js';
import { env } from '../../core/env.js';
import { detectFormat, isSupportedFormat, parseBookFile } from '../../core/parsers/index.js';
import { getDatabaseUnavailableReason, getDb } from '../../db/client.js';
import { books, chapterAudio, chapters, readingProgress, users } from '../../db/schema.js';
import { revokeToken, isTokenRevoked } from '../../core/token-revocation.js';

const DB_ERROR_CODES = ['ECONNREFUSED', 'ECONNRESET', 'ENOTFOUND', 'ETIMEDOUT', '57P03', '08001', '08003', '08004', '08006', '08007'];

function isDbConnectionError(err: unknown): boolean {
 const seen = new Set<unknown>();
 let current: unknown = err;
 for (let depth = 0; depth < 10 && current != null; depth++) {
 if (seen.has(current)) break;
 seen.add(current);
 if (current instanceof Error) {
 const anyErr = current as { code?: string; errno?: string; name?: string };
 if (DB_ERROR_CODES.includes(anyErr.code ?? '') || DB_ERROR_CODES.includes(anyErr.errno ?? '')) return true;
 const msg = current.message?.toLowerCase() ?? '';
 if (msg.includes('econnrefused') || msg.includes('connection refused') || msg.includes('connection terminated') || msg.includes('cannot connect')) return true;
 if (current instanceof AggregateError && Array.isArray(current.errors)) {
 for (const inner of current.errors) {
 if (isDbConnectionError(inner)) return true;
 }
 }
 current = (current as { cause?: unknown }).cause;
 } else {
 current = (current as { cause?: unknown })?.cause;
 }
 }
 return false;
}

function dbUnavailableReply() {
 return {
 error: 'ServiceUnavailable' as const,
 message: 'Servicio no disponible: no se puede conectar a la base de datos.'
 };
}

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8)
});

const registerSchema = z.object({
  name: z.string().min(1).max(255),
  email: z.string().email(),
  password: z.string().min(8)
});

const refreshSchema = z.object({
  refresh_token: z.string().min(1)
});

const logoutSchema = z.object({
  refresh_token: z.string().min(1).optional()
});

const bookParamsSchema = z.object({ bookId: z.string().uuid() });
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

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const AUDIO_DIR = path.join(__dirname, '..', '..', 'storage', 'audio');

function getAudioFilePath(chapterId: string, voiceId: string): string {
	const resolved = path.resolve(AUDIO_DIR, `${chapterId}-${voiceId}.mp3`);
	if (!resolved.startsWith(AUDIO_DIR)) {
		throw new Error('Path traversal detected');
	}
	return resolved;
}

function getAudioUrlPath(chapterId: string, voiceId: string): string {
	return `/api/v1/audio/${chapterId}-${voiceId}.mp3`;
}

async function saveAudioFile(filePath: string, buffer: Buffer): Promise<void> {
  await fs.promises.mkdir(path.dirname(filePath), { recursive: true });
  await fs.promises.writeFile(filePath, buffer);
}

export async function registerV1Routes(app: FastifyInstance): Promise<void> {
	app.setErrorHandler((error, request, reply) => {
		if (error instanceof z.ZodError) {
			return reply.code(400).send({
				error: 'ValidationError',
				message: 'Datos de entrada invalidos',
				details: error.issues
			});
		}

		request.log.error({ err: error }, 'Unhandled error');

		if (env.NODE_ENV === 'production') {
			return reply.code(500).send({
				error: 'InternalServerError',
				message: 'Error interno del servidor.'
			});
		}

		return reply.code(500).send({
			error: 'InternalServerError',
			message: error instanceof Error ? error.message : 'Error interno del servidor.'
		});
	});

  app.get('/api/v1/health', async () => ({
    ok: true,
    service: 'lectorsync-backend',
    timestamp: new Date().toISOString()
  }));

  // ────────────────────────────── AUTH ──────────────────────────────

 app.post('/api/v1/auth/register', async (request, reply) => {
 const body = registerSchema.parse(request.body);
 const db = getDb();

 if (!db) {
 return reply.code(503).send(dbUnavailableReply());
 }

 try {
 const existingUser = await db
 .select({ id: users.id, passwordHash: users.passwordHash })
 .from(users)
 .where(eq(users.email, body.email))
 .limit(1);

 if (existingUser[0]) {
 if (!existingUser[0].passwordHash) {
 const passwordHash = await hashPassword(body.password);
 await db
 .update(users)
 .set({ passwordHash })
 .where(eq(users.id, existingUser[0].id));
 return reply.code(201).send({ id: existingUser[0].id, email: body.email, name: body.name });
 }

 return reply.code(409).send({
 error: 'Conflict',
 message: 'Ya existe una cuenta con ese correo.'
 });
 }

 const passwordHash = await hashPassword(body.password);

 const createdUser = await db
 .insert(users)
 .values({ email: body.email, name: body.name, passwordHash })
 .returning({ id: users.id, email: users.email, name: users.name });

 return reply.code(201).send(createdUser[0]);
 } catch (err) {
 if (isDbConnectionError(err)) {
 return reply.code(503).send(dbUnavailableReply());
 }
 throw err;
 }
 });

 app.post('/api/v1/auth/login', async (request, reply) => {
 const body = loginSchema.parse(request.body);
 const db = getDb();

 if (!db) {
 return reply.code(503).send(dbUnavailableReply());
 }

 try {
 const result = await db
 .select({ id: users.id, email: users.email, passwordHash: users.passwordHash })
 .from(users)
 .where(eq(users.email, body.email))
 .limit(1);

 const user = result[0];

 if (!user || !user.passwordHash) {
 return reply.code(401).send({
 error: 'Unauthorized',
 message: 'Credenciales inválidas.'
 });
 }

 const valid = await verifyPassword(body.password, user.passwordHash);
 if (!valid) {
 return reply.code(401).send({
 error: 'Unauthorized',
 message: 'Credenciales inválidas.'
 });
 }

 return reply.send({
 access_token: createAccessToken(app, { id: user.id, email: user.email }),
 refresh_token: createRefreshToken(app, { id: user.id, email: user.email }),
 expires_in: 900
 });
 } catch (err) {
 if (isDbConnectionError(err)) {
 return reply.code(503).send(dbUnavailableReply());
 }
 throw err;
 }
 });

 app.post('/api/v1/auth/refresh', async (request, reply) => {
 const body = refreshSchema.parse(request.body ?? {});

 try {
 if (await isTokenRevoked(body.refresh_token)) {
 return reply.code(401).send({
 error: 'Unauthorized',
 message: 'Token ha sido revocado.'
 });
 }
 } catch {
 // If revocation check fails (DB down), continue to JWT verification
 // so we can still reject wrong token types with proper 401
 }

 let payload: { sub: string; email: string; type: 'access' | 'refresh' };
 try {
 payload = await app.jwt.verify(body.refresh_token);
 } catch {
 return reply.code(401).send({
 error: 'Unauthorized',
 message: 'Refresh token invalido o expirado.'
 });
 }

 if (payload.type !== 'refresh') {
 return reply.code(401).send({
 error: 'Unauthorized',
 message: 'El token enviado no es un refresh token.'
 });
 }

 const db = getDb();
 if (!db) {
 return reply.code(503).send(dbUnavailableReply());
 }

 try {
 await revokeToken(body.refresh_token, payload.sub, REFRESH_TOKEN_TTL, 'refresh');
 } catch (err) {
 if (isDbConnectionError(err)) {
 return reply.code(503).send(dbUnavailableReply());
 }
 throw err;
 }

 try {
 const result = await db
 .select({ id: users.id, email: users.email })
 .from(users)
 .where(eq(users.id, payload.sub))
 .limit(1);

 const user = result[0];
 if (!user) {
 return reply.code(401).send({
 error: 'Unauthorized',
 message: 'Usuario no encontrado.'
 });
 }

 return reply.send({
 access_token: createAccessToken(app, { id: user.id, email: user.email }),
 refresh_token: createRefreshToken(app, { id: user.id, email: user.email }),
 expires_in: 900
 });
 } catch (err) {
 if (isDbConnectionError(err)) {
 return reply.code(503).send(dbUnavailableReply());
 }
 throw err;
 }
 });

 app.post('/api/v1/auth/logout', { preHandler: requireAccessToken }, async (request, reply) => {
 const body = logoutSchema.parse(request.body ?? {});
 const authUser = getAuthenticatedUser(request);
 const db = getDb();

 if (db && authUser) {
 const rawAccessToken = request.headers.authorization?.replace('Bearer ', '') ?? '';
 try {
 if (rawAccessToken) {
 await revokeToken(rawAccessToken, authUser.sub, ACCESS_TOKEN_TTL, 'access');
 }
 if (body.refresh_token) {
 await revokeToken(body.refresh_token, authUser.sub, REFRESH_TOKEN_TTL, 'refresh');
 }
 } catch {
 // If revocation persist fails (DB down), still return success.
 // Tokens will expire naturally (15m access / 30d refresh).
 }
 }

 return reply.code(204).send();
 });

  // ────────────────────────────── LIBRARY ──────────────────────────────

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
 return reply.code(202).send({
 id: crypto.randomUUID(),
 title: parsed.title,
 author: parsed.author,
 status: 'ready',
 file_format: parsed.fileFormat,
 total_chapters: parsed.chapters.length,
 total_words: parsed.totalWords,
 warning: getDatabaseUnavailableReason()
 });
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

 app.delete('/api/v1/books/:bookId', { preHandler: requireAccessToken }, async (request, reply) => {
 const params = bookParamsSchema.parse(request.params);
 const authUser = getAuthenticatedUser(request);
 const db = getDb();

 if (!db) {
 return reply.code(204).send();
 }

 try {
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

 return reply.code(204).send();
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

 await db.insert(chapterAudio).values({
 chapterId: params.chapterId,
 voiceId,
 ttsProvider: providerName,
 audioKey: audioUrlPath ?? '',
 durationMs: result.durationMs,
 wordTimestamps: result.wordTimestamps
 });

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
 const params = request.params as { bookId: string };
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

 await db
 .insert(readingProgress)
 .values({
 userId: authUser.sub,
 bookId: params.bookId,
 chapterId: body.chapter_id,
 wordIndex: body.word_index,
 audioPositionMs: body.audio_position_ms,
 percentage,
 lastReadAt: new Date()
 })
 .onConflictDoUpdate({
 target: [readingProgress.userId, readingProgress.bookId],
 set: {
 chapterId: body.chapter_id,
 wordIndex: body.word_index,
 audioPositionMs: body.audio_position_ms,
 percentage,
 lastReadAt: new Date()
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

	const audioParamsSchema = z.object({
		chapterId: z.string().uuid(),
		voiceId: z.string().min(1).max(100).regex(/^[a-zA-Z0-9_-]+$/)
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
