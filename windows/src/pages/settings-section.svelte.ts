// Какой раздел настроек открыт (null — список разделов). Другие экраны могут открыть нужный.
export type SettingsSection = 'services' | null

export const settingsSection = $state<{ value: SettingsSection }>({ value: null })
