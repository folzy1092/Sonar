import { mount } from 'svelte'
import './app.css'
import App from './App.svelte'
import { player } from './player/player.svelte'
import { router } from './app/router.svelte'

const app = mount(App, {
  target: document.getElementById('app')!,
})

// Заставка из index.html: держим хотя бы 900 мс с начала загрузки страницы, чтобы анимация логотипа успела сыграть.
const splash = document.getElementById('splash')
if (splash) {
  setTimeout(
    () => {
      splash.classList.add('out')
      setTimeout(() => splash.remove(), 400)
    },
    Math.max(0, 900 - performance.now()),
  )
}

// dev: доступ из консоли для отладки вёрстки (window.__sonar.player)
if (import.meta.env.DEV) Object.assign(window, { __sonar: { player, router } })

export default app
