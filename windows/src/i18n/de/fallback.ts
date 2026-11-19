// Немецкий словарь (fallback): ключ — русская строка интерфейса (lib/i18n.svelte.ts).
export default {
  'Играет из {to} — в {from} недоступен': 'Läuft über {to} – bei {from} nicht verfügbar',
  'Играет из {to} — в {from} только отрывок': 'Läuft über {to} – bei {from} nur ein Ausschnitt',
  'Играет из {to} — в {from} нужна подписка': 'Läuft über {to} – {from} braucht ein Abo',
  'Резервный сервис': 'Ersatzdienst',
  'Трек не играет в своём сервисе — тот же трек из другого': 'Wenn ein Titel im eigenen Dienst nicht läuft, derselbe Titel aus einem anderen',
  'Порядок резервных сервисов': 'Reihenfolge der Ersatzdienste',
  'Где искать трек сначала — перетащи сервисы': 'Wo der Titel zuerst gesucht wird – zieh die Dienste',
  'Трек недоступен, есть только отрывок или нужна подписка — Sonar найдёт его в другом сервисе (исполнитель, название и длительность совпадают) и скажет, откуда играет.': 'Ist ein Titel nicht verfügbar, nur als Ausschnitt oder nur mit Abo da, sucht Sonar ihn in einem anderen Dienst (gleicher Künstler, Titel und Länge) und sagt dir, woher er läuft.',
  'Где искать трек сначала — перетащи сервисы. Яндекс Музыка и VK Музыка ищутся, только если подключены.': 'Wo der Titel zuerst gesucht wird – zieh die Dienste. Yandex Music und VK Music werden nur durchsucht, wenn sie verbunden sind.',
  'Настройки → Аудио': 'Einstellungen → Audio',
  'SoundCloud: доступен только отрывок': 'SoundCloud: nur ein Ausschnitt verfügbar',
  'Яндекс Музыка: доступно только превью': 'Yandex Music: nur eine Vorschau verfügbar',
} satisfies Record<string, string>
