<script lang="ts">
  // Сообщения (демо): список чатов слева, лента справа. Вложения — трек (играть / в очередь), приглашение в
  // комнату («Войти»); ответ, правка и удаление своих, «прочитано». Ссылка `sonar://track/<ref>` в тексте
  // сама становится карточкой трека, если трек есть в медиатеке. Отправленное живёт только в памяти страницы.
  import { tick, untrack } from 'svelte'
  import Cover from '../../components/Cover.svelte'
  import Icon from '../../components/Icon.svelte'
  import { cascade } from '../../lib/cascade'
  import { t } from '../../lib/i18n.svelte'
  import { player } from '../../player/player.svelte'
  import { toast } from '../../lib/toast.svelte'
  import type { ListTrack } from '../../lib/api'
  import {
    canDelete, canEdit, checkDraft, deleteMessage, editMessage, groupRuns, parseSonarLinks, replyPreview, seenByPeer, timeline,
    unreadCount, type DMAttachment, type DMMessage,
  } from '../../lib/dm/dm-core'
  import type { DemoChat } from './social-demo'

  interface Props {
    chat: DemoChat
    me: string
    names: Map<string, string>
    byRef: Map<string, ListTrack>
    onsend: (m: DMMessage) => void
    onreplace: (m: DMMessage) => void
    onread: (threadId: string) => void
    onopenroom: () => void
  }
  let { chat, me, names, byRef, onsend, onreplace, onread, onopenroom }: Props = $props()

  let active = $state(untrack(() => chat.threads[0]?.id ?? ''))
  let draft = $state('')
  let attached = $state<DMAttachment[]>([])
  let replyTo = $state<string | null>(null)
  let editing = $state<string | null>(null)
  let feed: HTMLElement | undefined = $state()
  let field: HTMLTextAreaElement | undefined = $state()

  const thread = $derived(chat.threads.find((th) => th.id === active))
  const line = $derived(timeline(chat.messages, active))
  const runs = $derived(groupRuns(line))
  const byId = $derived(new Map(chat.messages.map((m) => [m.id, m])))
  const nameOf = (u: string) => (u === me ? t('Ты') : (names.get(u) ?? u))
  const threadTitle = (th: DemoChat['threads'][number]) => (th.room_id ? t('Чат комнаты') : nameOf(th.peer ?? ''))
  const lastOf = (id: string) => timeline(chat.messages, id).at(-1)
  const timeOf = (ms: number) => new Date(ms).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })

  // открыли чат — всё прочитано, лента — к последнему сообщению
  $effect(() => {
    const id = active
    if (id) untrack(() => onread(id))
  })
  $effect(() => {
    line.length
    void tick().then(() => feed?.scrollTo({ top: feed.scrollHeight }))
  })

  const trackAttachment = (tr: { ref: string; title: string; artist: string; cover_url: string | null }): DMAttachment => ({
    kind: 'track', ref: tr.ref, title: tr.title, artist: tr.artist, cover_url: tr.cover_url,
  })

  function attachCurrent() {
    const tr = player.current
    if (!tr || attached.some((a) => a.kind === 'track' && a.ref === tr.ref)) return
    attached = [...attached, trackAttachment(tr)]
  }

  function submit() {
    if (editing) {
      const msg = byId.get(editing)
      const next = msg && editMessage(msg, me, draft, Date.now())
      if (next) onreplace(next)
      editing = null
      draft = ''
      return
    }
    // ссылки на треки из медиатеки — карточками
    const fromLinks = parseSonarLinks(draft)
      .filter((l) => l.kind === 'track' && byRef.has(l.value) && !attached.some((a) => a.kind === 'track' && a.ref === l.value))
      .map((l) => trackAttachment(byRef.get(l.value)!))
    const all = [...attached, ...fromLinks]
    const ok = checkDraft(draft, all)
    if (!ok.ok) {
      if (ok.error !== 'empty') toast.show(ok.error === 'too_long' ? t('Слишком длинное сообщение') : t('Не больше четырёх вложений'))
      return
    }
    onsend({
      id: `local_${Date.now()}`,
      thread_id: active,
      from: me,
      text: ok.text,
      attachments: all,
      reply_to: replyTo,
      sent_at: Date.now(),
      edited_at: null,
      deleted: false,
    })
    draft = ''
    attached = []
    replyTo = null
  }

  function onkey(e: KeyboardEvent) {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      submit()
    } else if (e.key === 'Escape') cancel()
  }

  function startEdit(m: DMMessage) {
    editing = m.id
    replyTo = null
    draft = m.text
    void tick().then(() => field?.focus())
  }

  function startReply(m: DMMessage) {
    replyTo = m.id
    editing = null
    void tick().then(() => field?.focus())
  }

  function cancel() {
    if (editing) draft = ''
    editing = null
    replyTo = null
  }

  function remove(m: DMMessage) {
    const next = deleteMessage(m, me)
    if (next) onreplace(next)
  }

  function playTrack(ref: string) {
    const tr = byRef.get(ref)
    if (tr) void player.playList([tr], 0, null, t('Из сообщений'))
    else toast.show(t('Этого трека нет в твоей медиатеке — с сервером найдём через резерв'))
  }

  function queueTrack(ref: string) {
    const tr = byRef.get(ref)
    if (!tr) return toast.show(t('Этого трека нет в твоей медиатеке — с сервером найдём через резерв'))
    void player.addToQueue([tr], false)
    toast.show(t('Добавлено в очередь'))
  }
</script>

<div class="chat">
  <aside class="threads card">
    <ul use:cascade>
      {#each chat.threads as th (th.id)}
        {@const last = lastOf(th.id)}
        {@const unread = unreadCount(th, chat.messages, me)}
        <li>
          <button class="th" class:on={active === th.id} onclick={() => (active = th.id)}>
            <span class="ava">{#if th.room_id}<Icon name="group" size={16} />{:else}{threadTitle(th).slice(0, 1).toUpperCase()}{/if}</span>
            <span class="tt">
              <b>{threadTitle(th)}</b>
              <small>{last ? (replyPreview(last, 40) ?? t('Сообщение удалено')) : ''}</small>
            </span>
            {#if unread && active !== th.id}<span class="dot">{unread}</span>{/if}
          </button>
        </li>
      {/each}
    </ul>
  </aside>

  <section class="feed card">
    <div class="scroll" bind:this={feed}>
      {#each runs as run (run[0].id)}
        {@const mine = run[0].from === me}
        <div class="run" class:mine>
          <small class="author">{nameOf(run[0].from)}</small>
          {#each run as m (m.id)}
            {@const quote = m.reply_to ? byId.get(m.reply_to) : undefined}
            <div class="msg" class:deleted={m.deleted}>
              {#if m.reply_to}
                <div class="quote"><Icon name="reply" size={12} />{replyPreview(quote, 60) ?? t('Сообщение удалено')}</div>
              {/if}
              {#if m.deleted}
                <i>{t('Сообщение удалено')}</i>
              {:else}
                {#if m.text}<p>{m.text}</p>{/if}
                {#each m.attachments as a, i (i)}
                  {#if a.kind === 'track'}
                    <div class="att">
                      <Cover url={a.cover_url} size={44} source={a.ref} />
                      <span class="tt"><b>{a.title}</b><small>{a.artist}</small></span>
                      <button class="mini press" aria-label={t('Играть')} title={t('Играть')} onclick={() => playTrack(a.ref)}><Icon name="play" size={14} filled /></button>
                      <button class="mini press" aria-label={t('В очередь')} title={t('В очередь')} onclick={() => queueTrack(a.ref)}><Icon name="queue" size={14} /></button>
                    </div>
                  {:else if a.kind === 'room'}
                    <div class="att">
                      <span class="ava"><Icon name="group" size={16} /></span>
                      <span class="tt"><b>{a.title}</b><small>{t('Приглашение в комнату')}</small></span>
                      <button class="join press" onclick={onopenroom}>{t('Войти')}</button>
                    </div>
                  {:else}
                    <div class="att">
                      <Cover url={a.cover_url} size={44} />
                      <span class="tt"><b>{a.title}</b><small>{t('Плейлист')}</small></span>
                    </div>
                  {/if}
                {/each}
              {/if}
              <span class="foot">
                {timeOf(m.sent_at)}{#if m.edited_at} · {t('изменено')}{/if}
                {#if thread && seenByPeer(thread, m, me)} · <Icon name="check" size={12} />{/if}
                {#if !m.deleted}
                  <span class="tools">
                    <button aria-label={t('Ответить')} title={t('Ответить')} onclick={() => startReply(m)}><Icon name="reply" size={13} /></button>
                    {#if canEdit(m, me, Date.now()) && m.text}
                      <button aria-label={t('Изменить')} title={t('Изменить')} onclick={() => startEdit(m)}><Icon name="pencil" size={13} /></button>
                    {/if}
                    {#if canDelete(m, me)}
                      <button aria-label={t('Удалить')} title={t('Удалить')} onclick={() => remove(m)}><Icon name="trash" size={13} /></button>
                    {/if}
                  </span>
                {/if}
              </span>
            </div>
          {/each}
        </div>
      {/each}
    </div>

    <div class="composer">
      {#if replyTo || editing}
        <div class="context">
          <Icon name={editing ? 'pencil' : 'reply'} size={13} />
          <span>{editing ? t('Правка сообщения') : (replyPreview(byId.get(replyTo ?? '')) ?? '')}</span>
          <button aria-label={t('Отмена')} onclick={cancel}><Icon name="x" size={13} /></button>
        </div>
      {/if}
      {#if attached.length}
        <div class="context">
          {#each attached as a, i (i)}
            <span class="chipatt">
              <Icon name="music" size={12} />{a.title}
              <button aria-label={t('Убрать')} onclick={() => (attached = attached.filter((_, j) => j !== i))}><Icon name="x" size={12} /></button>
            </span>
          {/each}
        </div>
      {/if}
      <div class="input">
        <button class="mini press" disabled={!player.current || !!editing} aria-label={t('Прикрепить, что играет')} title={t('Прикрепить, что играет')} onclick={attachCurrent}>
          <Icon name="music" size={16} />
        </button>
        <textarea bind:this={field} bind:value={draft} rows="1" placeholder={t('Сообщение…')} onkeydown={onkey}></textarea>
        <button class="send press" aria-label={t('Отправить')} title={t('Отправить')} onclick={submit}><Icon name="send" size={16} /></button>
      </div>
      <small class="note">{t('Сообщения не шифруются сквозным шифрованием: их увидит сервер Sonar.')}</small>
    </div>
  </section>
</div>

<style>
  .chat {
    display: grid;
    grid-template-columns: 260px minmax(0, 1fr);
    gap: 16px;
    min-height: 460px;
  }
  @media (max-width: 760px) {
    .chat {
      grid-template-columns: 1fr;
    }
  }
  .card {
    border-radius: var(--radius-l);
    background: var(--plate);
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
  }
  .threads {
    padding: 8px;
    align-self: start;
  }
  ul {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }
  .th {
    display: flex;
    align-items: center;
    gap: 10px;
    width: 100%;
    padding: 8px;
    border-radius: var(--radius-m);
    text-align: left;
    color: inherit;
    transition: background var(--fast) var(--ease);
  }
  .th:hover {
    background: var(--hover);
  }
  .th.on {
    background: var(--accent-soft);
  }
  .ava {
    display: grid;
    place-items: center;
    width: 36px;
    height: 36px;
    flex-shrink: 0;
    border-radius: 50%;
    background: var(--surface-3);
    color: var(--text-2);
    font-weight: 700;
  }
  .tt {
    display: flex;
    flex-direction: column;
    min-width: 0;
    flex: 1;
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
  .tt small {
    color: var(--text-3);
    font-size: calc(12px * var(--fs, 1));
  }
  .dot {
    min-width: 20px;
    height: 20px;
    padding: 0 6px;
    border-radius: 10px;
    background: var(--accent);
    color: var(--accent-ink);
    font-size: 11px;
    font-weight: 700;
    display: grid;
    place-items: center;
  }
  .feed {
    display: flex;
    flex-direction: column;
    min-height: 0;
    max-height: 70vh;
  }
  .scroll {
    flex: 1;
    overflow-y: auto;
    padding: 16px;
    display: flex;
    flex-direction: column;
    gap: 14px;
  }
  .run {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 4px;
    max-width: 78%;
  }
  .run.mine {
    align-self: flex-end;
    align-items: flex-end;
  }
  .author {
    color: var(--text-3);
    font-size: calc(12px * var(--fs, 1));
    padding: 0 4px;
  }
  .msg {
    position: relative;
    display: flex;
    flex-direction: column;
    gap: 6px;
    padding: 8px 12px;
    border-radius: 14px;
    background: var(--surface-2);
  }
  .mine .msg {
    background: var(--accent-soft);
  }
  .msg p {
    margin: 0;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
    user-select: text;
  }
  .msg.deleted i {
    color: var(--text-3);
  }
  .quote {
    display: flex;
    align-items: center;
    gap: 6px;
    padding-left: 8px;
    border-left: 2px solid var(--border-strong);
    color: var(--text-3);
    font-size: calc(12px * var(--fs, 1));
  }
  .att {
    display: flex;
    align-items: center;
    gap: 10px;
    min-width: 240px;
    padding: 6px;
    border-radius: var(--radius-m);
    background: var(--plate);
    border: 1px solid var(--card-line);
  }
  .mini {
    display: grid;
    place-items: center;
    width: 30px;
    height: 30px;
    flex-shrink: 0;
    border-radius: 50%;
    color: var(--text-2);
    transition: background var(--fast) var(--ease);
  }
  .mini:hover:not(:disabled) {
    background: var(--hover);
    color: var(--text);
  }
  .mini:disabled {
    opacity: 0.4;
  }
  .join {
    height: 30px;
    padding: 0 14px;
    border-radius: 999px;
    background: var(--accent);
    color: var(--accent-ink);
    font-weight: 600;
    font-size: calc(13px * var(--fs, 1));
  }
  .foot {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    color: var(--text-3);
    font-size: 11px;
  }
  .tools {
    display: inline-flex;
    gap: 2px;
    margin-left: 6px;
    opacity: 0;
    transition: opacity var(--fast) var(--ease);
  }
  .msg:hover .tools,
  .tools:focus-within {
    opacity: 1;
  }
  .tools button {
    display: grid;
    place-items: center;
    width: 22px;
    height: 22px;
    border-radius: 6px;
    color: var(--text-3);
  }
  .tools button:hover {
    background: var(--hover);
    color: var(--text);
  }
  .composer {
    display: flex;
    flex-direction: column;
    gap: 6px;
    padding: 10px 12px 12px;
    border-top: 1px solid var(--border);
  }
  .context {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 6px;
    color: var(--text-2);
    font-size: calc(12px * var(--fs, 1));
  }
  .context > span:not(.chipatt) {
    flex: 1;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .context button {
    display: grid;
    place-items: center;
    color: var(--text-3);
  }
  .chipatt {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    height: 24px;
    padding: 0 8px;
    border-radius: 999px;
    background: var(--surface-2);
  }
  .input {
    display: flex;
    align-items: flex-end;
    gap: 6px;
  }
  textarea {
    flex: 1;
    resize: none;
    min-height: 36px;
    max-height: 120px;
    padding: 8px 12px;
    border-radius: 18px;
    border: 1px solid var(--border-strong);
    background: var(--surface-1);
    color: var(--text);
    font: inherit;
    field-sizing: content;
  }
  textarea:focus {
    outline: none;
    border-color: var(--accent);
  }
  .send {
    display: grid;
    place-items: center;
    width: 36px;
    height: 36px;
    flex-shrink: 0;
    border-radius: 50%;
    background: var(--accent);
    color: var(--accent-ink);
  }
  .note {
    color: var(--text-3);
    font-size: 11px;
  }
</style>
