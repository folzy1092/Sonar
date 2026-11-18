// Пульт (Система → Пульт, remote/ в Rust): iPhone управляет этим Sonar по Wi-Fi.
// Включён `remote.enabled` — Rust поднимает сервер в локальной сети; команды телефона приходят событием
// `remote-command` и выполняются здесь тем же плеером, что и кнопки окна. Состояние плеера уходит в
// Rust (`remote_state`) при изменениях и раз в 5 с — оттуда всем подключённым телефонам.
import { untrack } from 'svelte'
import { api, errorText, onRemoteChanged, onRemoteCommand, onRemotePaired, type RemoteStatus, type Track } from './api'
import { isTauri } from './tauri'
import { settings } from './settings.svelte'
import { library } from './library.svelte'
import { toast } from './toast.svelte'
import { t } from './i18n.svelte'
import { player } from '../player/player.svelte'
import { wave } from '../player/my-wave.svelte'
import { buildState, likeNeedsToggle, parseCommand, queueIndexNow, shouldSend, type RemoteCommand, type RemoteState } from './remote-core'

/** Как часто сверяем позицию (шлём, только если перемотали или прошло 5 с). */
const TICK_MS = 1000

class Remote {
  status = $state<RemoteStatus | null>(null)
  private started = false
  private sent: RemoteState | null = null
  private timer: ReturnType<typeof setInterval> | null = null
  /** Команды по очереди: «играть» и следом 49 «в очередь» с телефона не должны обгонять друг друга. */
  private chain: Promise<void> = Promise.resolve()

  init() {
    if (this.started || !isTauri) return
    this.started = true
    onRemoteCommand((raw) => {
      const cmd = parseCommand(raw)
      if (!cmd) return
      this.chain = this.chain
        .then(async () => {
          await this.run(cmd)
        })
        .catch((e) => {
          toast.show(errorText(e))
        })
    })
    onRemoteChanged(() => void this.refresh())
    onRemotePaired((name) => {
      toast.show(t('Пульт: {name} привязан', { name }))
      void this.refresh()
    })
    $effect.root(() => {
      $effect(() => {
        if (!settings.loaded) return
        const on = settings.get('remote.enabled')
        untrack(() => void this.apply(on))
      })
      // изменилось что-то, кроме позиции, — шлём сразу
      $effect(() => {
        const s = this.snapshot()
        untrack(() => this.push(s))
      })
    })
  }

  private async apply(on: boolean) {
    try {
      await api.remoteSetEnabled(on)
    } catch (e) {
      toast.show(errorText(e))
    }
    this.sent = null
    if (this.timer) clearInterval(this.timer)
    this.timer = on ? setInterval(() => this.push(this.snapshot()), TICK_MS) : null
    await this.refresh()
    if (on) this.push(this.snapshot())
  }

  async refresh() {
    try {
      this.status = await api.remoteStatus()
    } catch {
      this.status = null
    }
  }

  private snapshot(): RemoteState {
    return buildState(
      {
        current: player.current,
        positionMs: player.positionMs,
        durationMs: player.durationMs,
        playing: player.playing,
        volume: player.volume,
        repeat: player.repeat,
        shuffle: player.shuffle,
        liked: library.isLiked(player.current?.ref),
        upNext: player.upNext,
        contextTitle: player.contextTitle,
      },
      Date.now(),
    )
  }

  private push(next: RemoteState) {
    if (!settings.get('remote.enabled') || !shouldSend(next, this.sent, next.position_at)) return
    this.sent = next
    void api.remoteState(next).catch(() => {})
  }

  /** Трек по ref: из очереди, из присланного телефоном или из кэша метаданных. */
  private async resolve(ref: string, sent?: Track): Promise<Track | null> {
    const near = [player.current, ...player.upNext].find((x) => x?.ref === ref)
    if (near) return near
    if (sent) return sent
    const [cached] = await api.cachedTracks([ref])
    return cached ?? null
  }

  async run(cmd: RemoteCommand) {
    switch (cmd.type) {
      case 'toggle':
        return player.toggle()
      case 'next':
        return void (await player.next())
      case 'prev':
        return void (await player.prev())
      case 'seek':
        return player.seek(cmd.ms)
      case 'volume':
        return player.setVolume(cmd.value)
      case 'like': {
        const target = cmd.ref ? await this.resolve(cmd.ref) : player.current
        if (target && likeNeedsToggle(library.isLiked(target.ref), cmd.value)) await library.toggleLike(target)
        return
      }
      case 'play': {
        if (cmd.wave) return void (await wave.start())
        const track = await this.resolve(cmd.ref, cmd.track)
        if (!track) return toast.show(t('Пульт: трек не найден'))
        return void (await player.playList([track], 0, 'remote'))
      }
      case 'queue_add': {
        const track = await this.resolve(cmd.ref, cmd.track)
        if (!track) return toast.show(t('Пульт: трек не найден'))
        return void (await player.addToQueue([track], cmd.next))
      }
      case 'queue_play_index': {
        const sentQueue = this.sent?.queue.map((x) => x.ref) ?? []
        const i = queueIndexNow(sentQueue, cmd.index, player.upNext.map((x) => x.ref))
        if (i !== null) await player.jumpTo(i)
        return
      }
    }
  }
}

export const remote = new Remote()
