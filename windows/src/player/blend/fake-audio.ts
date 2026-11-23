// Игрушечный граф Web Audio для тестов: узлы помнят связи, параметры — последнюю цель хода.
// Звука нет; проверяется топология и куда едут параметры.

export class FakeParam {
  value: number
  target: number
  /** Время, к которому параметр должен прийти в `target`. */
  until = 0
  constructor(v = 0) {
    this.value = v
    this.target = v
  }
  cancelScheduledValues() {
    return this
  }
  setValueAtTime(v: number) {
    this.value = v
    this.target = v
    return this
  }
  linearRampToValueAtTime(v: number, t: number) {
    this.target = v
    this.until = t
    return this
  }
  setTargetAtTime(v: number, t: number) {
    this.target = v
    this.until = t
    return this
  }
}

export class FakeNode {
  readonly out = new Set<FakeNode>()
  constructor(readonly kind: string) {}
  connect<T>(dest: T): T {
    this.out.add(dest as unknown as FakeNode)
    return dest
  }
  disconnect(dest?: FakeNode) {
    if (dest) this.out.delete(dest)
    else this.out.clear()
  }
}

class FakeGain extends FakeNode {
  gain = new FakeParam(1)
  constructor() {
    super('gain')
  }
}

class FakeBiquad extends FakeNode {
  type = 'lowpass'
  frequency = new FakeParam(350)
  Q = new FakeParam(1)
  gain = new FakeParam(0)
  constructor() {
    super('biquad')
  }
}

class FakeDelay extends FakeNode {
  delayTime = new FakeParam(0)
  constructor(readonly max: number) {
    super('delay')
  }
}

export class FakeWorklet extends FakeNode {
  readonly parameters = new Map([['ratio', new FakeParam(1)]])
  constructor(
    _ctx: unknown,
    readonly name: string,
  ) {
    super('worklet')
  }
}

export class FakeContext {
  sampleRate = 48_000
  currentTime = 0
  modules = 0
  audioWorklet = {
    addModule: async () => {
      this.modules++
    },
  }
  createGain() {
    return new FakeGain()
  }
  createBiquadFilter() {
    return new FakeBiquad()
  }
  createDelay(max: number) {
    return new FakeDelay(max)
  }
}

/** Есть ли путь по связям от `from` до `to`, не заходя в узлы, где `avoid` вернёт true. */
export function reaches(from: FakeNode, to: FakeNode, avoid: (n: FakeNode) => boolean = () => false): boolean {
  const seen = new Set<FakeNode>()
  const stack = [from]
  while (stack.length) {
    const n = stack.pop()!
    if (n === to) return true
    if (seen.has(n) || avoid(n)) continue
    seen.add(n)
    stack.push(...n.out)
  }
  return false
}

/** Подставить игрушечный AudioWorkletNode вместо настоящего (в Node его нет). */
export function installFakeWorklet() {
  ;(globalThis as Record<string, unknown>).AudioWorkletNode = FakeWorklet
}
