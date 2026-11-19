// Польский словарь (fallback): ключ — русская строка интерфейса (lib/i18n.svelte.ts).
export default {
  'Играет из {to} — в {from} недоступен': 'Gra z {to} – w {from} niedostępny',
  'Играет из {to} — в {from} только отрывок': 'Gra z {to} – w {from} tylko fragment',
  'Играет из {to} — в {from} нужна подписка': 'Gra z {to} – {from} wymaga subskrypcji',
  'Резервный сервис': 'Serwis zapasowy',
  'Трек не играет в своём сервисе — тот же трек из другого': 'Utwór nie gra w swoim serwisie – ten sam utwór z innego',
  'Порядок резервных сервисов': 'Kolejność serwisów zapasowych',
  'Где искать трек сначала — перетащи сервисы': 'Gdzie szukać utworu najpierw – przeciągnij serwisy',
  'Трек недоступен, есть только отрывок или нужна подписка — Sonar найдёт его в другом сервисе (исполнитель, название и длительность совпадают) и скажет, откуда играет.': 'Jeśli utwór jest niedostępny, jest tylko fragment albo potrzebna subskrypcja, Sonar znajdzie go w innym serwisie (ten sam wykonawca, tytuł i długość) i powie, skąd gra.',
  'Где искать трек сначала — перетащи сервисы. Яндекс Музыка и VK Музыка ищутся, только если подключены.': 'Gdzie szukać utworu najpierw – przeciągnij serwisy. Yandex Music i VK Music są przeszukiwane tylko wtedy, gdy są połączone.',
  'Настройки → Аудио': 'Ustawienia → Dźwięk',
  'SoundCloud: доступен только отрывок': 'SoundCloud: dostępny tylko fragment',
  'Яндекс Музыка: доступно только превью': 'Yandex Music: dostępna tylko zapowiedź',
} satisfies Record<string, string>
