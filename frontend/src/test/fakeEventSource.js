import { vi } from 'vitest'

/**
 * Stands in for the browser's EventSource in tests: remembers what was
 * opened and lets a test play the backend.
 */
export class FakeEventSource {
  static CONNECTING = 0
  static OPEN = 1
  static CLOSED = 2
  /** @type {FakeEventSource[]} */
  static opened = []

  /** @param {string} url */
  constructor(url) {
    this.url = url
    this.readyState = FakeEventSource.CONNECTING
    /** @type {Record<string, ((event: { data: string }) => void)[]>} */
    this.listeners = {}
    /** @type {(() => void) | null} */
    this.onopen = null
    /** @type {(() => void) | null} */
    this.onerror = null
    FakeEventSource.opened.push(this)
  }

  /**
   * @param {string} name
   * @param {(event: { data: string }) => void} listener
   */
  addEventListener(name, listener) {
    ;(this.listeners[name] ??= []).push(listener)
  }

  close() {
    this.readyState = FakeEventSource.CLOSED
  }

  /** The connection stands. */
  open() {
    this.readyState = FakeEventSource.OPEN
    this.onopen?.()
  }

  /** @param {string} topic the backend says a part changed */
  change(topic) {
    for (const listener of this.listeners.change ?? []) {
      listener({ data: topic })
    }
  }

  /** @param {boolean} [refused] true if the backend said no and nobody tries again */
  lose(refused = false) {
    this.readyState = refused ? FakeEventSource.CLOSED : FakeEventSource.CONNECTING
    this.onerror?.()
  }
}

/** Puts the stand-in in place. Returns the list of what gets opened. */
export function fakeEventSource() {
  FakeEventSource.opened = []
  vi.stubGlobal('EventSource', FakeEventSource)
  return FakeEventSource.opened
}

/** Waits until signals that came in a row have become one loading. */
export function settled() {
  return new Promise((resolve) => setTimeout(resolve, 350))
}
