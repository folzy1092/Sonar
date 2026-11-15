import { mount } from 'svelte'
// Шрифты как в Dotify: Inter (интерфейс) и Roboto Flex (заголовок «Моя волна»), из fontsource — в exe
import '@fontsource-variable/inter/opsz.css'
import '@fontsource-variable/roboto-flex/full.css'
import './app.css'
import App from './App.svelte'
import { player } from './player/player.svelte'
import { router } from './app/router.svelte'

const app = mount(App, {
  target: document.getElementById('app')!,
})

// Заставка из index.html: знак раскручивается и тает ~1,25 с; фон заставки уходит, пока знак растворяется.
const splash = document.getElementById('splash')
if (splash) {
  setTimeout(
    () => {
      splash.classList.add('out')
      setTimeout(() => splash.remove(), 500)
    },
    Math.max(0, 1000 - performance.now()),
  )
}

// dev: доступ из консоли для отладки вёрстки (window.__sonar.player)
if (import.meta.env.DEV) Object.assign(window, { __sonar: { player, router } })

export default app
