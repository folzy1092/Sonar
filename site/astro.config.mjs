// Сайт Sonar — статика для GitHub Pages (try-sonar.ru). Спека — docs/SITE.md.
import { defineConfig } from 'astro/config'
import { INLINE_SCRIPT_HASHES } from './src/lib/inline-scripts.mjs'

export default defineConfig({
  site: 'https://try-sonar.ru',
  trailingSlash: 'ignore',
  build: { format: 'directory', inlineStylesheets: 'auto' },
  // CSP мета-тегом (у GitHub Pages нет своих заголовков): Astro сам считает хэши всех своих
  // скриптов и стилей, чужого кода на страницах нет. Сеть — статус API, релизы GitHub и lrclib (страница трека).
  experimental: {
    csp: {
      directives: [
        "default-src 'self'",
        // картинки: свои, встроенные и обложки сервисов — их показывает страница трека /t (SoundCloud, Яндекс,
        // YouTube / Google, Spotify). Директиву на одну страницу (`Astro.csp.insertDirective`) Astro 5.18 склеивает
        // с ошибкой — дублирует её после каждой, поэтому здесь, на весь сайт.
        // атрибуты style="--i: 1" (каскад появления, столбики графиков) — без них ступенек нет;
        // `style-src-attr` нет в списке Astro, поэтому идёт в одной строке с img-src
        "img-src 'self' data: https://*.sndcdn.com https://avatars.yandex.net https://*.ytimg.com https://*.googleusercontent.com https://i.scdn.co https://*.spotifycdn.com; style-src-attr 'unsafe-inline'",
        // мелкие шрифты Vite встраивает как data:
        "font-src 'self' data:",
        // lrclib — текст на странице трека /t
        "connect-src 'self' https://api.github.com https://lrclib.net",
        // встройки плеера на странице трека /t — только по нажатию «Слушать»
        'frame-src https://www.youtube-nocookie.com https://w.soundcloud.com',
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
