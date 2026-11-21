// Реактивный коллаж для карточек и шапок: сразу — по адресам (`collage`), через миг — по самим
// картинкам (`collageByPixels`), когда отпечатки обложек посчитаны. Устаревший ответ не перетирает новый.
import { collage, type CoverSource } from './covers'
import { collageByPixels } from './cover-hash'
import { proxied } from '../theme/theme.svelte'

export class PixelCollage {
  covers = $state<string[]>([])
  private run = 0

  /** Новый список треков; `initial` — готовые обложки (например, с сервера), пока считаем свои. */
  set(tracks: readonly CoverSource[], initial?: string[]) {
    const id = ++this.run
    this.covers = initial ?? collage(tracks)
    if (!tracks.length) return
    void collageByPixels(tracks, proxied).then((c) => {
      if (id === this.run && c.length) this.covers = c
    })
  }
}
