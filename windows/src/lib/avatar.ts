// Аватар профиля (Аккаунт → Профиль): файл с компьютера → квадрат по центру 256×256, обрезанный в
// круг (прозрачные углы) → WebP data URL. Маленький (≈ 10–30 КБ), поэтому живёт в настройках
// (`profile.avatar`) и синхронизируется вместе с ними; с сервером уйдёт в PATCH /me.
export async function avatarFromFile(file: File, size = 256): Promise<string> {
  const url = URL.createObjectURL(file)
  try {
    const img = await new Promise<HTMLImageElement>((resolve, reject) => {
      const i = new Image()
      i.onload = () => resolve(i)
      i.onerror = () => reject(new Error('не картинка'))
      i.src = url
    })
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
    URL.revokeObjectURL(url)
  }
}

/** @username: латиница, цифры и «_», 3–32 знака (как на сервере, API.md). */
export const USERNAME_RE = /^[a-z0-9_]{3,32}$/
export const cleanUsername = (s: string) => s.trim().replace(/^@/, '').toLowerCase()
