// Серия ранних пропусков в «Моей волне» (docs/WAVE.md, этап 5): два подряд — очередь «Далее» была
// подобрана под вкус, которого сейчас нет, значит пора пересобрать её, а не ждать, пока доиграют
// остальные 8–9 треков. Считает только исходы; саму очередь меняет `my-wave.svelte.ts`.

/** Сколько ранних пропусков подряд запускают пересборку. */
export const SERIES_LEN = 2
/** Не пересобирать чаще: новая порция тоже может не зайти с первого трека. */
export const SERIES_COOLDOWN_MS = 60_000

export class SkipSeries {
  private run = 0
  private lastAt = -Infinity

  /**
   * Учесть исход трека: `r` — оценка (`reward.ts`), `skipped` — пропущен вручную.
   * Ранний пропуск — ручной с оценкой ≤ −1 (ранний или 👎). Любой другой исход серию обрывает,
   * в том числе мягкий минус (пропуск на 25–50 % трека): человек слушал, а не мотал.
   * Вернёт true, когда пора пересобрать очередь: серия набралась и с прошлой пересборки
   * прошло не меньше минуты (пока ждём — серия не обнуляется, следующий ранний пропуск после
   * паузы сработает сразу).
   */
  push(r: number, skipped: boolean, now: number): boolean {
    if (!(skipped && r <= -1)) {
      this.run = 0
      return false
    }
    this.run++
    if (this.run < SERIES_LEN || now - this.lastAt < SERIES_COOLDOWN_MS) return false
    this.run = 0
    this.lastAt = now
    return true
  }

  reset() {
    this.run = 0
    this.lastAt = -Infinity
  }
}
