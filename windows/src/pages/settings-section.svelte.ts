// Панель настроек (PLATFORMS.md, reference/pc/Screenshot_30..32): слева плоская панель, а окно
// плеера уезжает вправо и поворачивается вглубь на ~15°. Другие экраны могут открыть нужный раздел.
export type SettingsTab = 'account' | 'interface' | 'player' | 'services' | 'integrations' | 'system'

class SettingsPanel {
  open = $state(false)
  tab = $state<SettingsTab>('player')

  show(tab?: SettingsTab) {
    if (tab) this.tab = tab
    this.open = true
  }

  close() {
    this.open = false
  }

  toggle() {
    this.open = !this.open
  }
}

export const settingsPanel = new SettingsPanel()
