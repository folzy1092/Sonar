// Резервный сервис (этап 4 NEXT_PROMPT): всплывашка плеера, Плеер → Аудио, ошибки Rust services/fallback.rs.
export default {
  'Играет из {to} — в {from} недоступен': 'Playing from {to} — unavailable on {from}',
  'Играет из {to} — в {from} только отрывок': 'Playing from {to} — only a preview on {from}',
  'Играет из {to} — в {from} нужна подписка': 'Playing from {to} — {from} needs a subscription',
  'Резервный сервис': 'Fallback service',
  'Трек не играет в своём сервисе — тот же трек из другого': 'A track won’t play on its own service — the same track from another one',
  'Порядок резервных сервисов': 'Fallback service order',
  'Где искать трек сначала — перетащи сервисы': 'Where to look for the track first — drag the services',
  'Трек недоступен, есть только отрывок или нужна подписка — Sonar найдёт его в другом сервисе (исполнитель, название и длительность совпадают) и скажет, откуда играет.':
    'If a track is unavailable, only a preview, or needs a subscription, Sonar finds it on another service (same artist, title and length) and tells you where it’s playing from.',
  'Где искать трек сначала — перетащи сервисы. Яндекс Музыка и VK Музыка ищутся, только если подключены.':
    'Where to look for the track first — drag the services. Yandex Music and VK Music are searched only when connected.',
  'Настройки → Аудио': 'Settings → Audio',
  'SoundCloud: доступен только отрывок': 'SoundCloud: only a preview is available',
  'Яндекс Музыка: доступно только превью': 'Yandex Music: only a preview is available',
} satisfies Record<string, string>
