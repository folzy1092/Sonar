<script lang="ts">
  import Icon from './Icon.svelte'
  import type { IconName } from './icons'

  interface Props {
    icon: IconName
    title: string
    text?: string
  }

  let { icon, title, text }: Props = $props()
</script>

<div class="empty">
  <div class="badge"><Icon name={icon} size={28} stroke={1.7} /></div>
  <h3>{title}</h3>
  {#if text}<p>{text}</p>{/if}
</div>

<style>
  .empty {
    display: flex;
    flex-direction: column;
    align-items: center;
    text-align: center;
    gap: 10px;
    padding: 56px 24px;
  }
  .badge {
    display: grid;
    place-items: center;
    width: 64px;
    height: 64px;
    border-radius: 50%;
    background: var(--plate);
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
    color: var(--text-2);
    margin-bottom: 6px;
  }
  h3 {
    font-size: calc(18px * var(--fs, 1));
    font-weight: 700;
  }
  p {
    margin: 0;
    max-width: 360px;
    color: var(--text-3);
  }
</style>
