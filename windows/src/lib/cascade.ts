// Каскад появления (класс .cascade в app.css) — один раз при показе и заново, когда меняется ключ
// (новые результаты поиска). Потом класс снимается, чтобы перестановка строк не «мигала».
export function cascade(node: HTMLElement, key?: unknown) {
  let timer: ReturnType<typeof setTimeout> | undefined
  const run = () => {
    node.classList.add('cascade')
    clearTimeout(timer)
    timer = setTimeout(() => node.classList.remove('cascade'), 1000)
  }
  run()
  return {
    update(next?: unknown) {
      if (next === key) return
      key = next
      node.classList.remove('cascade')
      void node.offsetWidth
      run()
    },
    destroy() {
      clearTimeout(timer)
    },
  }
}
