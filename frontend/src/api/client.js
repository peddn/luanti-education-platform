// The one place that talks to the backend. The types come from
// schema.d.ts, which is generated from api/openapi.json.

/** @typedef {import('./schema').components['schemas']} Schemas */
/** @typedef {Schemas['Health']} Health */
/** @typedef {Schemas['Status']} Status */
/** @typedef {Schemas['Confirmed']} Confirmed */
/** @typedef {Schemas['Me']} Me */
/** @typedef {Schemas['Group']} Group */
/** @typedef {Schemas['GroupChange']} GroupChange */
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
  'forbidden',
  'name_taken',
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
 * @param {object} [options]
 * @param {typeof fetch} [options.fetch]
 * @param {string} [options.base]
 * @param {() => void} [options.onUnauthorized] called when the backend
 *   says that nobody is logged in, although the page thought so
 */
export function createClient(options = {}) {
  const send = options.fetch ?? ((input, init) => globalThis.fetch(input, init))
  const base = options.base ?? ''

  /**
   * @param {string} path
   * @param {unknown} [content] sent as JSON; without it the request is a GET
   * @param {boolean} [quiet] true for a request that only asks whether somebody is logged in
   * @param {'POST' | 'PATCH'} [method] how content is sent
   * @returns {Promise<unknown>}
   */
  async function request(path, content, quiet, method = 'POST') {
    /** @type {RequestInit} */
    const init = { headers: { Accept: 'application/json' } }
    if (content !== undefined) {
      init.method = method
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
      const failure = failureOf(response, body)
      if (failure.code === 'unauthorized' && !quiet) {
        options.onUnauthorized?.()
      }
      throw failure
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
     * Returns the state of the backend with its details. Needs a login.
     *
     * @returns {Promise<Status>}
     */
    async status() {
      return /** @type {Status} */ (await request('/api/web/v1/status'))
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

    /**
     * Asks for a mail with a login link. The answer is the same whether
     * or not the address is known.
     *
     * @param {string} email
     * @returns {Promise<void>}
     */
    async requestLoginLink(email) {
      /** @type {Schemas['LoginLinkRequest']} */
      const body = { email }
      await request('/api/web/v1/login/link', body)
    },

    /**
     * Logs in with the token from a login mail. The backend sets the
     * session cookie.
     *
     * @param {string} token
     * @returns {Promise<Me>}
     */
    async login(token) {
      /** @type {Schemas['LoginRequest']} */
      const body = { token }
      return /** @type {Me} */ (await request('/api/web/v1/login', body))
    },

    /**
     * Returns the groups the teacher may see.
     *
     * @returns {Promise<Group[]>}
     */
    async groups() {
      const answer = /** @type {Schemas['Groups']} */ (await request('/api/web/v1/groups'))
      return answer.groups
    },

    /**
     * @param {string} id
     * @returns {Promise<Group>}
     */
    async group(id) {
      return /** @type {Group} */ (await request(`/api/web/v1/groups/${encodeURIComponent(id)}`))
    },

    /**
     * Renames a group, sets its teachers or both. Only for the school
     * administration.
     *
     * @param {string} id
     * @param {GroupChange} change
     * @returns {Promise<Group>} the group as it is now
     */
    async changeGroup(id, change) {
      const path = `/api/web/v1/groups/${encodeURIComponent(id)}`
      return /** @type {Group} */ (await request(path, change, false, 'PATCH'))
    },

    /**
     * Returns the accounts that can be assigned to groups. Only for the
     * school administration.
     *
     * @returns {Promise<string[]>}
     */
    async teachers() {
      const answer = /** @type {Schemas['TeacherList']} */ (await request('/api/web/v1/teachers'))
      return answer.teachers
    },

    /** @returns {Promise<void>} */
    async logout() {
      await request('/api/web/v1/logout', {})
    },

    /**
     * Returns who is logged in, or null if nobody is.
     *
     * @returns {Promise<Me | null>}
     */
    async me() {
      try {
        return /** @type {Me} */ (await request('/api/web/v1/me', undefined, true))
      } catch (err) {
        if (err instanceof ApiFailure && err.code === 'unauthorized') {
          return null
        }
        throw err
      }
    },
  }
}

/** @typedef {ReturnType<typeof createClient>} Client */

/** @type {(() => void) | null} */
let unauthorizedHandler = null

/**
 * Sets what happens when the backend says that nobody is logged in any
 * more, for example because the session is over.
 *
 * @param {(() => void) | null} handler
 */
export function setUnauthorizedHandler(handler) {
  unauthorizedHandler = handler
}

/** The client the pages use. */
export const api = createClient({ onUnauthorized: () => unauthorizedHandler?.() })
