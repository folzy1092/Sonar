<script lang="ts">
  // «Вместе» — комнаты совместного прослушивания и личные сообщения (docs/ROOMS.md, docs/DM.md).
  // До сервера это предпросмотр: друзья выдуманы (pages/social/social-demo.ts), всё живёт в памяти страницы
  // и никуда не уходит. Правила настоящие — комнату двигает lib/rooms/room-core, чат — lib/dm/dm-core,
  // поэтому кнопки ролей ведут себя так, как будут с сервером. «Создать комнату» и «Пригласить» неактивны.
  import Icon from '../components/Icon.svelte'
  import EmptyState from '../components/EmptyState.svelte'
  import RoomView from './social/RoomView.svelte'
  import ChatView from './social/ChatView.svelte'
  import { api, type ListTrack } from '../lib/api'
  import { t } from '../lib/i18n.svelte'
  import { indicator } from '../lib/indicator'
  import { settings } from '../lib/settings.svelte'
  import { toast } from '../lib/toast.svelte'
  import { applyOp, type Room, type RoomError, type RoomMember, type RoomOp } from '../lib/rooms/room-core'
  import type { DMMessage } from '../lib/dm/dm-core'
  import { demoChat, demoMembers, demoRoom, FRIEND, FRIEND2, type DemoChat } from './social/social-demo'
  import { router } from '../app/router.svelte'

  type Tab = 'room' | 'chat'
  let tab = $state<Tab>(router.param === 'chat' ? 'chat' : 'room')
  let tracks = $state<ListTrack[] | null>(null)
  let room = $state<Room | null>(null)
  let chat = $state<DemoChat | null>(null)
  /** Чьими глазами смотреть на комнату: я (хост) или один из демо-друзей. */
  let viewer = $state('')

  const me = $derived<RoomMember>({
    username: settings.get('profile.username') || 'me',
    display_name: settings.get('profile.name') || t('вместе::Я'),
    avatar_url: settings.get('profile.avatar') || null,
  })
  const members = $derived(demoMembers(me, t('Друг'), t('Второй друг')))
  const byRef = $derived(new Map((tracks ?? []).map((tr) => [tr.ref, tr])))
  const names = $derived(new Map(members.map((m) => [m.username, m.display_name ?? m.username])))
  const roomTitle = $derived(settings.get('profile.name') ? t('Комната {name}', { name: settings.get('profile.name') }) : t('Моя комната'))

  function build() {
    const list = tracks ?? []
    const now = Date.now()
    room = list.length ? demoRoom(members, list, now) : null
    chat = demoChat(
      me.username,
      list,
      roomTitle,
      {
        hey: t('Слушай, что скажешь про этот?'),
        fire: t('Огонь, кинул в Любимые'),
        join: t('Залетай, включил свои любимые'),
        room: t('Я тут, слышу всё синхронно'),
      },
      now,
    )
    viewer = me.username
  }

  void api
    .favorites()
    .catch(() => [] as ListTrack[])
    .then((list) => {
      tracks = list.filter((tr) => tr.available)
      build()
    })

  const ERRORS: Record<Exclude<RoomError, 'noop'>, string> = {
    closed: 'Комната закрыта',
    forbidden: 'У этой роли нет на это прав',
    full: 'В комнате нет мест',
    not_member: 'Ты не в комнате',
    bad_index: 'Так нельзя: этот трек играет или очередь кончилась',
    no_user: 'Этого участника уже нет в комнате',
  }

  function act(op: RoomOp) {
    if (!room) return
    const res = applyOp(room, viewer, op, Date.now())
    if (res.ok) room = res.room
    else if (res.error !== 'noop') toast.show(t(ERRORS[res.error]))
    else if (op.type === 'suggest') toast.show(t('Предложение увидят лидер и диджеи, когда у Sonar появится сервер'))
  }

  function send(msg: DMMessage) {
    if (chat) chat = { ...chat, messages: [...chat.messages, msg] }
  }
  function replace(msg: DMMessage) {
    if (chat) chat = { ...chat, messages: chat.messages.map((m) => (m.id === msg.id ? msg : m)) }
  }
  function read(threadId: string) {
    if (!chat) return
    const now = Date.now()
    chat = { ...chat, threads: chat.threads.map((th) => (th.id === threadId ? { ...th, my_read_at: now } : th)) }
  }

  const viewers = $derived([
    { id: me.username, label: t('вместе::Я') },
    { id: FRIEND, label: t('Друг') },
    { id: FRIEND2, label: t('Второй друг') },
  ])
</script>

<div class="social">
  <div class="bar">
    <span class="badge"><Icon name="group" size={18} /></span>
    <span class="text">
      <b>{t('Комнаты и сообщения — предпросмотр')}</b>
      <small>{t('Заработает вместе с сервером и друзьями. Сейчас друзья выдуманы, а треки — из твоих Любимых; никуда ничего не уходит.')}</small>
    </span>
    <span class="actions">
      <button class="ghost" disabled title={t('Появится с сервером')}><Icon name="plus" size={16} />{t('Создать комнату')}</button>
      <button class="ghost" disabled title={t('Появится с сервером')}><Icon name="share" size={16} />{t('Пригласить')}</button>
    </span>
  </div>

  <div class="head">
    <div class="chips" role="tablist" aria-label={t('Вместе')} use:indicator={{ key: tab, kind: 'pill' }}>
      {#each [['room', 'Комната'], ['chat', 'Сообщения']] as const as [id, label] (id)}
        <button class="chip" class:on={tab === id} role="tab" aria-selected={tab === id} onclick={() => (tab = id)}>{t(label)}</button>
      {/each}
    </div>
    {#if tab === 'room' && room}
      <div class="chips small" role="radiogroup" aria-label={t('Чьими глазами')} use:indicator={{ key: viewer, kind: 'pill' }}>
        <span class="label">{t('Чьими глазами')}</span>
        {#each viewers as v (v.id)}
          <button class="chip" class:on={viewer === v.id} role="radio" aria-checked={viewer === v.id} onclick={() => (viewer = v.id)}>{v.label}</button>
        {/each}
      </div>
    {/if}
  </div>

  {#if tracks === null}
    <p class="loading">{t('Загружаю…')}</p>
  {:else if tab === 'room'}
    {#if room}
      {#key room.id}
        <RoomView {room} {viewer} {byRef} {names} title={roomTitle} onop={act} onrebuild={build} />
      {/key}
    {:else}
      <EmptyState icon="heart" title={t('Нужны Любимые')} text={t('Поставь лайк паре треков — на них соберётся демо-комната.')} />
    {/if}
  {:else if chat}
    <ChatView {chat} me={me.username} {names} {byRef} onsend={send} onreplace={replace} onread={read} onopenroom={() => (tab = 'room')} />
  {/if}
</div>

<style>
  .social {
    display: flex;
    flex-direction: column;
    gap: 20px;
    padding-top: 34px;
    min-height: 100%;
  }
  .bar {
    display: flex;
    align-items: center;
    gap: 14px;
    padding: 12px 14px;
    border-radius: var(--radius-l);
    border: 1px dashed var(--border-strong);
    background: var(--plate);
  }
  .badge {
    display: grid;
    place-items: center;
    width: 36px;
    height: 36px;
    flex-shrink: 0;
    border-radius: 50%;
    background: color-mix(in srgb, var(--accent) 18%, transparent);
    color: var(--accent);
  }
  .text {
    display: flex;
    flex-direction: column;
    gap: 1px;
    min-width: 0;
    flex: 1;
  }
  .text b {
    font-size: calc(14px * var(--fs, 1));
    font-weight: 600;
  }
  .text small {
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  .actions {
    display: flex;
    flex-wrap: wrap;
    justify-content: flex-end;
    gap: 8px;
  }
  .ghost {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    height: 36px;
    padding: 0 14px;
    border-radius: 10px;
    font-size: calc(13px * var(--fs, 1));
    font-weight: 600;
    color: var(--text-2);
  }
  .ghost:disabled {
    opacity: 0.5;
    cursor: default;
  }
  .head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    flex-wrap: wrap;
    gap: 12px;
  }
  .chips {
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .label {
    color: var(--text-3);
    font-size: calc(12px * var(--fs, 1));
    margin-right: 2px;
  }
  .chip {
    height: 34px;
    padding: 0 16px;
    border-radius: 999px;
    background: var(--plate);
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
    color: var(--text-2);
    font-weight: 600;
    transition:
      color var(--fast) var(--ease),
      background var(--fast) var(--ease);
  }
  .small .chip {
    height: 30px;
    padding: 0 12px;
    font-size: calc(13px * var(--fs, 1));
  }
  .chip:hover {
    color: var(--text);
    background: var(--hover);
  }
  .chip.on {
    background: transparent;
    border-color: transparent;
    color: var(--accent-ink);
  }
  .chips :global(.tab-ind.pill) {
    background: var(--accent);
  }
  .loading {
    color: var(--text-3);
  }
</style>
