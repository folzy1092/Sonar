// Немецкий словарь (overlay-monitors): ключ — русская строка интерфейса (lib/i18n.svelte.ts).
export default {
  'Монитор {n}': 'Display {n}',
  'монитор::Основной': 'Haupt',
  'Гц': 'Hz',
  'Полноэкранный оверлей занимает весь монитор — нажми другой, чтобы перенести': 'Das Vollbild-Overlay deckt das ganze Display ab – klick auf ein anderes, um es zu verschieben',
  'Нажми монитор и точку — или перетащи плашку, хоть на другой монитор': 'Klick auf ein Display und einen Punkt – oder zieh die Plakette, auch auf ein anderes Display',
  'Выбранный монитор отключён — оверлей пока на основном. Подключишь — вернётся сам': 'Das gewählte Display ist getrennt – das Overlay ist vorerst auf dem Hauptdisplay. Sobald du es wieder anschließt, kehrt es von selbst zurück',
  'Не удалось узнать мониторы — показан обычный экран': 'Displays konnten nicht erkannt werden – es wird ein Standardbildschirm gezeigt',
} satisfies Record<string, string>
