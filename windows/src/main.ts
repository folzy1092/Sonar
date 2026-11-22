import { mount } from 'svelte'
// Шрифты как в Dotify: Inter (интерфейс) и Roboto Flex (заголовок Sonar Mix), из fontsource — в exe
import '@fontsource-variable/inter/opsz.css'
import '@fontsource-variable/roboto-flex/full.css'
// каталог шрифтов Интерфейс → Вид (латиница+кириллица; файл грузится, только когда шрифт показан)
import './theme/fonts.css'
import './app.css'
import './theme/fx.css'
import { newReleases } from './lib/new-releases.svelte'
import App from './App.svelte'
import MiniWindow from './app/MiniWindow.svelte'
import { player } from './player/player.svelte'
import { router } from './app/router.svelte'
import { lyrics } from './lyrics/lyrics.svelte'
import { settings } from './lib/settings.svelte'
import { catchErrors } from './lib/errors'
import { isTauri } from './lib/tauri'

// ошибки интерфейса — в журнал сессии (после сбоя при следующем запуске предложим отправить лог)
if (isTauri) catchErrors()

// Меню WebView2 по правому клику («Назад», «Обновить», «Печать»…) не показываем нигде (просьба
// владельца 2026-11-17). Гасим только системное меню: свои меню Sonar (трек, плейлист, текст) открывают
// их обработчики, они срабатывают как обычно. Клавиша меню и Shift+F10 дают то же событие.
window.addEventListener('contextmenu', (e) => e.preventDefault(), { capture: true })

// мини-окно и оверлей (mini.rs) открывают тот же index.html с #mini / #overlay — там только плашка,
// без плеера и заставки
const plaque = location.hash === '#mini' ? 'mini' : location.hash === '#overlay' ? 'overlay' : null
if (plaque) {
  document.documentElement.classList.add('mini-window')
  document.getElementById('splash')?.remove()
}

// новинки исполнителей — только в главном окне (колокольчик в чёлке)
if (!plaque) newReleases.start()

const app = plaque
  ? mount(MiniWindow, { target: document.getElementById('app')!, props: { kind: plaque } })
  : mount(App, { target: document.getElementById('app')! })

// Заставка из index.html («сонар-поле»): уходит, когда знак встал на место (~1 с от её начала),
// а интерфейс за ней чуть «подъезжает» (только масштаб — без размытия, его
// считал бы главный поток, занятый загрузкой).
const splash = document.getElementById('splash')
if (splash) {
  const shown = performance.now() - ((window as { __splashT0?: number }).__splashT0 ?? 0)
  setTimeout(
    () => {
      splash.classList.add('out')
      if (!matchMedia('(prefers-reduced-motion: reduce)').matches)
        document.getElementById('app')?.animate(
          [
            { scale: '1.02' },
            { scale: '1' },
          ],
          { duration: 820, easing: 'cubic-bezier(0.22, 1, 0.36, 1)' },
        )
      setTimeout(() => splash.remove(), 700)
    },
    Math.max(0, 1000 - shown),
  )
}

// dev: доступ из консоли для отладки вёрстки (window.__sonar.player)
if (import.meta.env.DEV) Object.assign(window, { __sonar: { player, router, lyrics, settings } })

export default app
