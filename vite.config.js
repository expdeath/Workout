import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Content-Security-Policy for the deployed site (build only — it would
// break Vite's dev-server HMR). The app may only load its own assets and
// talk to the Gemini API; everything else is blocked.
const CSP = [
  "default-src 'none'",
  "script-src 'self'",
  "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com", // inline style attrs + Google Fonts CSS
  "font-src https://fonts.gstatic.com",
  "img-src 'self' data:",
  "connect-src 'self' https://generativelanguage.googleapis.com https://api.github.com", // Gemini + cloud sync
  "worker-src 'self'",   // service worker (offline)
  "manifest-src 'self'", // PWA manifest
  "base-uri 'none'",
  "form-action 'none'",
].join('; ');

// On GitHub Actions, serve from /<repo-name>/ (GitHub Pages project site).
const repo = process.env.GITHUB_REPOSITORY?.split('/')[1];

export default defineConfig({
  base: repo ? `/${repo}/` : '/',
  plugins: [
    react(),
    {
      name: 'inject-csp',
      apply: 'build',
      transformIndexHtml() {
        return [
          {
            tag: 'meta',
            attrs: { 'http-equiv': 'Content-Security-Policy', content: CSP },
            injectTo: 'head-prepend',
          },
        ];
      },
    },
  ],
  server: {
    port: 5173,
    open: true,
  },
  build: {
    outDir: 'dist',
  },
});
