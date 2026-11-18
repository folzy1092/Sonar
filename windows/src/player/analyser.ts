// Спектр плеера для всех, кто его рисует: волна под ползунком (`Wave.svelte`) и поле точек героя
// Главной (`components/SonarField.svelte`). Анализатор один — тот, что плеер создал в своём графе
// Web Audio (`player.analyser`); второй не заводим. Нет анализатора или музыка на паузе — null.
import { player } from './player.svelte'
import { createSpectrumReader } from './spectrum-reader'

export type { Spectrum } from './spectrum-reader'

export const readSpectrum = createSpectrumReader(() => (player.playing ? player.analyser : null))
