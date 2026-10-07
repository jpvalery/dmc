import { defineConfig } from 'astro/config';
import tailwindcss from '@tailwindcss/vite';

// Vercel exposes the production domain at build time; SITE_URL overrides it once there is a
// custom domain. Canonical and Open Graph URLs need it to be absolute.
const site =
  process.env.SITE_URL ??
  (process.env.VERCEL_PROJECT_PRODUCTION_URL
    ? `https://${process.env.VERCEL_PROJECT_PRODUCTION_URL}`
    : 'http://localhost:4321');

export default defineConfig({
  site,
  vite: {
    plugins: [tailwindcss()],
  },
});
