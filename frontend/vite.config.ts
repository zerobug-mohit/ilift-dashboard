import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  // GitHub Pages serves project sites from /<repo>/, so assets need that prefix.
  // The deploy workflow sets VITE_BASE; local builds stay at the root.
  base: process.env.VITE_BASE ?? '/',
  server: {
    port: 5173,
    // Proxy /api to the Plumber backend so the browser sees a single origin.
    proxy: {
      '/api': {
        target: process.env.ILIFT_API_URL ?? 'http://127.0.0.1:8000',
        changeOrigin: true,
      },
    },
  },
})
