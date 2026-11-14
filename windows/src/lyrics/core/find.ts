// Текущая строка (LYRICS.md §3): от прошлого индекса ±2, иначе бинарный поиск. До первой — −1.
import type { Line } from './types'

function binary(lines: Line[], t: number): number {
  let lo = 0
  let hi = lines.length - 1
  let ans = -1
  while (lo <= hi) {
    const mid = (lo + hi) >> 1
    if (lines[mid].time <= t) {
      ans = mid
      lo = mid + 1
    } else hi = mid - 1
  }
  return ans
}

function isActive(lines: Line[], i: number, t: number): boolean {
  if (i === -1) return t < lines[0].time
  return lines[i].time <= t && (i + 1 >= lines.length || lines[i + 1].time > t)
}

export function findLine(lines: Line[], t: number, prev = -1): number {
  if (!lines.length) return -1
  for (let d = 0; d <= 2; d++) {
    for (const i of d ? [prev + d, prev - d] : [prev]) {
      if (i >= -1 && i < lines.length && isActive(lines, i, t)) return i
    }
  }
  return binary(lines, t)
}
