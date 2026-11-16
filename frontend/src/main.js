import './style.css'

import { createPinia } from 'pinia'
import { createApp } from 'vue'

import App from './App.vue'
import { createLepI18n } from './i18n'
import { createLepRouter } from './router'

createApp(App).use(createPinia()).use(createLepRouter()).use(createLepI18n()).mount('#app')
