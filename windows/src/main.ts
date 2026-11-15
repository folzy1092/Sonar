import { mount } from 'svelte'
// Шрифты как в Dotify: Inter (интерфейс) и Roboto Flex (заголовок «Моя волна»), из fontsource — в exe
import '@fontsource-variable/inter/opsz.css'
import '@fontsource-variable/roboto-flex/full.css'
import './app.css'
import App from './App.svelte'
import { player } from './player/player.svelte'
import { router } from './app/router.svelte'
import { lyrics } from './lyrics/lyrics.svelte'
import { settings } from './lib/settings.svelte'

const app = mount(App, {
  target: document.getElementById('app')!,
})

// Заставка из index.html: S перетекает в круг, круг вращается (~0,9 с), потом мягкий фейдаут фона.
const splash = document.getElementById('splash')
if (splash) {
  setTimeout(
    () => {
      splash.classList.add('out')
      setTimeout(() => splash.remove(), 600)
    },
    Math.max(0, 880 - performance.now()),
  )
}

// dev: доступ из консоли для отладки вёрстки (window.__sonar.player)
if (import.meta.env.DEV) Object.assign(window, { __sonar: { player, router, lyrics, settings } })

export default app
