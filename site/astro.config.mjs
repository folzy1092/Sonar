// Сайт Sonar — статика для GitHub Pages (try-sonar.ru). Спека — docs/SITE.md.
import { defineConfig } from 'astro/config'
import { INLINE_SCRIPT_HASHES } from './src/lib/inline-scripts.mjs'

export default defineConfig({
  site: 'https://try-sonar.ru',
  trailingSlash: 'ignore',
  build: { format: 'directory', inlineStylesheets: 'auto' },
  // CSP мета-тегом (у GitHub Pages нет своих заголовков): Astro сам считает хэши всех своих
  // скриптов и стилей, чужого кода на страницах нет. Сеть — только статус API и релизы GitHub.
  experimental: {
    csp: {
      directives: [
        "default-src 'self'",
        // атрибуты style="--i: 1" (каскад появления, столбики графиков) — без них ступенек нет;
        // `style-src-attr` нет в списке Astro, поэтому идёт в одной строке с img-src
        "img-src 'self' data:; style-src-attr 'unsafe-inline'",
        // мелкие шрифты Vite встраивает как data:
        "font-src 'self' data:",
        "connect-src 'self' https://sonar-api.folzy.ru https://api.github.com",
        "object-src 'none'",
        "base-uri 'self'",
        "form-action 'self'",
      ],
      // `is:inline` (класс .js, язык 404) Astro не хэширует — хэши из src/lib/inline-scripts.mjs
      scriptDirective: { hashes: INLINE_SCRIPT_HASHES },
    },
  },
  vite: {
    // данные о версиях и ценах лежат выше `site/` (updates/, windows/src/lib/)
    server: { fs: { allow: ['..'] } },
  },
})
