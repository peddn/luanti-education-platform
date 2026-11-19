// The one place that talks to the backend. The types come from
// schema.d.ts, which is generated from api/openapi.json.

/** @typedef {import('./schema').components['schemas']} Schemas */
/** @typedef {Schemas['Health']} Health */
/** @typedef {Schemas['Status']} Status */
/** @typedef {Schemas['Confirmed']} Confirmed */
/** @typedef {Schemas['Me']} Me */
/** @typedef {Schemas['Group']} Group */
/** @typedef {Schemas['GroupChange']} GroupChange */
/** @typedef {Schemas['Student']} Student */
/** @typedef {Schemas['AccessSlip']} AccessSlip */
/** @typedef {Schemas['GroupProgress']} GroupProgress */
/** @typedef {Schemas['ProtocolPage']} ProtocolPage */
/** @typedef {Schemas['ProtocolRow']} ProtocolRow */
/** @typedef {Schemas['YearEnd']} YearEnd */
/** @typedef {Schemas['Removal']} Removal */
/** @typedef {Schemas['StaffAccount']} StaffAccount */

/**
 * What narrows a protocol down.
 *
 * @typedef {object} ProtocolFilters
 * @property {string} [account] only entries of this account
 * @property {number} [since] only entries from this time on, in seconds since 1970
 */

/**
 * @param {string} id identifier of the group
 * @param {string} protocol
 * @param {string} tail what follows the name of the protocol
 * @param {Record<string, string | number | undefined>} wanted
 */
function protocolPath(id, protocol, tail, wanted) {
  const query = new URLSearchParams()
  for (const [name, value] of Object.entries(wanted)) {
    if (value !== undefined && value !== '') {
      query.set(name, String(value))
    }
  }
  const text = query.toString()
  const path = `/api/web/v1/groups/${encodeURIComponent(id)}/protocols/${encodeURIComponent(protocol)}${tail}`
  return text === '' ? path : `${path}?${text}`
}

/** @typedef {Schemas['DisplayNameEntry']} DisplayNameEntry */
/** @typedef {Schemas['ModuleProgress']} ModuleProgress */
/** @typedef {Schemas['ProgressChange']} ProgressChange */
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
  'no_names',
  'account_taken',
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

/** @param {string} id identifier of a group */
function studentsPath(id) {
  return `/api/web/v1/groups/${encodeURIComponent(id)}/students`
}

/**
 * @param {unknown} answer
 * @returns {Student[]}
 */
function studentsOf(answer) {
  return /** @type {Schemas['Students']} */ (answer).students
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
   * @param {'POST' | 'PATCH' | 'DELETE'} [method] how the request is sent, if not as GET or with content as POST
   * @returns {Promise<unknown>}
   */
  async function request(path, content, quiet, method) {
    /** @type {RequestInit} */
    const init = { headers: { Accept: 'application/json' } }
    if (method) {
      init.method = method
    }
    if (content !== undefined) {
      init.method = method ?? 'POST'
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
     * Returns the accounts of the students of a group.
     *
     * @param {string} id identifier of the group
     * @returns {Promise<Student[]>}
     */
    async students(id) {
      return studentsOf(await request(studentsPath(id)))
    },

    /**
     * Rolls names for new accounts. Nothing happens in the world yet.
     *
     * @param {string} id
     * @param {number} count
     * @returns {Promise<Student[]>} all accounts of the group
     */
    async draftStudents(id, count) {
      /** @type {Schemas['DraftRequest']} */
      const body = { count }
      return studentsOf(await request(studentsPath(id), body))
    },

    /**
     * Replaces a name that is not an account yet by a newly rolled one.
     *
     * @param {string} id
     * @param {string} account
     * @returns {Promise<Student[]>}
     */
    async rerollStudent(id, account) {
      const path = `${studentsPath(id)}/${encodeURIComponent(account)}/reroll`
      return studentsOf(await request(path, undefined, false, 'POST'))
    },

    /**
     * Removes a name that is not an account in the world.
     *
     * @param {string} id
     * @param {string} account
     * @returns {Promise<Student[]>}
     */
    async removeStudent(id, account) {
      const path = `${studentsPath(id)}/${encodeURIComponent(account)}`
      return studentsOf(await request(path, undefined, false, 'DELETE'))
    },

    /**
     * Has the world create an account for every draft. The passwords in
     * the answer are shown once; the backend does not keep them.
     *
     * @param {string} id
     * @returns {Promise<AccessSlip[]>}
     */
    async createStudents(id) {
      const path = `${studentsPath(id)}/create`
      const answer = /** @type {Schemas['AccessSlips']} */ (await request(path, undefined, false, 'POST'))
      return answer.slips
    },

    /**
     * Orders a new start password for an account that exists in the
     * world. The password in the answer is shown once.
     *
     * @param {string} id
     * @param {string} account
     * @returns {Promise<AccessSlip[]>} one slip
     */
    async resetPassword(id, account) {
      const path = `${studentsPath(id)}/${encodeURIComponent(account)}/password`
      const answer = /** @type {Schemas['AccessSlips']} */ (await request(path, undefined, false, 'POST'))
      return answer.slips
    },

    /**
     * Orders the world to take the display name of a student away. The
     * answer shows the list with the order on its way.
     *
     * @param {string} id
     * @param {string} account
     * @returns {Promise<Student[]>}
     */
    async removeDisplayName(id, account) {
      const path = `${studentsPath(id)}/${encodeURIComponent(account)}/display-name`
      return studentsOf(await request(path, undefined, false, 'DELETE'))
    },

    /**
     * Orders the world to delete the account of a student with
     * everything it knows about it. It cannot be undone. The account
     * name is sent once more, so that no request does this by accident.
     *
     * @param {string} id
     * @param {string} account
     * @returns {Promise<Student[]>}
     */
    async orderRemoval(id, account) {
      const path = `${studentsPath(id)}/${encodeURIComponent(account)}/removal`
      return studentsOf(await request(path, { confirm: account }))
    },

    /**
     * Takes back the order to delete an account, as long as the world
     * has not answered.
     *
     * @param {string} id
     * @param {string} account
     * @returns {Promise<Student[]>}
     */
    async takeBackRemoval(id, account) {
      const path = `${studentsPath(id)}/${encodeURIComponent(account)}/removal`
      return studentsOf(await request(path, undefined, false, 'DELETE'))
    },

    /**
     * Returns the accounts of all teachers. For the school
     * administration only, like everything about these accounts.
     *
     * @returns {Promise<StaffAccount[]>}
     */
    async staff() {
      const body = /** @type {Schemas['StaffList']} */ (await request('/api/web/v1/staff'))
      return body.staff
    },

    /**
     * Has every world create the account of a teacher. The password in
     * the answer is shown once.
     *
     * @param {string} name the account name the school administration chose
     * @returns {Promise<AccessSlip[]>} one slip
     */
    async createStaff(name) {
      const answer = /** @type {Schemas['AccessSlips']} */ (await request('/api/web/v1/staff', { name }))
      return answer.slips
    },

    /**
     * Orders a new start password for a teacher in every world. The
     * password in the answer is shown once.
     *
     * @param {string} account
     * @returns {Promise<AccessSlip[]>} one slip
     */
    async resetStaffPassword(account) {
      const path = `/api/web/v1/staff/${encodeURIComponent(account)}/password`
      const answer = /** @type {Schemas['AccessSlips']} */ (await request(path, undefined, false, 'POST'))
      return answer.slips
    },

    /**
     * Orders every world to delete the account of a teacher. It cannot
     * be undone.
     *
     * @param {string} account
     * @returns {Promise<StaffAccount[]>}
     */
    async removeStaff(account) {
      const path = `/api/web/v1/staff/${encodeURIComponent(account)}/removal`
      const body = /** @type {Schemas['StaffList']} */ (await request(path, { confirm: account }))
      return body.staff
    },

    /**
     * Returns the notes of the accounts that were deleted on request,
     * newest first. For the school administration only.
     *
     * @returns {Promise<Removal[]>}
     */
    async removals() {
      const body = /** @type {Schemas['Removals']} */ (await request('/api/web/v1/removals'))
      return body.removals
    },

    /**
     * Orders the world to lock or unlock choosing a display name for a
     * student.
     *
     * @param {string} id
     * @param {string} account
     * @param {boolean} locked
     * @returns {Promise<Student[]>}
     */
    async lockDisplayName(id, account, locked) {
      const path = `${studentsPath(id)}/${encodeURIComponent(account)}/display-name/lock`
      return studentsOf(await request(path, { locked }))
    },

    /**
     * Returns what happened to the display name of a student, newest
     * first.
     *
     * @param {string} id
     * @param {string} account
     * @returns {Promise<DisplayNameEntry[]>}
     */
    async displayNameHistory(id, account) {
      const path = `${studentsPath(id)}/${encodeURIComponent(account)}/display-names`
      const answer = /** @type {Schemas['DisplayNameHistory']} */ (await request(path))
      return answer.entries
    },

    /**
     * Returns a part of a protocol of the world of a group, newest
     * entries first.
     *
     * @param {string} id
     * @param {string} protocol chat, signs, rewards, desk or names
     * @param {ProtocolFilters & { before?: number, after?: number }} [wanted]
     * @returns {Promise<ProtocolPage>}
     */
    async protocol(id, protocol, wanted = {}) {
      return /** @type {ProtocolPage} */ (await request(protocolPath(id, protocol, '', wanted)))
    },

    /**
     * Returns the address the filtered entries of a protocol can be
     * downloaded from as a CSV file.
     *
     * @param {string} id
     * @param {string} protocol
     * @param {ProtocolFilters} [wanted]
     * @returns {string}
     */
    protocolExportUrl(id, protocol, wanted = {}) {
      return protocolPath(id, protocol, '/export', wanted)
    },

    /**
     * Returns where the students of a group stand, as the world reported
     * it last.
     *
     * @param {string} id
     * @returns {Promise<GroupProgress>}
     */
    async progress(id) {
      const path = `/api/web/v1/groups/${encodeURIComponent(id)}/progress`
      return /** @type {GroupProgress} */ (await request(path))
    },

    /**
     * Orders a new level, a lock or both for a student in a module. The
     * answer shows the old state with the change on its way: the world
     * makes it.
     *
     * @param {string} id
     * @param {string} account
     * @param {string} module id of the module
     * @param {ProgressChange} change
     * @returns {Promise<GroupProgress>}
     */
    async changeProgress(id, account, module, change) {
      const path =
        `/api/web/v1/groups/${encodeURIComponent(id)}/progress/` +
        `${encodeURIComponent(account)}/${encodeURIComponent(module)}`
      return /** @type {GroupProgress} */ (await request(path, change))
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
     * Returns what closing the year would delete, and when it was closed
     * before. For the school administration only.
     *
     * @returns {Promise<YearEnd>}
     */
    async yearEnd() {
      return /** @type {YearEnd} */ (await request('/api/web/v1/year-end'))
    },

    /**
     * Closes the year for the whole school: all protocols are deleted.
     * It cannot be undone. The word is the one the backend asks for, so
     * that no request does this by accident.
     *
     * @returns {Promise<YearEnd>}
     */
    async closeYear() {
      return /** @type {YearEnd} */ (await request('/api/web/v1/year-end', { confirm: 'close-the-year' }))
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
