// Сайт Sonar — статика для GitHub Pages (sonar.folzy.ru). Спека — docs/SITE.md.
import { defineConfig } from 'astro/config'

export default defineConfig({
  site: 'https://sonar.folzy.ru',
  trailingSlash: 'ignore',
  build: { format: 'directory', inlineStylesheets: 'auto' },
  vite: {
    // данные о версиях и ценах лежат выше `site/` (updates/, windows/src/lib/)
    server: { fs: { allow: ['..'] } },
  },
})
