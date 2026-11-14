// Формат текста — docs/LYRICS.md §1 (его же отдаёт Rust: src-tauri/src/lyrics/mod.rs).
export interface Word {
  time: number
  duration: number
  text: string
  isBackground: boolean
  hasSpaceAfter: boolean
}

export interface Line {
  time: number
  duration: number
  text: string
  translation?: string
  agent?: string
  isBackground: boolean
  words?: Word[]
}

export interface Lyrics {
  isSynced: boolean
  source: 'lrclib' | 'genius' | 'server'
  lines: Line[]
}
