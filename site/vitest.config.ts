import type { OxcOptions } from 'vite'
import { defineConfig } from 'vitest/config'

// plans.test.ts импортирует windows/src/lib/subscription.ts. Без этого Vite берёт у файла ближайший
// windows/tsconfig.json, а он наследует @tsconfig/svelte — в CI сайта его нет (ставится только site/).
// `tsconfig` нет в типе OxcOptions, но Vite передаёт oxc-опции в трансформацию как есть; перестанет —
// plans.test.ts в CI просто не загрузится.
const OXC_WITHOUT_TSCONFIG = { tsconfig: false } as OxcOptions

export default defineConfig({
  oxc: OXC_WITHOUT_TSCONFIG,
  test: { include: ['src/**/*.test.ts'] },
})
