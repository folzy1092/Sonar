import { beforeEach, describe, expect, it, vi } from 'vitest'
import { dropUpcoming } from './queue'

// Плеер подменён простым объектом с теми же методами очереди — проверяем логику волны, а не <audio>.
const player = vi.hoisted(() => ({
  context: null as string | null,
  tracks: [] as { ref: string; artist: string }[],
  order: [] as number[],
  pos: 0,
  shuffle: false,
  repeat: 'off',
  onQueueEnd: null as unknown,
  hook: null as null | ((t: unknown, ms: number, skipped: boolean) => void),
  onTrackEnd(cb: (t: unknown, ms: number, skipped: boolean) => void) {
    this.hook = cb
    return () => {}
  },
  async playList(tracks: { ref: string; artist: string }[], index: number, context: string) {
    this.tracks = tracks.slice()
    this.order = tracks.map((_, i) => i)
    this.pos = index
    this.context = context
  },
  async addToQueue(tracks: { ref: string; artist: string }[]) {
    for (const t of tracks) {
      this.tracks.push(t)
      this.order.push(this.tracks.length - 1)
    }
  },
  dropUpNext(keep: number, drop: (t: { ref: string; artist: string }) => boolean) {
    const out = dropUpcoming(this.tracks, this.order, this.pos, drop, keep)
    this.tracks = out.tracks
    this.order = out.order
    return out.dropped
  },
  get current() {
    return this.tracks[this.order[this.pos]] ?? null
  },
}))
const api = vi.hoisted(() => ({
  wavePortion: vi.fn(),
  dislikedRefs: vi.fn(async () => []),
  waveFeedback: vi.fn(async () => {}),
}))

vi.mock('./player.svelte', () => ({ player }))
vi.mock('../lib/api', () => ({ api, errorText: (e: unknown) => String(e) }))
vi.mock('../lib/toast.svelte', () => ({ toast: { show: () => {} } }))
vi.mock('../lib/settings.svelte', () => ({ settings: { get: () => 'own', set: () => {} } }))
vi.mock('../lib/library.svelte', () => ({ library: { isLiked: () => false } }))

const { wave } = await import('./my-wave.svelte')

const tr = (ref: string) =>
  ({ ref, title: ref, artist: `art-${ref}`, artists: [], album: null, duration_ms: 200_000, cover_url: null, url: null, explicit: false, available: true, plays: null, tags: null }) as never
const batch = (prefix: string, n = 10) => Array.from({ length: n }, (_, i) => tr(`${prefix}${i}`))
const refs = () => player.order.map((i) => player.tracks[i].ref)
const flush = async () => {
  for (let i = 0; i < 10; i++) await Promise.resolve()
}
/** Как `player.next()`: сначала хук конца трека, потом позиция уходит дальше. */
function skip(ms = 5_000) {
  const t = player.current as never
  player.hook!(t, ms, true)
  player.pos++
}

beforeEach(async () => {
  api.wavePortion.mockReset()
  api.waveFeedback.mockClear()
  player.context = null
  wave.init()
  vi.useRealTimers()
})

describe('Моя волна: серия ранних пропусков', () => {
  it('два ранних пропуска пересобирают «Далее»: ближайший остаётся, остальное — новая порция', async () => {
    api.wavePortion.mockResolvedValueOnce(batch('a')).mockResolvedValueOnce(batch('b', 6))
    await wave.start()
    skip()
    skip()
    await flush()
    // играет a2, ближайший a3 остался, a4…a9 заменены
    expect(player.current).toMatchObject({ ref: 'a2' })
    expect(refs()).toEqual(['a0', 'a1', 'a2', 'a3', 'b0', 'b1', 'b2', 'b3', 'b4', 'b5'])
    // в новый запрос ушли только реально выданные: убранные вернулись в пул
    const req = api.wavePortion.mock.calls[1][0]
    expect(req.exclude.sort()).toEqual(['a0', 'a1', 'a2', 'a3'])
    expect(req.served_artists).toEqual(['art-a0', 'art-a1', 'art-a2', 'art-a3'])
  })

  it('пропуск, дослушал, пропуск — очередь не трогаем', async () => {
    api.wavePortion.mockResolvedValue(batch('a'))
    await wave.start()
    skip()
    player.hook!(player.current as never, 200_000, false)
    player.pos++
    skip()
    await flush()
    expect(refs()).toHaveLength(10)
    expect(api.wavePortion).toHaveBeenCalledTimes(1)
  })

  it('порция, запрошенная до пересборки, выбрасывается — не дописывается в очередь', async () => {
    let late!: (v: unknown) => void
    api.wavePortion
      .mockResolvedValueOnce(batch('a'))
      .mockImplementationOnce(() => new Promise((r) => (late = r)))
      .mockResolvedValueOnce(batch('c', 3))
    await wave.start()
    const stale = wave.more() // запрос ушёл, ответа ещё нет
    skip()
    skip()
    await flush()
    late(batch('s', 4)) // ответ на старый запрос приходит уже после пересборки
    await stale
    await flush()
    const all = refs()
    expect(all.some((r) => r.startsWith('s'))).toBe(false)
    expect(all.slice(-3)).toEqual(['c0', 'c1', 'c2'])
    expect(api.wavePortion).toHaveBeenCalledTimes(3)
  })

  it('защита: вторая серия в течение минуты очередь не пересобирает', async () => {
    api.wavePortion.mockResolvedValueOnce(batch('a', 14)).mockResolvedValue(batch('b', 2))
    await wave.start()
    skip()
    skip()
    await flush()
    expect(api.wavePortion).toHaveBeenCalledTimes(2)
    const before = refs()
    skip()
    skip()
    await flush()
    expect(api.wavePortion).toHaveBeenCalledTimes(2)
    expect(refs().length).toBeGreaterThanOrEqual(before.length)
  })

  it('свои «В очередь» (не из волны) пересборка не убирает', async () => {
    api.wavePortion.mockResolvedValueOnce(batch('a')).mockResolvedValueOnce(batch('b', 2))
    await wave.start()
    await player.addToQueue([tr('mine')])
    skip()
    skip()
    await flush()
    expect(refs()).toContain('mine')
  })
})
