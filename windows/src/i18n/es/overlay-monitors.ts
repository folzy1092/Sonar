// Испанский словарь (overlay-monitors): ключ — русская строка интерфейса (lib/i18n.svelte.ts).
export default {
  'Монитор {n}': 'Pantalla {n}',
  'монитор::Основной': 'Principal',
  'Гц': 'Hz',
  'Полноэкранный оверлей занимает весь монитор — нажми другой, чтобы перенести': 'La superposición a pantalla completa ocupa toda la pantalla: haz clic en otra para moverla',
  'Нажми монитор и точку — или перетащи плашку, хоть на другой монитор': 'Haz clic en una pantalla y en un punto, o arrastra la placa, incluso a otra pantalla',
  'Выбранный монитор отключён — оверлей пока на основном. Подключишь — вернётся сам': 'La pantalla elegida está desconectada: por ahora la superposición está en la principal. Cuando la conectes, volverá sola',
  'Не удалось узнать мониторы — показан обычный экран': 'No se pudieron leer las pantallas: se muestra una pantalla estándar',
} satisfies Record<string, string>
