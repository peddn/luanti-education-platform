import { onMounted, onUnmounted, ref } from 'vue'

import { watchGroup } from '@/api/changes'

/** @typedef {import('@/api/changes').ChangeTopic} ChangeTopic */

// Several signals in a row become one loading.
const QUIET_MS = 300

/**
 * Keeps a page of a group up to date: when the backend says that a part
 * the page shows has changed, the page loads it again.
 *
 * @param {string} id identifier of the group
 * @param {ChangeTopic[]} topics the parts of the group the page shows
 * @param {() => void} refresh loads the data again, without disturbing what the user is doing
 * @param {() => boolean} [paused] true while the page must not change, for example while it
 *   shows passwords that exist only once
 * @returns {{ live: import('vue').Ref<boolean> }} live is false while the connection is lost
 */
export function useGroupChanges(id, topics, refresh, paused = () => false) {
  const live = ref(true)
  /** @type {ReturnType<typeof setTimeout> | undefined} */
  let timer
  /** @type {(() => void) | undefined} */
  let stop

  function soon() {
    if (timer !== undefined) {
      return
    }
    timer = setTimeout(() => {
      timer = undefined
      if (!paused()) {
        refresh()
      }
    }, QUIET_MS)
  }

  onMounted(() => {
    stop = watchGroup(id, {
      onChange(topic) {
        if (topics.includes(topic)) {
          soon()
        }
      },
      onOpen() {
        // Back after a break: signals were missed.
        if (!live.value) {
          live.value = true
          soon()
        }
      },
      onLost(closed) {
        live.value = false
        // The backend said no. Loading shows why: the login page if the
        // session is over, an error if the group is gone.
        if (closed) {
          soon()
        }
      },
    })
  })

  onUnmounted(() => {
    stop?.()
    clearTimeout(timer)
  })

  return { live }
}
