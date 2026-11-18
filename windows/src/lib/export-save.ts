/** Сохранить плейлист в файл: текст собирает `export.ts`, окно «Сохранить как» и запись —
 *  Rust (`export_playlist`), итог — всплывашка. */
import { api, errorText } from './api'
import { exportText, serviceName, type ExportFormat, type ExportTrack } from './export'
import { t } from './i18n.svelte'
import { toast } from './toast.svelte'

export async function saveExport(format: ExportFormat, name: string, tracks: readonly ExportTrack[]): Promise<void> {
  if (!tracks.length) {
    toast.show(t('В плейлисте нет треков'))
    return
  }
  try {
    const contents = exportText(format, name, tracks, (ref) => {
      const service = serviceName(ref)
      return service ? t(service) : ''
    })
    const saved = await api.exportPlaylist(name, format, t('Экспорт плейлиста'), contents)
    if (saved) toast.show(t('Сохранено: {file}', { file: saved }))
  } catch (e) {
    toast.show(errorText(e))
  }
}
