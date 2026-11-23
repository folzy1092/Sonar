// Тональности для сведения (docs/BLEND.md §7.4): круг Camelot, совместимость двух тональностей и сдвиг тона
// входящего трека, при котором они станут совместимы. Тональность — как в `key.ts`: 0…11 мажор (до = 0),
// 12…23 минор (ля минор = 21), null — не знаем.
//
// Связанная скорость (тон едет вместе со скоростью) сама сдвигает тон на 12·log2(rate) — дробно. Поэтому
// всё считается в полутонах с дробью: «совместимо без сдвига» — если до совместимой тональности не больше
// четверти тона.

/** Сдвиг тона входящего трека на время перехода — не больше, полутонов (решение владельца 8). */
export const MAX_SHIFT = 2
/** До совместимой тональности ближе — сдвиг не нужен, полутонов. */
const IN_TUNE = 0.25
/** Энергичный буст (+2 по кругу) — совместим, но слабее. */
const BOOST_SCORE = 0.6
/** Тональность одного из треков неизвестна. */
export const UNKNOWN_SCORE = 0.5

export interface CamelotKey {
  /** 1…12. */
  num: number
  /** A — минор, B — мажор. */
  minor: boolean
}

const mod = (x: number, m: number) => ((x % m) + m) % m

/** До мажор = 8B, ля минор = 8A; шаг квинтой вверх — +1 по кругу. */
export function camelot(key: number): CamelotKey {
  const minor = key >= 12
  const tonic = mod(key, 12)
  const major = minor ? tonic + 3 : tonic // параллельный по Camelot = относительный мажор
  return { num: mod(major * 7 + 7, 12) + 1, minor }
}

/** «8B», «5A» — для отладки и подсказок. */
export function camelotName(key: number | null): string {
  if (key === null) return '—'
  const c = camelot(key)
  return `${c.num}${c.minor ? 'A' : 'B'}`
}

/** Совместимость B после A, 0…1: та же клетка и ±1 по кругу, мажор ↔ минор с тем же номером — 1; +2 — 0.6. */
export function compat(a: number, b: number): number {
  const ca = camelot(a)
  const cb = camelot(b)
  const step = mod(cb.num - ca.num, 12)
  if (ca.minor !== cb.minor) return step === 0 ? 1 : 0
  if (step === 0 || step === 1 || step === 11) return 1
  return step === 2 ? BOOST_SCORE : 0
}

export interface KeyMatchOpts {
  /** Сдвиг тона A и B от связанной скорости, полутонов (12·log2(rate); 0 — тон сохраняется). */
  driftA?: number
  driftB?: number
  /** `audio.blend_key`: можно сдвигать тон B. */
  allowShift: boolean
}

export interface KeyMatch {
  /** 0…1; тональность одного из треков неизвестна — 0.5. */
  score: number
  /** Сдвиг тона B на время перехода, полутонов (−2…+2). */
  shift: number
  /** Обе тональности известны, а совместить не вышло: долгое наложение — каша. */
  clash: boolean
}

/** Интервал от тоники A до тоники B (0…11) и лад B, при которых B совместим с A. */
function compatibleTargets(a: number): { interval: number; minorB: boolean; score: number }[] {
  const out: { interval: number; minorB: boolean; score: number }[] = []
  const tonicA = mod(a, 12)
  for (const minorB of [false, true]) {
    for (let interval = 0; interval < 12; interval++) {
      const b = mod(tonicA + interval, 12) + (minorB ? 12 : 0)
      const score = compat(a, b)
      if (score > 0) out.push({ interval, minorB, score })
    }
  }
  return out
}

/** Ближайший к 0 представитель x по модулю 12: −6…+6. */
const nearest = (x: number) => mod(x + 6, 12) - 6

/** Насколько B совместим с A и какой сдвиг тона B это даёт (§7.4). */
export function keyMatch(a: number | null, b: number | null, opts: KeyMatchOpts): KeyMatch {
  if (a === null || b === null) return { score: UNKNOWN_SCORE, shift: 0, clash: false }
  const minorB = b >= 12
  // где сейчас тоника B относительно тоники A, с дробью от скоростей
  const actual = mod(b, 12) + (opts.driftB ?? 0) - (mod(a, 12) + (opts.driftA ?? 0))
  let best: KeyMatch = { score: 0, shift: 0, clash: true }
  for (const t of compatibleTargets(a)) {
    if (t.minorB !== minorB) continue
    const need = nearest(t.interval - actual)
    const inTune = Math.abs(need) <= IN_TUNE
    if (!inTune && (!opts.allowShift || Math.abs(need) > MAX_SHIFT)) continue
    const shift = inTune ? 0 : Math.round(need * 100) / 100
    const better = t.score > best.score || (t.score === best.score && Math.abs(shift) < Math.abs(best.shift))
    if (better) best = { score: t.score, shift, clash: false }
  }
  return best
}
