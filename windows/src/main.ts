import { mount } from 'svelte'
// Шрифты как в Dotify: Inter (интерфейс) и Roboto Flex (заголовок «Моя волна»), из fontsource — в exe
import '@fontsource-variable/inter/opsz.css'
import '@fontsource-variable/roboto-flex/full.css'
// каталог шрифтов Интерфейс → Вид (латиница+кириллица; файл грузится, только когда шрифт показан)
import './theme/fonts.css'
import './app.css'
import App from './App.svelte'
import { player } from './player/player.svelte'
import { router } from './app/router.svelte'
import { lyrics } from './lyrics/lyrics.svelte'
import { settings } from './lib/settings.svelte'
import { catchErrors } from './lib/errors'
import { isTauri } from './lib/tauri'

// ошибки интерфейса — в журнал сессии (после сбоя при следующем запуске предложим отправить лог)
if (isTauri) catchErrors()

const app = mount(App, {
  target: document.getElementById('app')!,
})

// Заставка из index.html: знак крутится пропеллером и, не останавливаясь, растворяется (класс .out).
const splash = document.getElementById('splash')
if (splash) {
  setTimeout(
    () => {
      splash.classList.add('out')
      setTimeout(() => splash.remove(), 700)
    },
    Math.max(0, 420 - performance.now()),
  )
}

// dev: доступ из консоли для отладки вёрстки (window.__sonar.player)
if (import.meta.env.DEV) Object.assign(window, { __sonar: { player, router, lyrics, settings } })

export default app
