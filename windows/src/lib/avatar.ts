// Картинки профиля (Аккаунт → Профиль): файл с компьютера → WebP data URL. Аватар — квадрат по центру
// 256×256, обрезанный в круг (≈ 10–30 КБ); баннер и фон — прямоугольник «по обложке» (обрезка по центру).
// Маленькие, поэтому живут в настройках (`profile.*`) и синхронизируются вместе с ними; с сервером уйдут
// в PATCH /me.

function loadImage(file: File): Promise<{ img: HTMLImageElement; done: () => void }> {
  const url = URL.createObjectURL(file)
  return new Promise((resolve, reject) => {
    const i = new Image()
    i.onload = () => resolve({ img: i, done: () => URL.revokeObjectURL(url) })
    i.onerror = () => {
      URL.revokeObjectURL(url)
      reject(new Error('не картинка'))
    }
    i.src = url
  })
}

export async function avatarFromFile(file: File, size = 256): Promise<string> {
  const { img, done } = await loadImage(file)
  try {
    const side = Math.min(img.naturalWidth, img.naturalHeight)
    const sx = (img.naturalWidth - side) / 2
    const sy = (img.naturalHeight - side) / 2
    const c = document.createElement('canvas')
    c.width = c.height = size
    const g = c.getContext('2d')!
    g.beginPath()
    g.arc(size / 2, size / 2, size / 2, 0, Math.PI * 2)
    g.clip()
    g.drawImage(img, sx, sy, side, side, 0, 0, size, size)
    return c.toDataURL('image/webp', 0.86)
  } finally {
    done()
  }
}

/** Баннер или фон: обрезка по центру до пропорций width×height и уменьшение до них. */
export async function coverFromFile(file: File, width: number, height: number, quality = 0.8): Promise<string> {
  const { img, done } = await loadImage(file)
  try {
    const scale = Math.max(width / img.naturalWidth, height / img.naturalHeight)
    const sw = width / scale
    const sh = height / scale
    const c = document.createElement('canvas')
    c.width = width
    c.height = height
    c.getContext('2d')!.drawImage(img, (img.naturalWidth - sw) / 2, (img.naturalHeight - sh) / 2, sw, sh, 0, 0, width, height)
    return c.toDataURL('image/webp', quality)
  } finally {
    done()
  }
}

/** @username: латиница, цифры и «_», 3–32 знака (как на сервере, API.md). */
export const USERNAME_RE = /^[a-z0-9_]{3,32}$/
export const cleanUsername = (s: string) => s.trim().replace(/^@/, '').toLowerCase()
