import './style.css'

import { createPinia } from 'pinia'
import { createApp } from 'vue'

import { setUnauthorizedHandler } from './api/client'
import App from './App.vue'
import { createLepI18n } from './i18n'
import { createLepRouter } from './router'
import { useAuthStore } from './stores/auth'

const pinia = createPinia()
const router = createLepRouter()

// A session that ended while the page was open: back to the login.
setUnauthorizedHandler(() => {
  useAuthStore(pinia).forget()
  router.push({ name: 'login' })
})

createApp(App).use(pinia).use(router).use(createLepI18n()).mount('#app')
