// Английский словарь (export): экспорт плейлистов в файл — меню плейлиста и Любимых (ExportItems.svelte,
// lib/export-save.ts) и ошибки окна сохранения (src-tauri/src/export.rs). Ключ — русская строка.
export default {
  Экспорт: 'Export',
  'для плееров': 'for players',
  'для таблиц': 'for spreadsheets',
  'все поля': 'all fields',
  'Экспорт плейлиста': 'Export playlist',
  'Сохранено: {file}': 'Saved: {file}',
  'Неизвестный формат экспорта': 'Unknown export format',
  'Плейлист слишком большой для экспорта': 'The playlist is too large to export',
  'Окно сохранения закрылось': 'The save window closed',
  'Не удалось сохранить файл': "Couldn't save the file",
} satisfies Record<string, string>
