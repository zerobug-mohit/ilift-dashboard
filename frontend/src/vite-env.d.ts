/// <reference types="vite/client" />

interface ImportMetaEnv {
  /**
   * Absolute origin of the Plumber API, baked in at build time.
   * Used for the GitHub Pages build, where the page is served from github.io
   * but the backend runs on the viewer's own machine.
   *   VITE_API_BASE=http://127.0.0.1:8000 npm run build
   * Leave unset for local development — Vite proxies /api instead.
   */
  readonly VITE_API_BASE?: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
