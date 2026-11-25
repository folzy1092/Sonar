// «Играть из» в меню трека (lib/track-source.ts, app/TrackMenu.svelte, плашка в плеере).
export default {
  'Играть из': 'Play from',
  'как решит Sonar': 'Sonar decides',
  'Ищем трек в других сервисах…': 'Looking for the track on other services…',
  'В других сервисах этот трек не нашёлся': 'This track wasn’t found on other services',
  'Трек снова играет как решит Sonar': 'Sonar picks the source for this track again',
  'Играть из: {service}': 'Play from: {service}',
  'Не получилось сохранить выбор': 'Couldn’t save the choice',
  'Выбрано в меню трека: «Играть из»': 'Chosen in the track menu: “Play from”',
} satisfies Record<string, string>
