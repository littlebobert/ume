// Umete API: a small proxy that lets the app use OpenAI's Decisions API for
// field mapping without each user bringing an API key.
//
// Privacy: requests carry only sanitized field descriptions (labels, names,
// autocomplete hints), never saved answers or values typed into a form. The
// worker never logs or stores request content. The only state it keeps is a
// per-day request count keyed by a salted hash of the device ID or IP address.

const DECISIONS_URL = 'https://api.openai.com/v1/decisions';
const MAX_BODY_BYTES = 128 * 1024;
const MAX_INPUT_CHARS = 8_000;
const MAX_QUESTIONS = 10;
const MIN_CHOICES = 2;
const MAX_CHOICES = 31;
const MAX_INSTRUCTIONS_CHARS = 600;
const MAX_DESCRIPTION_CHARS = 300;
const IDENTIFIER = /^[A-Za-z0-9_-]{1,64}$/;
const DEVICE_ID = /^[A-Za-z0-9-]{16,64}$/;
const UPSTREAM_TIMEOUT_MS = 20_000;

const JSON_HEADERS = {
  'Cache-Control': 'no-store',
  'Content-Type': 'application/json; charset=utf-8',
  'X-Content-Type-Options': 'nosniff',
};

class HttpError extends Error {
  constructor(status, code, message, headers = {}) {
    super(message);
    this.status = status;
    this.code = code;
    this.headers = headers;
  }
}

function json(data, status = 200, headers = {}) {
  return new Response(JSON.stringify(data), { status, headers: { ...JSON_HEADERS, ...headers } });
}

function limit(env, name, fallback) {
  const value = Number(env[name]);
  return Number.isFinite(value) && value > 0 ? value : fallback;
}

function utcDay(now) {
  return now.toISOString().slice(0, 10);
}

function secondsUntilNextUtcDay(now) {
  const next = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1);
  return Math.max(1, Math.ceil((next - now.getTime()) / 1000));
}

async function hash(salt, value) {
  const bytes = new TextEncoder().encode(`${salt}|${value}`);
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)].slice(0, 16).map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function text(value, field, maximum) {
  if (typeof value !== 'string' || !value.trim()) throw new HttpError(400, 'invalid_request', `${field} must be a non-empty string.`);
  if (value.length > maximum) throw new HttpError(400, 'invalid_request', `${field} is too long.`);
  return value;
}

// Accept only the shape the app sends: choice questions over saved-answer IDs.
// This keeps the endpoint from being useful as a general-purpose model proxy.
export function validateDecisionRequest(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw new HttpError(400, 'invalid_request', 'Expected a JSON object.');
  const device = typeof body.device === 'string' ? body.device : '';
  if (!DEVICE_ID.test(device)) throw new HttpError(400, 'invalid_request', 'device is missing or malformed.');
  const input = text(body.input, 'input', MAX_INPUT_CHARS);
  if (!Array.isArray(body.questions) || body.questions.length === 0 || body.questions.length > MAX_QUESTIONS) {
    throw new HttpError(400, 'invalid_request', `questions must contain 1 to ${MAX_QUESTIONS} entries.`);
  }
  const names = new Set();
  const questions = body.questions.map((question, index) => {
    if (!question || question.type !== 'choice') throw new HttpError(400, 'invalid_request', `questions[${index}] must be a choice question.`);
    if (!IDENTIFIER.test(String(question.name || ''))) throw new HttpError(400, 'invalid_request', `questions[${index}].name is malformed.`);
    if (names.has(question.name)) throw new HttpError(400, 'invalid_request', 'Question names must be unique.');
    names.add(question.name);
    const instructions = text(question.instructions, `questions[${index}].instructions`, MAX_INSTRUCTIONS_CHARS);
    if (!Array.isArray(question.choices) || question.choices.length < MIN_CHOICES || question.choices.length > MAX_CHOICES) {
      throw new HttpError(400, 'invalid_request', `questions[${index}].choices must contain ${MIN_CHOICES} to ${MAX_CHOICES} entries.`);
    }
    const values = new Set();
    const choices = question.choices.map((choice, choiceIndex) => {
      const value = String(choice?.value || '');
      if (!IDENTIFIER.test(value) || values.has(value)) {
        throw new HttpError(400, 'invalid_request', `questions[${index}].choices[${choiceIndex}].value is malformed or repeated.`);
      }
      values.add(value);
      return { value, description: text(choice.description, `questions[${index}].choices[${choiceIndex}].description`, MAX_DESCRIPTION_CHARS) };
    });
    return { type: 'choice', name: question.name, instructions, choices };
  });
  return { device, input, questions };
}

async function increment(db, day, subject) {
  const row = await db.prepare(`
    INSERT INTO usage (day, subject, count) VALUES (?, ?, 1)
    ON CONFLICT (day, subject) DO UPDATE SET count = count + 1
    RETURNING count
  `).bind(day, subject).first();
  return Number(row?.count || 0);
}

async function enforceQuotas(env, request, device, now) {
  const ip = request.headers.get('CF-Connecting-IP') || 'unknown';
  if (env.BURST_LIMITER) {
    const result = await env.BURST_LIMITER.limit({ key: ip });
    if (!result.success) throw new HttpError(429, 'rate_limited', 'Too many requests. Try again in a minute.', { 'Retry-After': '60' });
  }
  if (!env.HASH_SALT) throw new Error('HASH_SALT is not configured.');
  const day = utcDay(now);
  const resetHeaders = { 'Retry-After': String(secondsUntilNextUtcDay(now)) };
  const deviceLimit = limit(env, 'DAILY_DEVICE_LIMIT', 60);

  const deviceCount = await increment(env.DB, day, `device:${await hash(env.HASH_SALT, device)}`);
  if (deviceCount > deviceLimit) {
    throw new HttpError(429, 'daily_limit_reached', "You've used today's free AI matching. It resets at midnight UTC.", resetHeaders);
  }
  const ipCount = await increment(env.DB, day, `ip:${await hash(env.HASH_SALT, ip)}`);
  if (ipCount > limit(env, 'DAILY_IP_LIMIT', 300)) {
    throw new HttpError(429, 'daily_limit_reached', "This network has used today's free AI matching. It resets at midnight UTC.", resetHeaders);
  }
  const globalCount = await increment(env.DB, day, 'global');
  if (globalCount > limit(env, 'DAILY_GLOBAL_LIMIT', 20_000)) {
    throw new HttpError(429, 'service_busy', 'Free AI matching is at capacity for today. Local matching still works.', resetHeaders);
  }
  return { remaining: Math.max(0, deviceLimit - deviceCount), resetHeaders };
}

// Return only the fields the app reads, so upstream additions never leak through.
function sanitizeAnswers(upstream, questionNames) {
  const answers = Array.isArray(upstream?.answers) ? upstream.answers : [];
  return answers
    .filter((answer) => questionNames.has(answer?.name))
    .map((answer) => {
      if (answer.type !== 'choice') return { type: String(answer.type || 'unknown'), name: answer.name };
      return {
        type: 'choice',
        name: answer.name,
        choice: String(answer.choice || ''),
        confidence: typeof answer.confidence === 'number' ? answer.confidence : null,
        probabilities: (Array.isArray(answer.probabilities) ? answer.probabilities : [])
          .filter((entry) => typeof entry?.value === 'string' && typeof entry?.probability === 'number')
          .map((entry) => ({ value: entry.value, probability: entry.probability })),
      };
    });
}

async function handleDecisions(request, env, deps) {
  if (!(request.headers.get('Content-Type') || '').toLowerCase().startsWith('application/json')) {
    throw new HttpError(415, 'invalid_request', 'Content-Type must be application/json.');
  }
  if (Number(request.headers.get('Content-Length') || 0) > MAX_BODY_BYTES) {
    throw new HttpError(413, 'invalid_request', 'Request body is too large.');
  }
  const raw = await request.text();
  if (raw.length > MAX_BODY_BYTES) throw new HttpError(413, 'invalid_request', 'Request body is too large.');
  let body;
  try {
    body = JSON.parse(raw);
  } catch {
    throw new HttpError(400, 'invalid_request', 'The request body must be valid JSON.');
  }
  const { device, input, questions } = validateDecisionRequest(body);
  const { remaining } = await enforceQuotas(env, request, device, deps.now());

  if (!env.OPENAI_API_KEY) throw new Error('OPENAI_API_KEY is not configured.');
  let upstream;
  try {
    upstream = await deps.fetch(DECISIONS_URL, {
      method: 'POST',
      headers: { Authorization: `Bearer ${env.OPENAI_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ model: env.DECISIONS_MODEL || 'gpt-6-luna', input, questions }),
      signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
    });
  } catch (error) {
    // Log the error type only, never request content.
    console.warn(`decisions upstream fetch failed: ${error?.name || 'Error'}: ${error?.message || ''}`.slice(0, 200));
    const timedOut = error?.name === 'TimeoutError' || error?.name === 'AbortError';
    throw new HttpError(504, 'upstream_unavailable', timedOut ? 'The AI service did not respond in time.' : 'The AI service could not be reached.');
  }
  if (!upstream.ok) {
    // Log the status only; upstream error bodies can echo request content.
    console.warn(`decisions upstream status ${upstream.status}`);
    throw new HttpError(502, 'upstream_error', 'The AI service could not answer right now.');
  }
  const answers = sanitizeAnswers(await upstream.json(), new Set(questions.map((question) => question.name)));
  return json({ answers }, 200, { 'X-Umete-Remaining': String(remaining) });
}

export async function handleRequest(request, env, deps = {}) {
  // Workers reject the global fetch when it is called as a method of another
  // object ("Illegal invocation"), so wrap it instead of storing it directly.
  const resolved = { fetch: deps.fetch || ((url, init) => fetch(url, init)), now: deps.now || (() => new Date()) };
  const url = new URL(request.url);
  try {
    if (url.pathname === '/v1/health' && request.method === 'GET') return json({ ok: true });
    if (url.pathname === '/v1/decisions') {
      if (request.method !== 'POST') throw new HttpError(405, 'method_not_allowed', 'Use POST.', { Allow: 'POST' });
      return await handleDecisions(request, env, resolved);
    }
    throw new HttpError(404, 'not_found', 'Not found.');
  } catch (error) {
    if (error instanceof HttpError) {
      return json({ error: error.code, message: error.message }, error.status, error.headers);
    }
    console.error(`umete-api error: ${error?.message || error}`);
    return json({ error: 'internal_error', message: 'Something went wrong.' }, 500);
  }
}

export default {
  fetch(request, env) {
    return handleRequest(request, env);
  },
  async scheduled(_controller, env) {
    const cutoff = utcDay(new Date(Date.now() - 3 * 86_400_000));
    await env.DB.prepare('DELETE FROM usage WHERE day < ?').bind(cutoff).run();
  },
};
