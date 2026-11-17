<script lang="ts">
  // «Копировать ссылку на профиль» (Аккаунт → Профиль и шапка предпросмотра): `https://sonar.folzy.ru/@username`
  // в буфер обмена. Скопировано — значок ссылки меняется на галочку, подпись на «Ссылка скопирована»
  // (кроссфейдом), через пару секунд — обратно. Нет @username — кнопка неактивна.
  import Icon from './Icon.svelte'
  import { t } from '../lib/i18n.svelte'
  import { toast } from '../lib/toast.svelte'
  import { profileUrl } from '../lib/public-profile'

  const COPIED_MS = 1800

  let { username }: { username: string } = $props()
  const url = $derived(profileUrl(username))
  let copied = $state(false)
  let timer: ReturnType<typeof setTimeout> | undefined

  $effect(() => () => clearTimeout(timer))

  async function copy() {
    if (!url) return
    try {
      await navigator.clipboard.writeText(url)
      copied = true
      clearTimeout(timer)
      timer = setTimeout(() => (copied = false), COPIED_MS)
    } catch {
      toast.show(t('Не получилось скопировать'))
    }
  }
</script>

<button class="copy" class:done={copied} disabled={!url} title={url ?? t('Сначала задай @username')} onclick={copy}>
  {#key copied}
    <span class="swap"><Icon name={copied ? 'check' : 'link'} size={16} />{copied ? t('Ссылка скопирована') : t('Копировать ссылку на профиль')}</span>
  {/key}
</button>

<style>
  .copy {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    height: 36px;
    padding: 0 16px;
    border-radius: 10px;
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
    font-size: calc(13px * var(--fs, 1));
    font-weight: 600;
    color: var(--text-2);
    white-space: nowrap;
    transition:
      background var(--fast) var(--ease),
      color var(--fast) var(--ease),
      border-color var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .copy:hover:not(:disabled) {
    background: var(--hover);
    color: var(--text);
  }
  .copy:active:not(:disabled) {
    transform: scale(0.97);
  }
  .copy.done {
    color: var(--accent);
    border-color: color-mix(in srgb, var(--accent) 45%, transparent);
  }
  .copy:disabled {
    opacity: 0.45;
    cursor: default;
  }
  .swap {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    animation: tab-in var(--normal) var(--ease);
  }
</style>
