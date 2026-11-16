// «Продолжение трека» как в SoundCloud: нажал трек (например, в поиске) — он играет, а следом в
// очередь сразу встают похожие на него. Похожие догружаются в фоне, трек стартует без ожидания.
// Когда и они кончатся, «Авто похожие» (`general.similar_autoplay`) продолжат волной по последнему.
import { api, type Track } from '../lib/api'
import { player } from './player.svelte'
import { wave } from './my-wave.svelte'

/** Сколько похожих ставить следом. */
const STATION_SIZE = 25

/** Похожие для продолжения: без самого трека, без 👎 и без повторов. */
export function stationTracks(seed: Track, similar: Track[], disliked: (ref: string) => boolean): Track[] {
  const seen = new Set([seed.ref])
  return similar.filter((t) => t.available !== false && !disliked(t.ref) && !seen.has(t.ref) && seen.add(t.ref))
}

export async function playStation(t: Track, context: string | null = 'search') {
  await player.playList([t], 0, context, `Похожее на «${t.title}»`)
  try {
    const similar = await api.similarTracks(t.ref, STATION_SIZE)
    // пока грузилось, включили другое или уже что-то добавили — не мешаем
    if (player.current?.ref !== t.ref || player.tracks.length !== 1) return
    const next = stationTracks(t, similar, (r) => wave.isDisliked(r))
    if (next.length) await player.addToQueue(next, false)
  } catch {
    // нет сети или сервис не ответил — трек доиграет, дальше сработают «Авто похожие»
  }
}
