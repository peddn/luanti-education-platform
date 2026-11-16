import { fileURLToPath, URL } from 'node:url'

import tailwindcss from '@tailwindcss/vite'
import vue from '@vitejs/plugin-vue'
import { defineConfig } from 'vitest/config'

// Where the development server finds the backend.
const backend = process.env.LEP_DEV_URL || 'http://127.0.0.1:8080'

export default defineConfig({
  plugins: [vue(), tailwindcss()],
  resolve: {
    alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) },
  },
  server: {
    host: '127.0.0.1',
    port: 5173,
    strictPort: true,
    proxy: {
      '/api': {
        target: backend,
        // Without a backend say so, as a proxy in front of it would.
        configure(proxy) {
          proxy.on('error', (_err, _req, res) => {
            if ('writeHead' in res && !res.headersSent) {
              res.writeHead(502).end()
            }
          })
        },
      },
    },
  },
  test: {
    environment: 'jsdom',
    include: ['src/**/*.test.js'],
  },
})
