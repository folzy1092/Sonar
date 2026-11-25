// Вкус по артистам поверх настройки `wave.artist_prefs` (ядро — `artist-prefs-core.ts`). Порцию Sonar Mix
// фильтрует и оценивает Rust по той же настройке; здесь — меню трека, страница «Вкус» и автоплей похожих.
// «Никогда» сразу убирает из «Далее» ещё не игравшие треки этого артиста, если их поставили волна или
// автоплей; свои плейлисты и ручную очередь не трогает — ручное главнее.
import { settings } from './settings.svelte'
import { toast } from './toast.svelte'
import { t } from './i18n.svelte'
import type { Track } from './api'
import { levelFor, levelOf, trackKeys, withLevel, type ArtistLevel, type ArtistPrefs } from './artist-prefs-core'
import { player } from '../player/player.svelte'
import { WAVE_CONTEXT } from '../player/my-wave.svelte'

const DONE: Record<ArtistLevel, string> = {
  more: 'Будем ставить {name} чаще',
  less: 'Будем ставить {name} реже',
  never: '{name} больше не попадёт в Sonar Mix и похожие',
}

class ArtistTaste {
  get prefs(): ArtistPrefs {
    return settings.get('wave.artist_prefs') ?? {}
  }

  levelOf(name: string) {
    return levelOf(this.prefs, name)
  }

  /** «Никогда» для трека — любой из соавторов. */
  isNever(track: Pick<Track, 'artist' | 'artists'>) {
    return levelFor(this.prefs, track) === 'never'
  }

  /** Поставить уровень; тот же ещё раз или `null` — снять. */
  set(name: string, level: ArtistLevel | null, quiet = false) {
    const was = this.levelOf(name)
    const next = level === was ? null : level
    settings.set('wave.artist_prefs', withLevel(this.prefs, name, next))
    if (!quiet) toast.show(next ? t(DONE[next], { name: name.trim() }) : t('{name} — снова как обычно', { name: name.trim() }))
    if (next === 'never') this.dropQueued(name)
  }

  /** Убрать из «Далее» треки артиста, которые поставили волна или автоплей; играет такой — дальше. */
  private dropQueued(name: string) {
    const key = name.trim().toLowerCase()
    const auto = (tr: Track) => player.context === WAVE_CONTEXT || player.autoRefs.has(tr.ref)
    const hit = (tr: Track) => auto(tr) && trackKeys(tr).includes(key)
    player.dropUpNext(0, hit)
    if (player.current && hit(player.current)) void player.next()
  }
}

export const artistTaste = new ArtistTaste()
