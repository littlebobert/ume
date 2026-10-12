import assert from 'node:assert/strict';
import test from 'node:test';
import worker, { handleRequest } from '../src/index.js';
import { createTestDatabase } from './sqlite-d1.js';

const DEVICE = '0B6F1E52-8C1A-4D7E-9F55-2B9C3A7D1E44';

function createEnvironment(overrides = {}) {
  const { database, d1 } = createTestDatabase();
  return {
    database,
    env: {
      DB: d1,
      HASH_SALT: 'test-salt',
      OPENAI_API_KEY: 'sk-test',
      DECISIONS_MODEL: 'gpt-6-luna',
      DAILY_DEVICE_LIMIT: '3',
      DAILY_IP_LIMIT: '5',
      DAILY_GLOBAL_LIMIT: '100',
      BURST_LIMITER: { limit: async () => ({ success: true }) },
      ...overrides,
    },
  };
}

function decisionBody(overrides = {}) {
  return {
    device: DEVICE,
    input: 'A web form has these unfilled fields.\n- field-0: labeled "Who normally manages your care?"',
    questions: [{
      type: 'choice',
      name: 'field-0',
      instructions: 'Which saved answer should fill form field field-0?',
      choices: [
        { value: 'none', description: 'No saved answer belongs in this field.' },
        { value: 'saved-3-name', description: 'Saved answer labeled "Doctor, Primary care name"' },
      ],
    }],
    ...overrides,
  };
}

function post(body, { ip = '203.0.113.10', headers = {} } = {}) {
  return new Request('https://api.umete.jp/v1/decisions', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'CF-Connecting-IP': ip, ...headers },
    body: typeof body === 'string' ? body : JSON.stringify(body),
  });
}

function upstreamReturning(answers, calls = []) {
  return async (url, init) => {
    calls.push({ url, init, body: JSON.parse(init.body) });
    return Response.json({ answers });
  };
}

const NOW = () => new Date('2026-10-12T15:00:00Z');

test('forwards a valid request with the server key and forced model, and returns sanitized answers', async () => {
  const { env } = createEnvironment();
  const calls = [];
  const fetch = upstreamReturning([
    { type: 'choice', name: 'field-0', choice: 'saved-3-name', confidence: 0.9, probabilities: [{ value: 'saved-3-name', probability: 0.88 }, { value: 'none', probability: 0.12 }], extra: 'dropped' },
    { type: 'choice', name: 'not-asked', choice: 'none', probabilities: [] },
  ], calls);
  const response = await handleRequest(post(decisionBody({ model: 'gpt-expensive' })), env, { fetch, now: NOW });
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('X-Umete-Remaining'), '2');
  const body = await response.json();
  assert.deepEqual(body.answers, [{
    type: 'choice', name: 'field-0', choice: 'saved-3-name', confidence: 0.9,
    probabilities: [{ value: 'saved-3-name', probability: 0.88 }, { value: 'none', probability: 0.12 }],
  }]);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, 'https://api.openai.com/v1/decisions');
  assert.equal(calls[0].init.headers.Authorization, 'Bearer sk-test');
  assert.equal(calls[0].body.model, 'gpt-6-luna', 'the client cannot choose the model');
  assert.equal(calls[0].body.device, undefined, 'the device ID is not forwarded');
});

test('enforces the per-device daily limit and reports when it resets', async () => {
  const { env } = createEnvironment();
  const fetch = upstreamReturning([]);
  for (let attempt = 0; attempt < 3; attempt += 1) {
    assert.equal((await handleRequest(post(decisionBody()), env, { fetch, now: NOW })).status, 200);
  }
  const limited = await handleRequest(post(decisionBody()), env, { fetch, now: NOW });
  assert.equal(limited.status, 429);
  assert.equal((await limited.json()).error, 'daily_limit_reached');
  assert.equal(limited.headers.get('Retry-After'), String(9 * 3600));

  const nextDay = await handleRequest(post(decisionBody()), env, { fetch, now: () => new Date('2026-10-13T00:00:05Z') });
  assert.equal(nextDay.status, 200, 'the quota resets at midnight UTC');
});

test('limits a network that rotates device IDs, and caps total daily usage', async () => {
  const { env } = createEnvironment({ DAILY_DEVICE_LIMIT: '100', DAILY_IP_LIMIT: '2', DAILY_GLOBAL_LIMIT: '3' });
  const fetch = upstreamReturning([]);
  const device = (n) => `0B6F1E52-8C1A-4D7E-9F55-2B9C3A7D1E4${n}`;
  assert.equal((await handleRequest(post(decisionBody({ device: device(1) })), env, { fetch, now: NOW })).status, 200);
  assert.equal((await handleRequest(post(decisionBody({ device: device(2) })), env, { fetch, now: NOW })).status, 200);
  assert.equal((await handleRequest(post(decisionBody({ device: device(3) })), env, { fetch, now: NOW })).status, 429);

  const other = await handleRequest(post(decisionBody({ device: device(4) }), { ip: '198.51.100.7' }), env, { fetch, now: NOW });
  assert.equal(other.status, 200);
  const capped = await handleRequest(post(decisionBody({ device: device(5) }), { ip: '198.51.100.8' }), env, { fetch, now: NOW });
  assert.equal(capped.status, 429);
  assert.equal((await capped.json()).error, 'service_busy');
});

test('stores only hashed counters, never request content or raw identifiers', async () => {
  const { env, database } = createEnvironment();
  await handleRequest(post(decisionBody()), env, { fetch: upstreamReturning([]), now: NOW });
  const rows = database.prepare('SELECT day, subject, count FROM usage ORDER BY subject').all();
  assert.equal(rows.length, 3);
  for (const row of rows) {
    assert.ok(!row.subject.includes(DEVICE) && !row.subject.includes('203.0.113.10'));
    assert.match(row.subject, /^(device:[0-9a-f]{32}|ip:[0-9a-f]{32}|global)$/);
  }
});

test('rejects requests that are not the app\'s decision shape', async () => {
  const { env } = createEnvironment();
  const fetch = async () => { throw new Error('should not reach upstream'); };
  const cases = [
    decisionBody({ device: 'short' }),
    decisionBody({ questions: [] }),
    decisionBody({ questions: [{ type: 'predicate', name: 'q', instructions: 'Is this a form?' }] }),
    decisionBody({ questions: [{ type: 'choice', name: 'q', instructions: 'x', choices: [{ value: 'only', description: 'one choice' }] }] }),
    decisionBody({ questions: [{ type: 'choice', name: 'bad name!', instructions: 'x', choices: [{ value: 'a', description: 'a' }, { value: 'b', description: 'b' }] }] }),
    decisionBody({ input: 'x'.repeat(8_001) }),
    decisionBody({ questions: Array.from({ length: 11 }, (_, i) => ({ type: 'choice', name: `q${i}`, instructions: 'x', choices: [{ value: 'a', description: 'a' }, { value: 'b', description: 'b' }] })) }),
  ];
  for (const body of cases) {
    const response = await handleRequest(post(body), env, { fetch, now: NOW });
    assert.equal(response.status, 400, JSON.stringify(body).slice(0, 120));
  }
  assert.equal((await handleRequest(post('{not json'), env, { fetch, now: NOW })).status, 400);
  const wrongType = await handleRequest(post(decisionBody(), { headers: { 'Content-Type': 'text/plain' } }), env, { fetch, now: NOW });
  assert.equal(wrongType.status, 415, 'browsers cannot reach it without a CORS preflight');
});

test('hides upstream failures and the burst limiter rejects floods', async () => {
  const { env } = createEnvironment();
  const failing = async () => new Response(JSON.stringify({ error: { message: 'echo of your input' } }), { status: 500 });
  const response = await handleRequest(post(decisionBody()), env, { fetch: failing, now: NOW });
  assert.equal(response.status, 502);
  assert.ok(!(await response.text()).includes('echo of your input'));

  const burst = createEnvironment({ BURST_LIMITER: { limit: async () => ({ success: false }) } });
  const limited = await handleRequest(post(decisionBody()), burst.env, { fetch: upstreamReturning([]), now: NOW });
  assert.equal(limited.status, 429);
  assert.equal((await limited.json()).error, 'rate_limited');
});

test('health check, unknown routes, and the cleanup cron', async () => {
  const { env, database } = createEnvironment();
  assert.equal((await handleRequest(new Request('https://api.umete.jp/v1/health'), env)).status, 200);
  assert.equal((await handleRequest(new Request('https://api.umete.jp/nope'), env)).status, 404);
  assert.equal((await handleRequest(new Request('https://api.umete.jp/v1/decisions'), env)).status, 405);
  database.prepare("INSERT INTO usage (day, subject, count) VALUES ('2020-01-01', 'global', 5)").run();
  await worker.scheduled({}, env);
  assert.equal(database.prepare('SELECT COUNT(*) AS n FROM usage').get().n, 0);
});

test('calls the global fetch as a plain function, as Workers require', async () => {
  const { env } = createEnvironment();
  const original = globalThis.fetch;
  globalThis.fetch = function strictFetch() {
    // Workers throw "Illegal invocation" unless `this` is the global object or undefined.
    if (this !== undefined && this !== globalThis) throw new TypeError('Illegal invocation');
    return Promise.resolve(Response.json({ answers: [] }));
  };
  try {
    const response = await handleRequest(post(decisionBody()), env, { now: NOW });
    assert.equal(response.status, 200);
  } finally {
    globalThis.fetch = original;
  }
});
