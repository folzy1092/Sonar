// Кнопки в превью окна на панели задач (thumbbar.rs): значки — наши MingCute, нарисованные в canvas
// 32×32 белым с лёгкой тенью (на светлой и тёмной панели задач читаются одинаково). Средняя
// кнопка меняется вместе с паузой.
import { invoke } from '@tauri-apps/api/core'
import { isTauri } from './tauri'
import { mingcute } from '../components/mingcute'
import { player } from '../player/player.svelte'

const SIZE = 32

async function draw(name: 'prev' | 'play' | 'pause' | 'next'): Promise<number[]> {
  const body = mingcute[name].fill
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${SIZE}" height="${SIZE}" viewBox="0 0 24 24" style="color:#fff" fill="#fff">${body}</svg>`
  const img = new Image()
  img.src = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`
  await img.decode()
  const c = document.createElement('canvas')
  c.width = c.height = SIZE
  const ctx = c.getContext('2d')!
  ctx.shadowColor = 'rgba(0, 0, 0, 0.45)'
  ctx.shadowBlur = 2
  ctx.shadowOffsetY = 1
  // значок чуть меньше клетки — как у системных кнопок плеера
  ctx.drawImage(img, 3, 3, SIZE - 6, SIZE - 6)
  return Array.from(ctx.getImageData(0, 0, SIZE, SIZE).data)
}

let started = false

export async function startThumbbar() {
  if (!isTauri || started) return
  started = true
  try {
    const icons = await Promise.all((['prev', 'play', 'pause', 'next'] as const).map(draw))
    await invoke('thumbbar_init', { icons, playing: player.playing })
  } catch {
    started = false
    return
  }
  $effect.root(() => {
    $effect(() => {
      const playing = player.playing
      void invoke('thumbbar_state', { playing }).catch(() => {})
    })
  })
}
