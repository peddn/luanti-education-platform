import { mount } from '@vue/test-utils'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { defineComponent, h } from 'vue'

import { fakeEventSource, settled } from '@/test/fakeEventSource'

import { useGroupChanges } from './groupChanges'

/**
 * A page that shows the students of a group and nothing else.
 *
 * @param {() => void} refresh
 * @param {() => boolean} [paused]
 */
function page(refresh, paused) {
  return mount(
    defineComponent({
      setup() {
        const { live } = useGroupChanges('id 7b', ['students'], refresh, paused)
        return () => h('p', live.value ? 'live' : 'offline')
      },
    }),
  )
}

describe('group changes', () => {
  afterEach(() => vi.unstubAllGlobals())

  it('listens to the changes of its group', () => {
    const opened = fakeEventSource()
    page(vi.fn())
    expect(opened.map((source) => source.url)).toEqual(['/api/web/v1/groups/id%207b/changes'])
  })

  it('loads again when a part it shows has changed', async () => {
    const opened = fakeEventSource()
    const refresh = vi.fn()
    page(refresh)
    opened[0].open()
    opened[0].change('progress')
    opened[0].change('group')
    await settled()
    expect(refresh).not.toHaveBeenCalled()

    opened[0].change('students')
    expect(refresh).not.toHaveBeenCalled()
    await settled()
    expect(refresh).toHaveBeenCalledTimes(1)
  })

  it('turns several signals in a row into one loading', async () => {
    const opened = fakeEventSource()
    const refresh = vi.fn()
    page(refresh)
    opened[0].change('students')
    opened[0].change('students')
    opened[0].change('students')
    await settled()
    expect(refresh).toHaveBeenCalledTimes(1)
    opened[0].change('students')
    await settled()
    expect(refresh).toHaveBeenCalledTimes(2)
  })

  it('says when the connection is lost and loads again when it is back', async () => {
    const opened = fakeEventSource()
    const refresh = vi.fn()
    const host = page(refresh)
    opened[0].open()
    await settled()
    // The first connection needs no loading: the page has just loaded.
    expect(refresh).not.toHaveBeenCalled()
    expect(host.text()).toBe('live')

    opened[0].lose()
    await settled()
    expect(host.text()).toBe('offline')
    // The browser tries again by itself. Nothing is loaded meanwhile.
    expect(refresh).not.toHaveBeenCalled()

    opened[0].open()
    await settled()
    expect(host.text()).toBe('live')
    expect(refresh).toHaveBeenCalledTimes(1)
  })

  it('loads once when the backend refuses, so the page shows why', async () => {
    const opened = fakeEventSource()
    const refresh = vi.fn()
    const host = page(refresh)
    opened[0].lose(true)
    await settled()
    expect(host.text()).toBe('offline')
    expect(refresh).toHaveBeenCalledTimes(1)
  })

  it('loads nothing while the page must not change', async () => {
    const opened = fakeEventSource()
    const refresh = vi.fn()
    let paused = true
    page(refresh, () => paused)
    opened[0].change('students')
    await settled()
    expect(refresh).not.toHaveBeenCalled()
    paused = false
    opened[0].change('students')
    await settled()
    expect(refresh).toHaveBeenCalledTimes(1)
  })

  it('stops listening when the page is left', async () => {
    const opened = fakeEventSource()
    const refresh = vi.fn()
    const host = page(refresh)
    opened[0].change('students')
    host.unmount()
    expect(opened[0].readyState).toBe(2)
    await settled()
    expect(refresh).not.toHaveBeenCalled()
  })

  it('leaves the page as it is where the browser cannot listen', () => {
    vi.stubGlobal('EventSource', undefined)
    const host = page(vi.fn())
    expect(host.text()).toBe('live')
  })
})
