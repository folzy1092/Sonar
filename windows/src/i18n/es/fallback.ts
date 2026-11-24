// Испанский словарь (fallback): ключ — русская строка интерфейса (lib/i18n.svelte.ts).
export default {
  'Играет из {to} — в {from} недоступен': 'Suena desde {to}: no disponible en {from}',
  'Играет из {to} — в {from} только отрывок': 'Suena desde {to}: en {from} solo hay un fragmento',
  'Играет из {to} — в {from} нужна подписка': 'Suena desde {to}: {from} requiere suscripción',
  'Резервный сервис': 'Servicio de respaldo',
  'Трек не играет в своём сервисе — тот же трек из другого': 'Si una canción no suena en su servicio, la misma canción de otro',
  'Порядок резервных сервисов': 'Orden de los servicios de respaldo',
  'Где искать трек сначала — перетащи сервисы': 'Dónde buscar primero la canción: arrastra los servicios',
  'Трек недоступен, есть только отрывок или нужна подписка — Sonar найдёт его в другом сервисе (исполнитель, название и длительность совпадают) и скажет, откуда играет.': 'Si una canción no está disponible, solo hay un fragmento o requiere suscripción, Sonar la busca en otro servicio (mismo artista, título y duración) y te dice desde dónde suena.',
  'Где искать трек сначала — перетащи сервисы. Яндекс Музыка ищется, только если подключена.':
    'Dónde buscar primero la canción: arrastra los servicios. Yandex Music solo se busca si está conectado.',
  'Настройки → Аудио': 'Ajustes → Audio',
  'SoundCloud: доступен только отрывок': 'SoundCloud: solo hay un fragmento disponible',
  'Яндекс Музыка: доступно только превью': 'Yandex Music: solo hay una vista previa disponible',
} satisfies Record<string, string>
