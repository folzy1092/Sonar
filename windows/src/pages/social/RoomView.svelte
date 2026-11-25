<script lang="ts">
  // Комната (демо): что играет у лидера, участники с ролями, общая очередь с «кто добавил».
  // Кнопки видны всем, но работают по правам роли того, чьими глазами смотрим (`canControl` и т. д.);
  // каждое нажатие — операция `applyOp`, как её потом примет сервер.
  import { onMount, untrack } from 'svelte'
  import Cover from '../../components/Cover.svelte'
  import Icon from '../../components/Icon.svelte'
  import { cascade } from '../../lib/cascade'
  import { t } from '../../lib/i18n.svelte'
  import { player } from '../../player/player.svelte'
  import { offline } from '../../lib/offline.svelte'
  import type { ListTrack } from '../../lib/api'
  import { anchorPosition, canControl, canEditQueue, canManageRoles, mainRole, type Room, type RoomOp, type RoomRole } from '../../lib/rooms/room-core'

  interface Props {
    room: Room
    viewer: string
    byRef: Map<string, ListTrack>
    names: Map<string, string>
    title: string
    onop: (op: RoomOp) => void
    onrebuild: () => void
  }
  let { room, viewer, byRef, names, title, onop, onrebuild }: Props = $props()

  let now = $state(Date.now())
  onMount(() => {
    const id = setInterval(() => (now = Date.now()), 500)
    return () => clearInterval(id)
  })

  const current = $derived(byRef.get(room.queue[room.pos]?.ref ?? ''))
  const duration = $derived(current?.duration_ms ?? 0)
  const position = $derived(Math.min(duration, anchorPosition(room, now)))
  const control = $derived(canControl(room, viewer))
  const editQueue = $derived(canEditQueue(room, viewer))
  const manage = $derived(canManageRoles(room, viewer))
  const nameOf = (u: string) => names.get(u) ?? u

  const ROLE: Record<RoomRole, string> = { host: 'Хост', leader: 'Лидер', dj: 'Диджей', listener: 'Слушатель' }

  const clock = (ms: number) => {
    const s = Math.floor(ms / 1000)
    return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`
  }

  // трек кончился у лидера — следующий (сервер делает это сам по длительности)
  $effect(() => {
    if (room.playing && duration && position >= duration && control && room.pos + 1 < room.queue.length) untrack(() => onop({ type: 'next' }))
  })

  function addCurrent() {
    const tr = player.current
    if (!tr) return
    onop(editQueue ? { type: 'queue.add', ref: tr.ref } : { type: 'suggest', ref: tr.ref })
  }
</script>

{#if room.closed}
  <div class="closed">
    <Icon name="x" size={22} />
    <b>{t('Комната закрыта')}</b>
    <button class="primary press" onclick={onrebuild}>{t('Собрать демо заново')}</button>
  </div>
{:else}
  <div class="room">
    <section class="now card">
      <Cover url={current?.cover_url} size={112} radius="var(--radius-m)" source={current?.ref} />
      <div class="meta">
        <small class="kicker">{title}</small>
        <b class="title">{current?.title ?? '—'}</b>
        <span class="artist">{current?.artist ?? ''}</span>
        <div class="progress" aria-hidden="true"><i style:width="{duration ? (position / duration) * 100 : 0}%"></i></div>
        <div class="row">
          <span class="time">{clock(position)} / {clock(duration)}</span>
          <span class="controls">
            <button class="round press" disabled={!control} aria-label={t('Предыдущий трек')} onclick={() => onop({ type: 'prev' })}><Icon name="prev" size={18} /></button>
            <button
              class="round big press"
              disabled={!control}
              aria-label={room.playing ? t('Пауза') : t('Играть')}
              onclick={() => onop(room.playing ? { type: 'pause', position_ms: position } : { type: 'play' })}
            >
              <Icon name={room.playing ? 'pause' : 'play'} size={20} filled />
            </button>
            <button class="round press" disabled={!control} aria-label={t('Следующий трек')} onclick={() => onop({ type: 'next' })}><Icon name="next" size={18} /></button>
          </span>
        </div>
        <small class="hint">
          {control ? t('Пульт у тебя: пауза и перемотка — у всех сразу') : t('Пультом управляет {name}', { name: nameOf(room.leader) })}
        </small>
      </div>
    </section>

    <section class="members card">
      <h3>{t('Участники')} <span class="count">{room.members.length}</span></h3>
      <ul use:cascade>
        {#each room.members as m (m.username)}
          {@const role = mainRole(room, m.username)}
          <li class:me={m.username === viewer} title={m.username === viewer ? t('это ты') : undefined}>
            <span class="ava">
              {#if m.avatar_url}<img src={offline.src(m.avatar_url)} alt="" />{:else}{nameOf(m.username).slice(0, 1).toUpperCase()}{/if}
            </span>
            <span class="who">
              <b>{nameOf(m.username)}</b>
              <small class="role role-{role}">
                {#if room.leader === m.username}<Icon name="crown" size={12} />{/if}
                {role ? t(ROLE[role]) : ''}{#if room.host === m.username && room.leader !== m.username} · {t('пульт отдан')}{/if}
              </small>
            </span>
            {#if manage && m.username !== room.leader}
              <span class="mact">
                <button class="pill press" onclick={() => onop({ type: 'leader.set', username: m.username })}>{t('Отдать пульт')}</button>
                {#if m.username !== room.host}
                  <button class="pill press" class:on={room.djs.includes(m.username)} onclick={() => onop({ type: 'dj.set', username: m.username, on: !room.djs.includes(m.username) })}>
                    {t('Диджей')}
                  </button>
                {/if}
              </span>
            {/if}
          </li>
        {/each}
      </ul>
      <p class="note">{t('Звук у каждого свой: эквалайзер и эффекты не синхронизируются, скорость в комнате — всегда 1×.')}</p>
      {#if viewer === room.host}
        <button class="danger press" onclick={() => onop({ type: 'close' })}><Icon name="x" size={14} />{t('Закрыть комнату')}</button>
      {/if}
    </section>

    <section class="queue card">
      <div class="qhead">
        <h3>{t('Очередь комнаты')}</h3>
        <button class="pill press" disabled={!player.current} onclick={addCurrent}>
          <Icon name="plus" size={14} />{editQueue ? t('Добавить, что играет у меня') : t('Предложить, что играет у меня')}
        </button>
      </div>
      <ol use:cascade>
        {#each room.queue as item, i (item.ref + ':' + i)}
          {@const tr = byRef.get(item.ref)}
          <li class:playing={i === room.pos} class:past={i < room.pos}>
            <button class="pick" disabled={!control || i === room.pos} onclick={() => onop({ type: 'jump', index: i })}>
              <span class="n">{#if i === room.pos}<Icon name="waveform" size={14} />{:else}{i + 1}{/if}</span>
              <Cover url={tr?.cover_url} size={36} source={item.ref} />
              <span class="tt">
                <b>{tr?.title ?? item.ref}</b>
                <small>{tr?.artist ?? ''}</small>
              </span>
            </button>
            <small class="by" title={t('Кто добавил')}><Icon name="user" size={12} />{item.added_by === viewer ? t('Ты') : nameOf(item.added_by)}</small>
            {#if editQueue && i !== room.pos}
              <button class="icon press" aria-label={t('Убрать')} title={t('Убрать')} onclick={() => onop({ type: 'queue.remove', index: i })}><Icon name="x" size={14} /></button>
            {/if}
          </li>
        {/each}
      </ol>
    </section>
  </div>
{/if}

<style>
  .room {
    display: grid;
    grid-template-columns: minmax(0, 1.4fr) minmax(260px, 1fr);
    grid-template-areas: 'now members' 'queue members';
    align-items: start;
    gap: 16px;
  }
  @media (max-width: 860px) {
    .room {
      grid-template-columns: 1fr;
      grid-template-areas: 'now' 'members' 'queue';
    }
  }
  .card {
    padding: 16px;
    border-radius: var(--radius-l);
    background: var(--plate);
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
  }
  .now {
    grid-area: now;
    display: flex;
    gap: 16px;
    align-items: center;
  }
  .members {
    grid-area: members;
    display: flex;
    flex-direction: column;
    gap: 10px;
  }
  .queue {
    grid-area: queue;
  }
  .meta {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
    flex: 1;
  }
  .kicker,
  .hint,
  .time,
  .note {
    color: var(--text-3);
    font-size: calc(12px * var(--fs, 1));
  }
  .title {
    font-size: calc(18px * var(--fs, 1));
    font-weight: 700;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .artist {
    color: var(--text-2);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .progress {
    height: 4px;
    margin: 10px 0 6px;
    border-radius: 2px;
    background: var(--track);
    overflow: hidden;
  }
  .progress i {
    display: block;
    height: 100%;
    background: var(--accent);
    transition: width 0.5s linear;
  }
  .row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
  }
  .controls {
    display: flex;
    align-items: center;
    gap: 6px;
  }
  .round {
    display: grid;
    place-items: center;
    width: 34px;
    height: 34px;
    border-radius: 50%;
    color: var(--text);
    transition:
      background var(--fast) var(--ease),
      opacity var(--fast) var(--ease);
  }
  .round:hover:not(:disabled) {
    background: var(--hover);
  }
  .round.big {
    width: 40px;
    height: 40px;
    background: var(--accent);
    color: var(--accent-ink);
  }
  .round:disabled {
    opacity: 0.4;
    cursor: default;
  }
  h3 {
    margin: 0;
    font-size: calc(15px * var(--fs, 1));
    font-weight: 700;
  }
  .count {
    color: var(--text-3);
    font-weight: 600;
    margin-left: 4px;
  }
  ul,
  ol {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }
  .members li {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 6px 8px;
    margin: 0 -8px;
    border-radius: var(--radius-m);
    transition: background var(--fast) var(--ease);
  }
  .members li.me {
    background: var(--accent-soft);
  }
  .ava {
    display: grid;
    place-items: center;
    width: 34px;
    height: 34px;
    flex-shrink: 0;
    border-radius: 50%;
    overflow: hidden;
    background: var(--surface-3);
    color: var(--text-2);
    font-weight: 700;
  }
  .ava img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }
  .who {
    display: flex;
    flex-direction: column;
    min-width: 0;
    flex: 1;
  }
  .who b {
    font-weight: 600;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .role {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    color: var(--text-3);
    font-size: calc(12px * var(--fs, 1));
  }
  .role-leader,
  .role-host {
    color: var(--text-2);
  }
  .mact {
    display: flex;
    gap: 6px;
    flex-shrink: 0;
  }
  .pill {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    height: 28px;
    padding: 0 10px;
    border-radius: 999px;
    border: 1px solid var(--border-strong);
    color: var(--text-2);
    font-size: calc(12px * var(--fs, 1));
    font-weight: 600;
    transition:
      background var(--fast) var(--ease),
      color var(--fast) var(--ease);
  }
  .pill:hover:not(:disabled) {
    background: var(--hover);
    color: var(--text);
  }
  .pill.on {
    background: var(--accent-soft);
    border-color: transparent;
    color: var(--text);
  }
  .pill:disabled {
    opacity: 0.45;
    cursor: default;
  }
  .danger {
    display: inline-flex;
    align-items: center;
    align-self: flex-start;
    gap: 6px;
    height: 32px;
    padding: 0 12px;
    border-radius: 10px;
    color: var(--danger);
    font-weight: 600;
    font-size: calc(13px * var(--fs, 1));
  }
  .danger:hover {
    background: color-mix(in srgb, var(--danger) 12%, transparent);
  }
  .qhead {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
    margin-bottom: 10px;
  }
  .queue li {
    display: flex;
    align-items: center;
    gap: 8px;
    border-radius: var(--radius-m);
    padding-right: 6px;
    transition: background var(--fast) var(--ease);
  }
  .queue li:hover {
    background: var(--hover);
  }
  .queue li.playing {
    background: var(--accent-soft);
  }
  .queue li.past {
    opacity: 0.55;
  }
  .pick {
    display: flex;
    align-items: center;
    gap: 10px;
    flex: 1;
    min-width: 0;
    padding: 6px 8px;
    text-align: left;
    color: inherit;
  }
  .pick:disabled {
    cursor: default;
  }
  .n {
    width: 20px;
    color: var(--text-3);
    font-size: calc(12px * var(--fs, 1));
    text-align: center;
    flex-shrink: 0;
  }
  .tt {
    display: flex;
    flex-direction: column;
    min-width: 0;
  }
  .tt b,
  .tt small {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .tt b {
    font-weight: 600;
  }
  .tt small,
  .by {
    color: var(--text-3);
    font-size: calc(12px * var(--fs, 1));
  }
  .by {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    flex-shrink: 0;
    white-space: nowrap;
  }
  .icon {
    display: grid;
    place-items: center;
    width: 28px;
    height: 28px;
    border-radius: 50%;
    color: var(--text-3);
  }
  .icon:hover {
    background: var(--hover);
    color: var(--text);
  }
  .closed {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 12px;
    padding: 48px 0;
    color: var(--text-2);
  }
  .primary {
    height: 36px;
    padding: 0 16px;
    border-radius: 10px;
    background: var(--accent);
    color: var(--accent-ink);
    font-weight: 600;
  }
</style>
