// «Сохранить картинкой» и «Скопировать» у карточки итогов: PNG рисует recap-draw.ts, файл пишет Rust
// (export.rs `save_image`, окно «Сохранить как»), в буфер — Clipboard API WebView2.
import { api, errorText, type Recap } from './api'
import { t } from './i18n.svelte'
import { imageName, type RecapCard, type RecapColors, type RecapRef } from './recap-core'
import { cardPng } from './recap-draw'
import { toast } from './toast.svelte'

/** Blob → base64 без префикса `data:`. */
async function toBase64(blob: Blob): Promise<string> {
  const bytes = new Uint8Array(await blob.arrayBuffer())
  const CHUNK = 0x8000
  let bin = ''
  for (let i = 0; i < bytes.length; i += CHUNK) bin += String.fromCharCode(...bytes.subarray(i, i + CHUNK))
  return btoa(bin)
}

interface Shot {
  card: RecapCard
  index: number
  ref: RecapRef
  data: Recap
  colors: RecapColors
}

export async function saveCard({ card, index, ref, data, colors }: Shot): Promise<void> {
  try {
    const png = await toBase64(await cardPng(card, ref, data, colors))
    const saved = await api.saveImage(imageName(ref, index, card.kind), t('Сохранить картинкой'), png)
    if (saved) toast.show(t('Сохранено: {file}', { file: saved }))
  } catch (e) {
    toast.show(errorText(e))
  }
}

export async function copyCard({ card, ref, data, colors }: Shot): Promise<void> {
  try {
    if (typeof ClipboardItem === 'undefined' || !navigator.clipboard?.write) throw new Error('Буфер обмена недоступен')
    // Blob — обещанием: запись в буфер начинается сразу, пока жест пользователя ещё «свежий»
    await navigator.clipboard.write([new ClipboardItem({ 'image/png': cardPng(card, ref, data, colors) })])
    toast.show(t('Картинка скопирована'))
  } catch (e) {
    toast.show(errorText(e))
  }
}
