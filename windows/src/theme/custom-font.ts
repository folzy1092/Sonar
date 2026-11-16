// «Свой» шрифт (Интерфейс → Вид → Шрифт): файл .ttf / .otf / .woff / .woff2 с компьютера хранится
// в IndexedDB (может весить мегабайты — в настройки не кладём) и регистрируется как FontFace.
import { CUSTOM_FAMILY } from './look'

const DB = 'sonar-fonts'
const STORE = 'fonts'
const KEY = 'custom'

function db(): Promise<IDBDatabase> {
  return new Promise((ok, fail) => {
    const req = indexedDB.open(DB, 1)
    req.onupgradeneeded = () => req.result.createObjectStore(STORE)
    req.onsuccess = () => ok(req.result)
    req.onerror = () => fail(req.error)
  })
}

async function tx<T>(mode: IDBTransactionMode, run: (s: IDBObjectStore) => IDBRequest<T>): Promise<T> {
  const d = await db()
  return new Promise((ok, fail) => {
    const req = run(d.transaction(STORE, mode).objectStore(STORE))
    req.onsuccess = () => ok(req.result)
    req.onerror = () => fail(req.error)
  })
}

let face: FontFace | null = null

async function register(data: ArrayBuffer) {
  const next = new FontFace(CUSTOM_FAMILY, data, { weight: '100 900' })
  await next.load()
  if (face) document.fonts.delete(face)
  document.fonts.add(next)
  face = next
}

/** Сохранить и подключить файл шрифта; вернёт имя для настройки (без расширения). */
export async function saveCustomFont(file: File): Promise<string> {
  const data = await file.arrayBuffer()
  await register(data.slice(0))
  await tx('readwrite', (s) => s.put({ name: file.name, data }, KEY))
  return file.name.replace(/\.(ttf|otf|woff2?)$/i, '')
}

/** Подключить сохранённый шрифт при запуске (если выбран «Свой»). */
export async function loadCustomFont(): Promise<boolean> {
  if (face) return true
  try {
    const rec = await tx<{ name: string; data: ArrayBuffer } | undefined>('readonly', (s) => s.get(KEY))
    if (!rec) return false
    await register(rec.data)
    return true
  } catch {
    return false
  }
}
