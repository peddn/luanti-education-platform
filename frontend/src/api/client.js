// The one place that talks to the backend. The types come from
// schema.d.ts, which is generated from api/openapi.json.

/** @typedef {import('./schema').components['schemas']} Schemas */
/** @typedef {Schemas['Health']} Health */
/** @typedef {Schemas['Confirmed']} Confirmed */
/** @typedef {Schemas['ErrorCode']} BackendErrorCode */

/**
 * Why a request failed. The codes of the backend, and two the frontend
 * adds: the backend could not be reached, or its answer made no sense.
 *
 * @typedef {BackendErrorCode | 'network' | 'unexpected'} ErrorCode
 */

/** @type {readonly string[]} */
const BACKEND_CODES = [
  'unauthorized',
  'not_found',
  'too_large',
  'invalid_request',
  'invalid_token',
  'address_taken',
  'internal',
]

/** What a proxy answers if it cannot reach the backend. */
const GATEWAY_STATUS = [502, 503, 504]

/** A failed request. Pages show `code`, translated, never `message`. */
export class ApiFailure extends Error {
  /**
   * @param {ErrorCode} code
   * @param {string} message English, for the console
   * @param {number} [status] HTTP status, if there was an answer
   */
  constructor(code, message, status) {
    super(message)
    this.name = 'ApiFailure'
    /** @type {ErrorCode} */
    this.code = code
    /** @type {number | undefined} */
    this.status = status
  }
}

/**
 * @param {unknown} err
 * @returns {ErrorCode}
 */
export function errorCode(err) {
  return err instanceof ApiFailure ? err.code : 'unexpected'
}

/**
 * @param {Response} response
 * @returns {Promise<unknown>}
 */
async function readJson(response) {
  try {
    return await response.json()
  } catch {
    return undefined
  }
}

/**
 * @param {Response} response
 * @param {unknown} body
 * @returns {ApiFailure}
 */
function failureOf(response, body) {
  if (body && typeof body === 'object') {
    const { code, message } = /** @type {Record<string, unknown>} */ (body)
    if (typeof code === 'string' && BACKEND_CODES.includes(code)) {
      return new ApiFailure(
        /** @type {BackendErrorCode} */ (code),
        typeof message === 'string' ? message : code,
        response.status,
      )
    }
  }
  if (GATEWAY_STATUS.includes(response.status)) {
    // Something in front of the backend answered in its place.
    return new ApiFailure('network', `status ${response.status} from a gateway`, response.status)
  }
  return new ApiFailure('unexpected', `status ${response.status} without a known code`, response.status)
}

/**
 * @param {{ fetch?: typeof fetch, base?: string }} [options]
 */
export function createClient(options = {}) {
  const send = options.fetch ?? ((input, init) => globalThis.fetch(input, init))
  const base = options.base ?? ''

  /**
   * @param {string} path
   * @param {unknown} [content] sent as JSON with POST; without it the request is a GET
   * @returns {Promise<unknown>}
   */
  async function request(path, content) {
    /** @type {RequestInit} */
    const init = { headers: { Accept: 'application/json' } }
    if (content !== undefined) {
      init.method = 'POST'
      init.headers = { Accept: 'application/json', 'Content-Type': 'application/json' }
      init.body = JSON.stringify(content)
    }
    /** @type {Response} */
    let response
    try {
      response = await send(base + path, init)
    } catch (err) {
      throw new ApiFailure('network', String(err))
    }
    const body = await readJson(response)
    if (!response.ok) {
      throw failureOf(response, body)
    }
    if (body === undefined) {
      throw new ApiFailure('unexpected', 'the answer is not JSON', response.status)
    }
    return body
  }

  return {
    /** @returns {Promise<Health>} */
    async health() {
      return /** @type {Health} */ (await request('/api/health'))
    },

    /**
     * Confirms an address with the token from a confirmation mail.
     *
     * @param {string} token
     * @returns {Promise<Confirmed>}
     */
    async confirm(token) {
      /** @type {Schemas['ConfirmRequest']} */
      const body = { token }
      return /** @type {Confirmed} */ (await request('/api/web/v1/confirm', body))
    },
  }
}

/** @typedef {ReturnType<typeof createClient>} Client */

/** The client the pages use. */
export const api = createClient()
