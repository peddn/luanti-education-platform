// Listens to the backend for changes of a group. The backend keeps the
// request open and sends a short signal: which part of the group
// changed, never the data. The page then loads that part again.

/** @typedef {import('./schema').components['schemas']['ChangeTopic']} ChangeTopic */

/**
 * @typedef {object} ChangeHandlers
 * @property {(topic: ChangeTopic) => void} onChange a part of the group changed
 * @property {() => void} onOpen the connection stands, at first and again after it was lost
 * @property {(closed: boolean) => void} onLost the connection is gone. closed is true if the
 *   backend refused it and nobody tries again: the session is over, or the group is gone
 */

/**
 * Starts listening for changes of a group.
 *
 * @param {string} id identifier of the group
 * @param {ChangeHandlers} handlers
 * @returns {() => void} stops listening
 */
export function watchGroup(id, handlers) {
  // Without the means to listen the page works as before: it shows
  // what it loaded.
  if (typeof EventSource === 'undefined') {
    return () => {}
  }
  const source = new EventSource(`/api/web/v1/groups/${encodeURIComponent(id)}/changes`)
  source.addEventListener('change', (event) => handlers.onChange(/** @type {MessageEvent} */ (event).data))
  source.onopen = () => handlers.onOpen()
  // After a lost connection the browser tries again by itself, but not
  // after an answer that says no.
  source.onerror = () => handlers.onLost(source.readyState === EventSource.CLOSED)
  return () => source.close()
}
