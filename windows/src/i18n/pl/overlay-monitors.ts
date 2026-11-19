// Польский словарь (overlay-monitors): ключ — русская строка интерфейса (lib/i18n.svelte.ts).
export default {
  'Монитор {n}': 'Monitor {n}',
  'монитор::Основной': 'Główny',
  'Гц': 'Hz',
  'Полноэкранный оверлей занимает весь монитор — нажми другой, чтобы перенести': 'Nakładka pełnoekranowa zajmuje cały monitor – kliknij inny, aby ją przenieść',
  'Нажми монитор и точку — или перетащи плашку, хоть на другой монитор': 'Kliknij monitor i punkt – albo przeciągnij plakietkę, nawet na inny monitor',
  'Выбранный монитор отключён — оверлей пока на основном. Подключишь — вернётся сам': 'Wybrany monitor jest odłączony – nakładka jest na razie na głównym. Gdy go podłączysz, wróci sama',
  'Не удалось узнать мониторы — показан обычный экран': 'Nie udało się odczytać monitorów – pokazano zwykły ekran',
} satisfies Record<string, string>
