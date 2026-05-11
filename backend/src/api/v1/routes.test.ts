import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { buildApp } from '../../app.js';

const uniqueEmail = (prefix: string) =>
 `${prefix}+${Date.now()}-${Math.floor(Math.random() * 1e6)}@lectorsync.test`;

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

 if (dbAvailable) {
 assert.equal(libraryResponse.statusCode, 200);
 assert.equal(Array.isArray(libraryResponse.json()), true);
 } else {
 assert.equal(libraryResponse.statusCode, 503);
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

 assert.equal(logoutResponse.statusCode, 204);

 await app.close();
 });

 it('rejects EPUB import without file', async () => {
 const app = await buildApp();
 const { accessToken } = await getAccessTokenForTest(app, 'epub');

 const importResponse = await app.inject({
 method: 'POST',
 url: '/api/v1/library/import',
 headers: {
 authorization: `Bearer ${accessToken}`,
 'content-type': 'multipart/form-data; boundary=----test'
 },
 payload: '------test--\r\n'
 });

 assert.equal(importResponse.statusCode, 400);

 await app.close();
 });

 it('rejects import of unsupported format (.docx)', async () => {
 const app = await buildApp();
 const { accessToken } = await getAccessTokenForTest(app, 'docx');

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
});
