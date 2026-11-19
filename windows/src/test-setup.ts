// Общая подготовка vitest: язык системы — русский, чтобы умолчание general.language
// (lib/system-lang.ts) не зависело от машины, где идут тесты.
Object.defineProperty(globalThis.navigator, 'languages', { value: ['ru-RU'], configurable: true })
Object.defineProperty(globalThis.navigator, 'language', { value: 'ru-RU', configurable: true })
