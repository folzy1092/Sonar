// Сторож офлайн-режима (`docs/OFFLINE.md` §5.2): сеть Sonar идёт через Rust (ворота `net.rs`), а картинки в
// офлайне — через локальный `/cover` (`offline.src`). Этот тест ловит обход: новый `fetch`, сокет или `<img>`
// с адресом CDN напрямую. Новое исключение — только с причиной в списке ниже.
import { describe, expect, it } from 'vitest'

const sources = import.meta.glob(['../**/*.{ts,svelte}', '!../**/*.test.ts', '!../i18n/**'], {
  query: '?raw',
  import: 'default',
  eager: true,
}) as Record<string, string>

/** Файлы, которым можно `fetch(`: */
const FETCH_ALLOWED: Record<string, string> = {
  './updater.svelte.ts': 'список изменений и релизы — только в сети, проверено в updater',
  './quick-core.ts': '`fetch` — параметр функции, не сеть',
  '../player/blend/analyze.svelte.ts': 'файл трека целиком — с локального аудио-сервера (blend_source)',
}

/** Файлы, которым можно `x.src = …`: */
const SRC_ALLOWED: Record<string, string> = {
  '../theme/theme.svelte.ts': 'адрес из `proxied` (локальный /cover)',
  './thumbbar.svelte.ts': 'data: URL',
  './avatar.ts': 'blob: из файла пользователя',
  './recap-draw.ts': 'адрес из `proxied`',
  './cover-hash.ts': 'адрес из `proxied`',
  './artist-map/avatars.ts': 'в офлайне не грузит вовсе',
  '../player/player.svelte.ts': 'звук — с локального аудио-сервера',
  '../player/art-field.ts': 'адрес из `proxied` (ArtBackdrop)',
}

/** Номера строк, где встречается выражение (для понятного сообщения). */
function hits(src: string, re: RegExp): number[] {
  return [...src.matchAll(re)].map((m) => src.slice(0, m.index).split('\n').length)
}

function offenders(re: RegExp, allowed: Record<string, string> = {}): string[] {
  return Object.entries(sources)
    .filter(([file]) => !(file in allowed))
    .flatMap(([file, src]) => hits(src, re).map((line) => `${file}:${line}`))
}

describe('офлайн: в сеть мимо Rust не ходим', () => {
  it('fetch — только в разрешённых файлах', () => {
    // вызов функции `fetch(`, но не метод `x.fetch(` и не объявление `private fetch(`
    expect(offenders(/(?<![.\w])(?<!private |async |function )fetch\(/g, FETCH_ALLOWED)).toEqual([])
  })

  it('ни сокетов, ни XHR, ни маяков', () => {
    expect(offenders(/XMLHttpRequest|new WebSocket\b|new EventSource\b|sendBeacon\(/g)).toEqual([])
  })

  it('каждый <img> берёт адрес через offline.src', () => {
    // от `<img` до первого `src=` — его значение должно начинаться с `{offline.src(`
    expect(offenders(/<img\b[\s\S]*?\ssrc=(?!\{offline\.src\()/g)).toEqual([])
  })

  it('картинки из кода (x.src = …) — только в разрешённых файлах', () => {
    expect(offenders(/\.src = /g, SRC_ALLOWED)).toEqual([])
  })

  it('список исключений не протух', () => {
    for (const file of [...Object.keys(FETCH_ALLOWED), ...Object.keys(SRC_ALLOWED)]) expect(sources[file], file).toBeTypeOf('string')
  })
})
