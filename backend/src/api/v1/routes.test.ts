import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import fs from 'node:fs';

import { buildApp } from '../../app.js';
import { signedAudioUrl } from '../../core/audio-url.js';
import { getAudioFilePath, saveAudioFile } from './routes/shared.js';
import { getDb } from '../../db/client.js';
import { users } from '../../db/schema.js';

const uniqueEmail = (prefix: string) =>
 `${prefix}+${Date.now()}-${Math.floor(Math.random() * 1e6)}@lectorsync.test`;

/** DATABASE_URL definida pero Postgres no responde (a diferencia de no tener DB). */
const dbDown = (dbAvailable: boolean) => !dbAvailable && getDb() !== null;

async function getAccessTokenForTest(app: Awaited<ReturnType<typeof buildApp>>, prefix: string) {
 const email = uniqueEmail(prefix);
 const password = 'password1234567890abcdefghijklmnop';

 const registerResponse = await app.inject({
 method: 'POST',
 url: '/api/v1/auth/register',
 payload: { name: 'Test User', email, password }
 });

 if (registerResponse.statusCode === 503) {
 const user = { id: crypto.randomUUID(), email };
 const accessToken = app.jwt.sign(
 { sub: user.id, email: user.email, type: 'access' },
 { expiresIn: '15m' }
 );
 const refreshToken = app.jwt.sign(
 { sub: user.id, email: user.email, type: 'refresh' },
 { expiresIn: '30d' }
 );
 return { accessToken, refreshToken, email, dbAvailable: false };
 }

 if (registerResponse.statusCode === 201) {
 const loginResponse = await app.inject({
 method: 'POST',
 url: '/api/v1/auth/login',
 payload: { email, password }
 });

 if (loginResponse.statusCode === 200) {
 const body = loginResponse.json();
 return { accessToken: body.access_token, refreshToken: body.refresh_token, email, dbAvailable: true };
 }
 }

 throw new Error(`Register/Login failed with status ${registerResponse.statusCode}: ${registerResponse.body}`);
}

describe('API v1 auth and protected routes', () => {
 it('returns health status', async () => {
 const app = await buildApp();

 const response = await app.inject({
 method: 'GET',
 url: '/api/v1/health'
 });

 assert.equal(response.statusCode, 200);
 const body = response.json();
 assert.equal(body.ok, true);

 await app.close();
 });

 it('issues login tokens and allows refresh', async () => {
 const app = await buildApp();
 const { accessToken, refreshToken, dbAvailable } = await getAccessTokenForTest(app, 'auth');

 if (!dbAvailable) {
 assert.equal(typeof accessToken, 'string');
 assert.equal(typeof refreshToken, 'string');

 const refreshResponse = await app.inject({
 method: 'POST',
 url: '/api/v1/auth/refresh',
 payload: { refresh_token: refreshToken }
 });
 assert.equal(refreshResponse.statusCode, 503);

 await app.close();
 return;
 }

 const refreshResponse = await app.inject({
 method: 'POST',
 url: '/api/v1/auth/refresh',
 payload: { refresh_token: refreshToken }
 });

 assert.equal(refreshResponse.statusCode, 200);
 const refreshBody = refreshResponse.json();
 assert.equal(typeof refreshBody.access_token, 'string');
 assert.equal(typeof refreshBody.refresh_token, 'string');

 await app.close();
 });

 it('rejects refresh endpoint when access token is used', async () => {
 const app = await buildApp();
 const { accessToken, dbAvailable } = await getAccessTokenForTest(app, 'token');

 const refreshResponse = await app.inject({
 method: 'POST',
 url: '/api/v1/auth/refresh',
 payload: { refresh_token: accessToken }
 });

 if (!dbAvailable) {
 assert.equal(refreshResponse.statusCode, 401);
 await app.close();
 return;
 }

 assert.equal(refreshResponse.statusCode, 401);

 await app.close();
 });

 it('rejects login with wrong password', async () => {
 const app = await buildApp();
 const { dbAvailable } = await getAccessTokenForTest(app, 'wrongpw');

 if (!dbAvailable) {
 const badLogin = await app.inject({
 method: 'POST',
 url: '/api/v1/auth/login',
 payload: { email: 'no-db@lectorsync.test', password: 'does-not-matter-long-password' }
 });
 assert.equal(badLogin.statusCode, 503);
 await app.close();
 return;
 }

 const email = uniqueEmail('wrongpw2');
 const password = 'password1234567890abcdefghijklmnop';

 await app.inject({
 method: 'POST',
 url: '/api/v1/auth/register',
 payload: { name: 'Test User', email, password }
 });

 const badLogin = await app.inject({
 method: 'POST',
 url: '/api/v1/auth/login',
 payload: { email, password: 'definitely-wrong-password-long' }
 });

 assert.equal(badLogin.statusCode, 401);

 await app.close();
 });

 it('does not let register claim an existing account without password', async () => {
 const app = await buildApp();
 const db = getDb();
 if (!db) {
 await app.close();
 return;
 }

 const email = uniqueEmail('claim');
 try {
 await db.insert(users).values({ email, name: 'Sin password' });
 } catch {
 // DB configurada pero caída: el resto de pruebas ya cubre el 503.
 await app.close();
 return;
 }

 const claim = await app.inject({
 method: 'POST',
 url: '/api/v1/auth/register',
 payload: { name: 'Atacante', email, password: 'attacker-password-long-enough' }
 });
 assert.equal(claim.statusCode, 409);

 const login = await app.inject({
 method: 'POST',
 url: '/api/v1/auth/login',
 payload: { email, password: 'attacker-password-long-enough' }
 });
 assert.equal(login.statusCode, 401);

 await app.close();
 });

 it('rate-limits chapter audio generation per client', async () => {
 const app = await buildApp();
 const token = app.jwt.sign(
 { sub: crypto.randomUUID(), email: 'tts@lectorsync.test', type: 'access' },
 { expiresIn: '15m' }
 );
 const url = `/api/v1/books/${crypto.randomUUID()}/chapters/${crypto.randomUUID()}/audio`;
 const statuses: number[] = [];
 for (let i = 0; i < 11; i++) {
 const res = await app.inject({
 method: 'POST',
 url,
 headers: { authorization: `Bearer ${token}` },
 payload: { voice_id: 'voz-de-prueba' }
 });
 statuses.push(res.statusCode);
 }
 // Los 10 primeros pasan el límite (404/200/503 según haya DB); el 11.º no.
 assert.ok(statuses.slice(0, 10).every((s) => s !== 429), `statuses: ${statuses}`);
 assert.equal(statuses[10], 429);

 await app.close();
 });

 it('ignores X-Forwarded-For from untrusted clients in the login rate limit', async () => {
 const app = await buildApp();
 const statuses: number[] = [];
 for (let i = 0; i < 6; i++) {
 const res = await app.inject({
 method: 'POST',
 url: '/api/v1/auth/login',
 remoteAddress: '203.0.113.9',
 headers: { 'x-forwarded-for': `198.51.100.${i}` },
 payload: { email: 'nadie@lectorsync.test', password: 'una-password-cualquiera' }
 });
 statuses.push(res.statusCode);
 }
 // Cambiar la cabecera en cada intento no da 5 intentos nuevos.
 assert.equal(statuses[5], 429, `statuses: ${statuses}`);
 await app.close();
 });

 it('blocks protected routes without token', async () => {
 const app = await buildApp();

 const response = await app.inject({
 method: 'GET',
 url: '/api/v1/library'
 });

 assert.equal(response.statusCode, 401);

 await app.close();
 });

 it('allows protected routes with valid access token', async () => {
 const app = await buildApp();
 const { accessToken, dbAvailable } = await getAccessTokenForTest(app, 'library');

 const libraryResponse = await app.inject({
 method: 'GET',
 url: '/api/v1/library',
 headers: { authorization: `Bearer ${accessToken}` }
 });

 if (dbDown(dbAvailable)) {
 assert.equal(libraryResponse.statusCode, 503);
 } else {
 // Con DB, la biblioteca del usuario; sin DB configurada, [].
 assert.equal(libraryResponse.statusCode, 200);
 assert.equal(Array.isArray(libraryResponse.json()), true);
 }

 const logoutResponse = await app.inject({
 method: 'POST',
 url: '/api/v1/auth/logout',
 headers: {
 authorization: `Bearer ${accessToken}`,
 'content-type': 'application/json'
 },
 payload: {}
 });

 // Revocación cerrada ante fallos: con la DB configurada pero caída no
 // se puede comprobar el token y la respuesta es 503.
 assert.equal(logoutResponse.statusCode, dbDown(dbAvailable) ? 503 : 204);

 await app.close();
 });

 it('rejects EPUB import without file', async () => {
 const app = await buildApp();
 const { accessToken, dbAvailable } = await getAccessTokenForTest(app, 'epub');

 const importResponse = await app.inject({
 method: 'POST',
 url: '/api/v1/library/import',
 headers: {
 authorization: `Bearer ${accessToken}`,
 'content-type': 'multipart/form-data; boundary=----test'
 },
 payload: '------test--\r\n'
 });

 assert.equal(importResponse.statusCode, dbDown(dbAvailable) ? 503 : 400);

 await app.close();
 });

 it('rejects import of unsupported format (.docx)', async () => {
 const app = await buildApp();
 const { accessToken, dbAvailable } = await getAccessTokenForTest(app, 'docx');

 const boundary = '----testdocx';
 const payload = [
 `--${boundary}`,
 'Content-Disposition: form-data; name="file"; filename="test.docx"',
 'Content-Type: application/vnd.openxmlformats-officedocument.wordprocessingml.document',
 '',
 'fake docx content',
 `--${boundary}--`,
 ''
 ].join('\r\n');

 const importResponse = await app.inject({
 method: 'POST',
 url: '/api/v1/library/import',
 headers: {
 authorization: `Bearer ${accessToken}`,
 'content-type': `multipart/form-data; boundary=${boundary}`
 },
 payload
 });

 if (dbDown(dbAvailable)) {
 assert.equal(importResponse.statusCode, 503);
 await app.close();
 return;
 }
 assert.equal(importResponse.statusCode, 400);
 const body = importResponse.json();
 assert.match(body.message, /formato no soportado/i);

 await app.close();
 });

 it('imports a TXT file successfully', async () => {
 const app = await buildApp();
 const { accessToken, dbAvailable } = await getAccessTokenForTest(app, 'txtimport');

 const txtContent = 'My TXT Book\n\nThis is chapter one content with some words.';
 const boundary = '----testtxt';
 const payload = [
 `--${boundary}`,
 'Content-Disposition: form-data; name="file"; filename="book.txt"',
 'Content-Type: text/plain',
 '',
 txtContent,
 `--${boundary}--`,
 ''
 ].join('\r\n');

 const importResponse = await app.inject({
 method: 'POST',
 url: '/api/v1/library/import',
 headers: {
 authorization: `Bearer ${accessToken}`,
 'content-type': `multipart/form-data; boundary=${boundary}`
 },
 payload
 });

 if (dbAvailable) {
 assert.equal(importResponse.statusCode, 201);
 const body = importResponse.json();
 assert.equal(body.file_format, 'txt');
 assert.ok(body.total_chapters >= 1);
 } else {
 assert.ok(
 importResponse.statusCode === 202 || importResponse.statusCode === 503,
 `Expected 202 or 503, got ${importResponse.statusCode}`
 );
 if (importResponse.statusCode === 202) {
 const body = importResponse.json();
 assert.equal(body.file_format, 'txt');
 }
 }

 await app.close();
 });

 it('returns 404 for audio on non-existent book', async () => {
 const app = await buildApp();
 const { accessToken, dbAvailable } = await getAccessTokenForTest(app, 'audio404');
 const fakeBookId = crypto.randomUUID();
 const fakeChapterId = crypto.randomUUID();

 const audioResponse = await app.inject({
 method: 'POST',
 url: `/api/v1/books/${fakeBookId}/chapters/${fakeChapterId}/audio`,
 headers: { authorization: `Bearer ${accessToken}` },
 payload: { provider: 'mock', voice_id: 'test-voice-1' }
 });

 if (dbAvailable) {
 assert.equal(audioResponse.statusCode, 404);
 } else {
 assert.ok(
 audioResponse.statusCode === 200 || audioResponse.statusCode === 503,
 `Expected 200 or 503, got ${audioResponse.statusCode}`
 );
 }

 await app.close();
 });

 it('serves chapter audio through the signed URL to its owner only', async () => {
 const app = await buildApp();
 const { accessToken, dbAvailable } = await getAccessTokenForTest(app, 'audioown');
 if (!dbAvailable) {
 await app.close();
 return;
 }
 const auth = { authorization: `Bearer ${accessToken}` };

 const boundary = '----audioown';
 const imported = await app.inject({
 method: 'POST',
 url: '/api/v1/library/import',
 headers: { ...auth, 'content-type': `multipart/form-data; boundary=${boundary}` },
 payload: [
 `--${boundary}`,
 'Content-Disposition: form-data; name="file"; filename="libro.txt"',
 'Content-Type: text/plain',
 '',
 'Capítulo uno con unas cuantas palabras para leer en voz alta.',
 `--${boundary}--`,
 ''
 ].join('\r\n')
 });
 assert.equal(imported.statusCode, 201, imported.body);
 const bookId = imported.json().id as string;
 const chapterList = await app.inject({ method: 'GET', url: `/api/v1/books/${bookId}/chapters`, headers: auth });
 const chapterId = chapterList.json()[0].id as string;
 const audioUrl = `/api/v1/books/${bookId}/chapters/${chapterId}/audio`;

 // El proveedor simulado no produce audio: se deja un mp3 en disco y la
 // segunda petición sale de la caché con su URL firmada.
 await app.inject({ method: 'POST', url: audioUrl, headers: auth, payload: { voice_id: 'voz-propia' } });
 const filePath = getAudioFilePath(chapterId, 'voz-propia');
 await saveAudioFile(filePath, Buffer.from('ID3 audio propio'));
 try {
 const cached = await app.inject({ method: 'POST', url: audioUrl, headers: auth, payload: { voice_id: 'voz-propia' } });
 assert.equal(cached.json().source, 'cache');
 const signedUrl = cached.json().audio_url as string;
 assert.match(signedUrl, /^\/api\/v1\/audio\/.+\.mp3\?.*sig=/);

 // Sin cabeceras, como lo pide el reproductor.
 const download = await app.inject({ method: 'GET', url: signedUrl });
 assert.equal(download.statusCode, 200);
 assert.equal(download.headers['content-type'], 'audio/mpeg');
 assert.equal(download.body, 'ID3 audio propio');

 // Borrado el libro, el enlace deja de valer aunque la firma no haya caducado.
 const deleted = await app.inject({ method: 'DELETE', url: `/api/v1/books/${bookId}`, headers: auth });
 assert.equal(deleted.statusCode, 204);
 const afterDelete = await app.inject({ method: 'GET', url: signedUrl });
 assert.equal(afterDelete.statusCode, 404);
 } finally {
 await fs.promises.rm(filePath, { force: true });
 await app.close();
 }
 });

 it('does not serve audio files of chapters the user does not own', async () => {
 const app = await buildApp();
 const chapterId = crypto.randomUUID();
 const voiceId = 'voz-ajena';
 const filePath = getAudioFilePath(chapterId, voiceId);
 await saveAudioFile(filePath, Buffer.from('ID3 audio de otro usuario'));
 try {
 const token = app.jwt.sign(
 { sub: crypto.randomUUID(), email: 'intruso@lectorsync.test', type: 'access' },
 { expiresIn: '15m' }
 );
 const plainUrl = `/api/v1/audio/${chapterId}-${voiceId}.mp3`;

 // Sin firma (aunque lleve un JWT válido): no se sirve.
 const unsigned = await app.inject({
 method: 'GET',
 url: plainUrl,
 headers: { authorization: `Bearer ${token}` }
 });
 assert.equal(unsigned.statusCode, 404);

 // Firma de otro capítulo pegada a este: 403.
 const other = new URL(signedAudioUrl(crypto.randomUUID(), voiceId, crypto.randomUUID()), 'http://x');
 const tampered = await app.inject({ method: 'GET', url: `${plainUrl}${other.search}` });
 assert.equal(tampered.statusCode, 403);

 // Firma válida de un usuario que no es dueño del capítulo: 404 con DB,
 // 503 sin ella. Nunca el archivo.
 const signed = await app.inject({
 method: 'GET',
 url: signedAudioUrl(chapterId, voiceId, crypto.randomUUID())
 });
 assert.ok([404, 503].includes(signed.statusCode), `got ${signed.statusCode}`);
 for (const res of [unsigned, tampered, signed]) {
 assert.ok(!res.body.includes('audio de otro usuario'));
 }
 } finally {
 await fs.promises.rm(filePath, { force: true });
 await app.close();
 }
 });
});
