// Обёртки над окном Tauri. В обычном браузере (npm run dev без Tauri) — тихие заглушки.
import { getCurrentWindow } from '@tauri-apps/api/window'

export const isTauri = typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window

const win = () => (isTauri ? getCurrentWindow() : null)

export const minimizeWindow = () => win()?.minimize()
export const toggleMaximizeWindow = () => win()?.toggleMaximize()
export const closeWindow = () => win()?.close()
export const isWindowMaximized = async () => (await win()?.isMaximized()) ?? false

export function onWindowResized(cb: () => void): () => void {
  const w = win()
  if (!w) return () => {}
  const unlisten = w.onResized(cb)
  return () => void unlisten.then((fn) => fn())
}
