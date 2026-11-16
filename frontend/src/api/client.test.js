import { describe, expect, it } from 'vitest'

import { ApiFailure, createClient, errorCode } from './client'

/**
 * @param {number} status
 * @param {unknown} body
 */
function answer(status, body) {
  const text = typeof body === 'string' ? body : JSON.stringify(body)
  return /** @type {typeof fetch} */ (async () => new Response(text, { status }))
}

/**
 * @param {Promise<unknown>} promise
 * @returns {Promise<ApiFailure>}
 */
async function failure(promise) {
  try {
    await promise
  } catch (err) {
    if (err instanceof ApiFailure) {
      return err
    }
    throw err
  }
  throw new Error('the request did not fail')
}

describe('api client', () => {
  it('returns the health of the backend', async () => {
    /** @type {string[]} */
    const asked = []
    const client = createClient({
      fetch: async (input) => {
        asked.push(String(input))
        return new Response(JSON.stringify({ status: 'ok', version: '1.2.3', database: true }))
      },
    })
    const health = await client.health()
    expect(health).toEqual({ status: 'ok', version: '1.2.3', database: true })
    expect(asked).toEqual(['/api/health'])
  })

  it('puts the base in front of the path', async () => {
    /** @type {string[]} */
    const asked = []
    const client = createClient({
      base: 'http://lep.example',
      fetch: async (input) => {
        asked.push(String(input))
        return new Response('{}')
      },
    })
    await client.health()
    expect(asked).toEqual(['http://lep.example/api/health'])
  })

  it('confirms an address with a POST', async () => {
    /** @type {[string, RequestInit | undefined][]} */
    const asked = []
    const client = createClient({
      fetch: async (input, init) => {
        asked.push([String(input), init])
        return new Response(JSON.stringify({ account: 'lehrer1' }))
      },
    })
    expect(await client.confirm('lepc_abc')).toEqual({ account: 'lehrer1' })
    const [path, init] = asked[0]
    expect(path).toBe('/api/web/v1/confirm')
    expect(init?.method).toBe('POST')
    expect(init?.body).toBe('{"token":"lepc_abc"}')
    expect(init?.headers).toMatchObject({ 'Content-Type': 'application/json' })
  })

  it('passes on the new codes of the backend', async () => {
    const client = createClient({ fetch: answer(400, { code: 'invalid_token', message: 'x' }) })
    expect((await failure(client.confirm('t'))).code).toBe('invalid_token')
  })

  it('passes on the code of the backend', async () => {
    const client = createClient({ fetch: answer(404, { code: 'not_found', message: 'no such path' }) })
    const err = await failure(client.health())
    expect(err.code).toBe('not_found')
    expect(err.message).toBe('no such path')
    expect(err.status).toBe(404)
  })

  it('does not trust codes it does not know', async () => {
    const client = createClient({ fetch: answer(500, { code: 'made_up', message: 'x' }) })
    expect((await failure(client.health())).code).toBe('unexpected')
  })

  it('reports an error without JSON as unexpected', async () => {
    const client = createClient({ fetch: answer(500, '<html>Oops</html>') })
    const err = await failure(client.health())
    expect(err.code).toBe('unexpected')
    expect(err.status).toBe(500)
  })

  it('reports the answer of a gateway as network', async () => {
    for (const status of [502, 503, 504]) {
      const client = createClient({ fetch: answer(status, '<html>Bad Gateway</html>') })
      const err = await failure(client.health())
      expect(err.code).toBe('network')
      expect(err.status).toBe(status)
    }
  })

  it('reports a good answer without JSON as unexpected', async () => {
    const client = createClient({ fetch: answer(200, '<html>a page</html>') })
    expect((await failure(client.health())).code).toBe('unexpected')
  })

  it('reports a backend out of reach as network', async () => {
    const client = createClient({
      fetch: async () => {
        throw new TypeError('fetch failed')
      },
    })
    const err = await failure(client.health())
    expect(err.code).toBe('network')
    expect(err.status).toBeUndefined()
  })

  it('names every other error unexpected', () => {
    expect(errorCode(new ApiFailure('internal', 'x'))).toBe('internal')
    expect(errorCode(new Error('x'))).toBe('unexpected')
    expect(errorCode(undefined)).toBe('unexpected')
  })
})
