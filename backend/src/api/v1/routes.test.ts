import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { buildApp } from '../../app.js';

// Email único por ejecución para no chocar con datos previos
const uniqueEmail = (prefix: string) =>
  `${prefix}+${Date.now()}-${Math.floor(Math.random() * 1e6)}@lectorsync.test`;

async function registerAndLogin(app: Awaited<ReturnType<typeof buildApp>>, prefix: string) {
  const email = uniqueEmail(prefix);
  const password = 'password123';

  await app.inject({
    method: 'POST',
    url: '/api/v1/auth/register',
    payload: { name: 'Test User', email, password }
  });

  const loginResponse = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/login',
    payload: { email, password }
  });

  return { email, password, loginResponse };
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

    const { loginResponse } = await registerAndLogin(app, 'auth');

    assert.equal(loginResponse.statusCode, 200);
    const loginBody = loginResponse.json();
    assert.equal(typeof loginBody.access_token, 'string');
    assert.equal(typeof loginBody.refresh_token, 'string');

    const refreshResponse = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/refresh',
      payload: { refresh_token: loginBody.refresh_token }
    });

    assert.equal(refreshResponse.statusCode, 200);
    const refreshBody = refreshResponse.json();
    assert.equal(typeof refreshBody.access_token, 'string');
    assert.equal(typeof refreshBody.refresh_token, 'string');

    await app.close();
  });

  it('rejects refresh endpoint when access token is used', async () => {
    const app = await buildApp();

    const { loginResponse } = await registerAndLogin(app, 'token');
    const loginBody = loginResponse.json();

    const refreshResponse = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/refresh',
      payload: { refresh_token: loginBody.access_token }
    });

    assert.equal(refreshResponse.statusCode, 401);

    await app.close();
  });

  it('rejects login with wrong password', async () => {
    const app = await buildApp();

    const { email } = await registerAndLogin(app, 'wrongpw');

    const badLogin = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/login',
      payload: { email, password: 'definitely-wrong-password' }
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

    const { loginResponse } = await registerAndLogin(app, 'library');
    const { access_token } = loginResponse.json();

    const libraryResponse = await app.inject({
      method: 'GET',
      url: '/api/v1/library',
      headers: { authorization: `Bearer ${access_token}` }
    });

    assert.equal(libraryResponse.statusCode, 200);
    assert.equal(Array.isArray(libraryResponse.json()), true);

    const logoutResponse = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/logout',
      headers: {
        authorization: `Bearer ${access_token}`,
        'content-type': 'application/json'
      },
      payload: {}
    });

    assert.equal(logoutResponse.statusCode, 204);

    await app.close();
  });

  it('rejects EPUB import without file', async () => {
    const app = await buildApp();

    const { loginResponse } = await registerAndLogin(app, 'epub');
    const { access_token } = loginResponse.json();

    const importResponse = await app.inject({
      method: 'POST',
      url: '/api/v1/library/import',
      headers: {
        authorization: `Bearer ${access_token}`,
        'content-type': 'multipart/form-data; boundary=----test'
      },
      payload: '------test--\r\n'
    });

    assert.equal(importResponse.statusCode, 400);

    await app.close();
  });

  it('rejects import of unsupported format (.docx)', async () => {
    const app = await buildApp();

    const { loginResponse } = await registerAndLogin(app, 'docx');
    const { access_token } = loginResponse.json();

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
        authorization: `Bearer ${access_token}`,
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

    const { loginResponse } = await registerAndLogin(app, 'txtimport');
    const { access_token } = loginResponse.json();

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
        authorization: `Bearer ${access_token}`,
        'content-type': `multipart/form-data; boundary=${boundary}`
      },
      payload
    });

    assert.equal(importResponse.statusCode, 201);
    const body = importResponse.json();
    assert.equal(body.file_format, 'txt');
    assert.ok(body.total_chapters >= 1);

    await app.close();
  });

  it('returns 404 for audio on non-existent book', async () => {
    const app = await buildApp();

    const { loginResponse } = await registerAndLogin(app, 'audio404');
    const { access_token } = loginResponse.json();
    const fakeBookId = crypto.randomUUID();
    const fakeChapterId = crypto.randomUUID();

    const audioResponse = await app.inject({
      method: 'POST',
      url: `/api/v1/books/${fakeBookId}/chapters/${fakeChapterId}/audio`,
      headers: { authorization: `Bearer ${access_token}` },
      payload: { provider: 'mock' }
    });

    assert.equal(audioResponse.statusCode, 404);

    await app.close();
  });
});
