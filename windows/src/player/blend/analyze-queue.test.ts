// Очередь анализа (docs/BLEND.md §4.1): два одновременно, «сейчас» раньше вечеринки, без двойного счёта,
// база раньше расчёта, упавшие не долбим, очистка хранилища сбрасывает память.

import { describe, expect, it, vi } from 'vitest'
import { ANALYSIS_VERSION, type BlendAnalysis } from './analysis'
import { AnalyzeQueue, type AnalyzeDeps } from './analyze-queue'

const result = (ref: string, version = ANALYSIS_VERSION) => ({ version, ref }) as BlendAnalysis

/** Расчёт, который завершается вручную: видно, сколько идёт одновременно и в каком порядке. */
function manual(stored: Record<string, BlendAnalysis> = {}) {
  const started: string[] = []
  const finish = new Map<string, { ok: () => void; fail: (msg: string) => void }>()
  const deps: AnalyzeDeps = {
    load: vi.fn(async (refs: string[]) => Object.fromEntries(refs.filter((r) => stored[r]).map((r) => [r, stored[r]]))),
    compute: vi.fn(
      (ref: string) =>
        new Promise<BlendAnalysis>((ok, fail) => {
          started.push(ref)
          finish.set(ref, { ok: () => ok(result(ref)), fail: (msg) => fail(new Error(msg)) })
        }),
    ),
    save: vi.fn(async () => {}),
  }
  return { deps, started, finish }
}

const tick = () => new Promise((r) => setTimeout(r, 0))

describe('очередь анализа', () => {
  it('не больше двух одновременно, «сейчас» раньше вечеринки', async () => {
    const { deps, started, finish } = manual()
    const q = new AnalyzeQueue(deps)
    q.request('p1', 'party')
    q.request('p2', 'party')
    q.request('p3', 'party')
    q.request('n1', 'now')
    await tick()
    expect(started).toEqual(['p1', 'p2'])
    finish.get('p1')?.ok()
    await tick()
    await tick()
    expect(started).toEqual(['p1', 'p2', 'n1'])
    expect(q.stats()).toEqual({ ready: 1, waiting: 1, running: 2, failed: 0, computed: 1 })
  })

  it('тот же трек не считается дважды, вечеринка поднимается до «сейчас»', async () => {
    const { deps, started, finish } = manual()
    const q = new AnalyzeQueue(deps, () => {}, 1)
    q.request('a', 'now')
    q.request('p', 'party')
    q.request('b', 'party')
    const twice = [q.request('b', 'now'), q.request('b', 'party')]
    await tick()
    finish.get('a')?.ok()
    await tick()
    await tick()
    expect(started).toEqual(['a', 'b'])
    finish.get('b')?.ok()
    const [x, y] = await Promise.all(twice)
    expect(x).toBe(y)
    await tick()
    expect(started.filter((r) => r === 'b')).toHaveLength(1)
    expect(started).toEqual(['a', 'b', 'p'])
  })

  it('готовый анализ той же версии — из базы, старой версии — пересчёт', async () => {
    const { deps, finish } = manual({ a: result('a'), old: result('old', ANALYSIS_VERSION - 1) })
    const q = new AnalyzeQueue(deps)
    expect((await q.request('a'))?.ref).toBe('a')
    expect(deps.compute).not.toHaveBeenCalled()
    const pending = q.request('old')
    await tick()
    finish.get('old')?.ok()
    expect((await pending)?.version).toBe(ANALYSIS_VERSION)
    expect(deps.save).toHaveBeenCalledWith(result('old'))
    expect(q.peek('old')).toEqual(result('old'))
  })

  it('упавший трек помним до forgetFailures', async () => {
    const { deps, finish } = manual()
    const changes = vi.fn()
    const q = new AnalyzeQueue(deps, changes)
    const first = q.request('x')
    await tick()
    finish.get('x')?.fail('offline')
    expect(await first).toBeNull()
    expect(q.failure('x')).toBe('offline')
    expect(await q.request('x')).toBeNull()
    expect(deps.compute).toHaveBeenCalledTimes(1)
    q.forgetFailures()
    expect(q.failure('x')).toBeUndefined()
    q.request('x')
    await tick()
    expect(deps.compute).toHaveBeenCalledTimes(2)
    expect(changes).toHaveBeenCalled()
  })

  it('warm поднимает из базы только свежие', async () => {
    const { deps } = manual({ a: result('a'), old: result('old', ANALYSIS_VERSION - 1) })
    const q = new AnalyzeQueue(deps)
    await q.warm(['a', 'old', 'none'])
    expect(q.peek('a')).toBeDefined()
    expect(q.peek('old')).toBeUndefined()
    expect(deps.compute).not.toHaveBeenCalled()
  })

  it('reset: ждущие получают null, идущий не пишет в базу и память', async () => {
    const { deps, finish } = manual()
    const q = new AnalyzeQueue(deps, () => {}, 1)
    const running = q.request('a')
    const waiting = q.request('b')
    await tick()
    q.reset()
    expect(await waiting).toBeNull()
    finish.get('a')?.ok()
    expect(await running).toBeNull()
    expect(q.peek('a')).toBeUndefined()
    expect(deps.save).not.toHaveBeenCalled()
    expect(q.pending('a')).toBe(false)
  })
})
