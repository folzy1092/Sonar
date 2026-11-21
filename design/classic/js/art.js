// Графика прототипа: свой набор иконок 24×24, абстрактные обложки, значки сервисов, знак Sonar.
// Иконки — контур 1.75, скруглённые концы; заливка только у управления воспроизведением.
// Подвижные части помечены классами p-* (в экспорте станут id).
window.Sonar = window.Sonar || {}
;(function (S) {
  const ICONS = Object.freeze({
    home: '<path d="M4 10.2 12 4l8 6.2V19a1 1 0 0 1-1 1h-4.5v-5.5h-5V20H5a1 1 0 0 1-1-1z"/>',
    search: '<circle cx="11" cy="11" r="6.5"/><path d="m16 16 4 4"/>',
    mix: '<circle class="fill" cx="12" cy="12" r="1.7"/><path class="p-wave1" d="M8.6 8.6a4.8 4.8 0 0 0 0 6.8M15.4 8.6a4.8 4.8 0 0 1 0 6.8"/><path class="p-wave2" d="M5.7 5.7a8.9 8.9 0 0 0 0 12.6M18.3 5.7a8.9 8.9 0 0 1 0 12.6"/>',
    heart: '<path class="p-heart" d="M12 19.5s-7.5-4.6-7.5-10.2A4.3 4.3 0 0 1 12 6.6a4.3 4.3 0 0 1 7.5 2.7c0 5.6-7.5 10.2-7.5 10.2z"/>',
    heartFill: '<path class="p-heart fill" d="M12 19.5s-7.5-4.6-7.5-10.2A4.3 4.3 0 0 1 12 6.6a4.3 4.3 0 0 1 7.5 2.7c0 5.6-7.5 10.2-7.5 10.2z"/>',
    playlist: '<path d="M4 6.5h11M4 11h11M4 15.5h6.5"/><circle cx="16" cy="17" r="2.5"/><path d="M18.5 17V8.5l2-.5"/>',
    artist: '<circle cx="12" cy="8.5" r="3.5"/><path d="M5.5 19.5a6.5 6.5 0 0 1 13 0"/>',
    album: '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="2.2"/>',
    folder: '<path d="M3.5 7.5a2 2 0 0 1 2-2h3.8l2 2h7.2a2 2 0 0 1 2 2V17a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2z"/>',
    file: '<path d="M7 3.5h6.5L18 8v12.5H7z"/><path d="M13.5 3.5V8H18"/>',
    stats: '<path d="M5 20v-7M10 20V5M15 20v-9M20 20v-4"/>',
    graph: '<circle cx="6" cy="7" r="2.2"/><circle cx="18" cy="6.5" r="2.2"/><circle cx="12" cy="17.5" r="2.6"/><path d="m7 9 3.8 6.2M17 8.6l-3.6 6.6M8.2 6.8l7.6-.3"/>',
    settings: '<path d="M4 7h9M18 7h2M4 17h3M12 17h8"/><circle cx="15.5" cy="7" r="2.2"/><circle cx="9.5" cy="17" r="2.2"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    more: '<circle class="fill" cx="5.5" cy="12" r="1.6"/><circle class="fill" cx="12" cy="12" r="1.6"/><circle class="fill" cx="18.5" cy="12" r="1.6"/>',
    chevL: '<path d="m14.5 6-6 6 6 6"/>',
    chevR: '<path d="m9.5 6 6 6-6 6"/>',
    chevD: '<path d="m6 9.5 6 6 6-6"/>',
    play: '<path class="fill p-play" d="M8 5.6v12.8a1 1 0 0 0 1.52.85l10.4-6.4a1 1 0 0 0 0-1.7L9.52 4.75A1 1 0 0 0 8 5.6z"/>',
    pause: '<rect class="fill p-bar1" x="6.5" y="5" width="4" height="14" rx="1.2"/><rect class="fill p-bar2" x="13.5" y="5" width="4" height="14" rx="1.2"/>',
    next: '<path class="fill" d="M4.5 6.6v10.8a.9.9 0 0 0 1.4.75l8-5.4a.9.9 0 0 0 0-1.5l-8-5.4a.9.9 0 0 0-1.4.75z"/><rect class="fill" x="16.5" y="5.5" width="3" height="13" rx="1"/>',
    prev: '<path class="fill" d="M19.5 6.6v10.8a.9.9 0 0 1-1.4.75l-8-5.4a.9.9 0 0 1 0-1.5l8-5.4a.9.9 0 0 1 1.4.75z"/><rect class="fill" x="4.5" y="5.5" width="3" height="13" rx="1"/>',
    shuffle: '<path d="M4 7h3.2c4.8 0 4.8 10 9.6 10H20M4 17h3.2c1.6 0 2.6-1.2 3.4-3M20 7h-3.2c-1.6 0-2.6 1.2-3.4 3M17.6 4.6 20 7l-2.4 2.4M17.6 14.6 20 17l-2.4 2.4"/>',
    repeat: '<path d="M5 11.5V9.5A2.5 2.5 0 0 1 7.5 7H19M16.6 4.6 19 7l-2.4 2.4M19 12.5v2A2.5 2.5 0 0 1 16.5 17H5M7.4 19.4 5 17l2.4-2.4"/>',
    queue: '<path d="M4 6h16M4 11h16M4 16h8.5"/><path class="fill" d="M16 13.7v5.6a.5.5 0 0 0 .77.42l4.2-2.8a.5.5 0 0 0 0-.84l-4.2-2.8a.5.5 0 0 0-.77.42z"/>',
    lyrics: '<path d="M5 5.5h14a1.5 1.5 0 0 1 1.5 1.5v8.5A1.5 1.5 0 0 1 19 17h-8l-4.5 3.2V17H5a1.5 1.5 0 0 1-1.5-1.5V7A1.5 1.5 0 0 1 5 5.5z"/><path d="M8 10h8M8 13h5"/>',
    volLow: '<path d="M4 9.5v5h3.5L12 18V6L7.5 9.5z"/><path d="M15.5 9.5a3.5 3.5 0 0 1 0 5"/>',
    volHigh: '<path d="M4 9.5v5h3.5L12 18V6L7.5 9.5z"/><path d="M15.5 9.5a3.5 3.5 0 0 1 0 5M18 7a7 7 0 0 1 0 10"/>',
    pip: '<rect x="3.5" y="5" width="17" height="14" rx="2"/><rect class="fill" x="12" y="12" width="6.5" height="5" rx="1"/>',
    thumbDown: '<path d="M7.5 13.5v-9M7.5 13.5l3.6 6.1a1.6 1.6 0 0 0 2.9-1.1l-.6-3.5h4.6a2 2 0 0 0 2-2.4l-1.3-6.5a2 2 0 0 0-2-1.6H7.5M7.5 4.5H5a1 1 0 0 0-1 1v7a1 1 0 0 0 1 1h2.5"/>',
    winMin: '<path d="M6.5 12h11"/>',
    winMax: '<rect x="6.5" y="6.5" width="11" height="11" rx="1.5"/>',
    winClose: '<path d="m7 7 10 10M17 7 7 17"/>',
    link: '<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/>',
    download: '<path d="M12 4.5v10M7.5 10.5 12 15l4.5-4.5M5 19.5h14"/>',
    copy: '<rect x="8.5" y="8.5" width="11" height="11" rx="2"/><path d="M15.5 8.5V6a1.5 1.5 0 0 0-1.5-1.5H6A1.5 1.5 0 0 0 4.5 6v8A1.5 1.5 0 0 0 6 15.5h2.5"/>',
    close: '<path d="m7 7 10 10M17 7 7 17"/>',
    check: '<path class="p-check" d="m5.5 12.5 4 4 9-9.5"/>',
    lock: '<rect x="5.5" y="10.5" width="13" height="9.5" rx="2"/><path d="M8.5 10.5V8a3.5 3.5 0 0 1 7 0v2.5"/>',
    eq: '<path d="M6 4.5v15M12 4.5v15M18 4.5v15"/><circle class="fill p-knob1" cx="6" cy="14" r="2.3"/><circle class="fill p-knob2" cx="12" cy="8" r="2.3"/><circle class="fill p-knob3" cx="18" cy="12.5" r="2.3"/>',
    bell: '<path d="M6.5 16.5V11a5.5 5.5 0 0 1 11 0v5.5l1.5 2H5z"/><path d="M10 20.5a2.2 2.2 0 0 0 4 0"/>',
    globe: '<circle cx="12" cy="12" r="8"/><path d="M4 12h16M12 4c2.2 2.3 3.2 5 3.2 8s-1 5.7-3.2 8c-2.2-2.3-3.2-5-3.2-8s1-5.7 3.2-8z"/>',
    external: '<path d="M13.5 4.5h6v6M19.5 4.5l-8 8M17 14v4.5a1 1 0 0 1-1 1H5.5a1 1 0 0 1-1-1V8a1 1 0 0 1 1-1H10"/>',
    trash: '<path d="M4.5 7h15M9.5 7V5h5v2M6.5 7l.8 12a1.5 1.5 0 0 0 1.5 1.4h6.4a1.5 1.5 0 0 0 1.5-1.4l.8-12"/>',
    refresh: '<path d="M19 12a7 7 0 1 1-2.1-5M19 4.5V8h-3.5"/>',
    info: '<circle cx="12" cy="12" r="8"/><path d="M12 11v5"/><circle class="fill" cx="12" cy="8" r="1.1"/>',
    palette: '<path d="M12 4a8 8 0 1 0 0 16c1.2 0 1.8-.8 1.8-1.7 0-1.3-1.2-1.6-1.2-2.8 0-1 .8-1.6 1.8-1.6H17a3.5 3.5 0 0 0 3-3.4C20 6.9 16.4 4 12 4z"/><circle class="fill" cx="8" cy="11" r="1.2"/><circle class="fill" cx="11" cy="7.8" r="1.2"/><circle class="fill" cx="15.3" cy="8.4" r="1.2"/>',
    sound: '<path d="M4 9.5v5h3.5L12 18V6L7.5 9.5z"/><path d="M15.5 9.5a3.5 3.5 0 0 1 0 5M18 7a7 7 0 0 1 0 10"/>',
    plug: '<path d="M9 4.5v4M15 4.5v4M6.5 8.5h11V12a5.5 5.5 0 0 1-11 0zM12 17.5v2.5"/>',
    user: '<circle cx="12" cy="8.5" r="3.5"/><path d="M5.5 19.5a6.5 6.5 0 0 1 13 0"/>',
    deep: '<path class="p-wave1" d="M4 7.5c2.7 2 5.3 2 8 0s5.3-2 8 0"/><path class="p-wave2" d="M4 12c2.7 2 5.3 2 8 0s5.3-2 8 0"/><path class="p-wave3" d="M4 16.5c2.7 2 5.3 2 8 0s5.3-2 8 0"/>',
    monitor: '<rect x="3.5" y="4.5" width="17" height="11.5" rx="1.8"/><path d="M9 20h6M12 16v4"/>',
    transfer: '<path d="M4.5 8.5h13M14 5l3.5 3.5L14 12M19.5 15.5h-13M10 12l-3.5 3.5L10 19"/>',
    zoomIn: '<circle cx="11" cy="11" r="6.5"/><path d="m16 16 4 4M8.5 11h5M11 8.5v5"/>',
    zoomOut: '<circle cx="11" cy="11" r="6.5"/><path d="m16 16 4 4M8.5 11h5"/>',
    target: '<circle cx="12" cy="12" r="7"/><circle class="fill" cx="12" cy="12" r="2"/><path d="M12 2.5V5M12 19v2.5M2.5 12H5M19 12h2.5"/>',
    clock: '<circle cx="12" cy="12" r="8"/><path d="M12 7.5V12l3 2"/>',
    note: '<circle cx="8" cy="17" r="2.6"/><path d="M10.6 17V5.5l8-1.5v10.5"/><circle cx="16" cy="14.5" r="2.6"/>',
    keyboard: '<rect x="3" y="6.5" width="18" height="11" rx="2"/><path d="M7 10h.01M10.5 10h.01M14 10h.01M17.5 10h.01M8 14h8"/>',
    disc: '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="2.2"/><path d="M12 6.5a5.5 5.5 0 0 0-5.5 5.5"/>',
    flame: '<path d="M12 20.5c3.6 0 6-2.4 6-5.7 0-4.3-4.2-6-4.5-10.3-2.6 1.6-4.1 4.2-4.1 6.5-1-.6-1.6-1.6-1.8-2.7C6.3 9.8 6 11.6 6 13.4c0 4.3 2.4 7.1 6 7.1z"/>',
    expand: '<path d="M14.5 4.5h5v5M9.5 19.5h-5v-5M19.5 4.5l-6 6M4.5 19.5l6-6"/>',
    hide: '<path d="M4 4l16 16M10.6 6.1A8.7 8.7 0 0 1 12 6c5 0 8.5 6 8.5 6a14.6 14.6 0 0 1-2.6 3.3M6.4 8A14.4 14.4 0 0 0 3.5 12S7 18 12 18a8 8 0 0 0 3.5-.8"/>',
    signal: '<path d="M4 18h2M9 18v-4M14 18V10M19 18V6"/>',
  })

  const icon = (name, cls = '') =>
    `<svg class="i i-${name} ${cls}" viewBox="0 0 24 24" aria-hidden="true">${ICONS[name] || ''}</svg>`

  // ── Обложки: геометрия в оттенках одного цвета ─────────────
  const tone = (c, dl, kc = 1) => `oklch(from ${c} clamp(0.1, calc(l + ${dl}), 0.97) calc(c * ${kc}) h)`

  const PATTERNS = {
    orbit: (c) =>
      `<circle cx="68" cy="34" r="40" style="fill:${tone(c, 0.14)}"/>` +
      `<circle cx="68" cy="34" r="23" style="fill:${tone(c, -0.1)}"/>` +
      `<circle cx="24" cy="77" r="9" style="fill:${tone(c, 0.32, 0.6)}"/>`,
    arcs: (c) =>
      [[92, 0.12], [70, 0], [48, -0.09], [26, 0.3]]
        .map(([r, d]) => `<circle cx="0" cy="100" r="${r}" style="fill:${tone(c, d)}"/>`)
        .join(''),
    split: (c) =>
      `<rect y="56" width="100" height="44" style="fill:${tone(c, -0.12)}"/>` +
      `<circle cx="50" cy="56" r="21" style="fill:${tone(c, 0.24, 0.7)}"/>`,
    grid: (c) => {
      const dots = []
      for (let y = 0; y < 7; y++) for (let x = 0; x < 7; x++)
        dots.push(`<circle cx="${11 + x * 13}" cy="${11 + y * 13}" r="1.7"/>`)
      return `<g style="fill:${tone(c, 0.42, 0.5)};opacity:.5">${dots.join('')}</g>` +
        `<circle cx="32" cy="70" r="28" style="fill:${tone(c, 0.18)}"/>`
    },
    bands: (c) =>
      `<g transform="rotate(-28 50 50)">` +
      [10, 38, 66, 94].map((y, i) =>
        `<rect x="-40" y="${y - 20}" width="180" height="14" style="fill:${tone(c, i % 2 ? -0.1 : 0.15)}"/>`).join('') +
      `</g>`,
    wave: (c) =>
      `<g style="fill:none;stroke:${tone(c, 0.3, 0.7)};stroke-width:2.6;stroke-linecap:round">` +
      [28, 41, 54, 67, 80].map((y) => `<path d="M-5 ${y}Q20 ${y - 11} 45 ${y}T95 ${y}T145 ${y}"/>`).join('') +
      `</g>`,
  }

  const cover = (color, pattern) =>
    `<svg class="art" viewBox="0 0 100 100" preserveAspectRatio="xMidYMid slice" aria-hidden="true">` +
    `<rect width="100" height="100" style="fill:${color}"/>${(PATTERNS[pattern] || PATTERNS.orbit)(color)}</svg>`

  const badge = (service) => {
    const s = S.data.SERVICES[service]
    if (!s) return ''
    const inner = service === 'file' ? icon('file') : s.short
    return `<span class="svc" title="${s.name}" aria-label="${s.name}">${inner}</span>`
  }

  const LOGO_PATH =
    'M244.1 917.6C244.4 917.3 251.9 915.7 260.7 914.0C336.9 899.8 417.1 875.8 476.5 849.5C558.3 813.3 619.4 767.3 654.0 715.7C671.2 690.1 681.9 661.6 685.0 633.2C686.8 617.5 685.8 595.7 683.0 586.0C671.0 544.5 630.9 504.6 560.5 464.0C548.4 457.1 506.8 435.7 492.5 429.2L483.5 425.1L497.5 425.1C529.0 424.9 580.9 428.1 613.0 432.1C703.1 443.3 761.6 466.9 796.5 506.0C841.5 556.5 830.9 619.4 765.9 687.4C705.1 751.1 629.7 803.6 541.8 843.3C455.5 882.4 357.3 908.2 266.0 916.0C259.1 916.6 251.3 917.3 248.5 917.6C245.8 917.9 243.8 917.9 244.1 917.6ZM258.1 847.6C258.3 847.4 265.5 846.0 274.0 844.6C365.5 829.0 447.9 797.3 506.7 755.2C551.1 723.4 589.3 681.0 615.0 635.2C618.4 629.0 621.5 624.0 621.8 624.0C622.8 624.0 620.9 639.1 618.5 648.6C615.4 661.7 611.3 672.5 603.6 688.4C593.0 710.1 581.0 726.4 563.5 742.8C505.4 797.1 406.3 833.1 279.6 846.0C258.1 848.2 257.5 848.2 258.1 847.6ZM485.0 597.9C366.7 592.9 284.2 570.4 240.9 531.3C186.8 482.5 186.4 424.2 239.8 357.3C260.5 331.4 302.5 292.2 338.3 265.2C454.9 177.6 607.3 121.0 762.5 107.6C778.9 106.2 784.3 106.2 776.4 107.5C763.4 109.8 734.7 115.7 717.6 119.6C548.3 158.5 426.0 224.8 370.0 308.3C352.8 333.9 342.1 362.4 339.0 390.8C337.2 406.5 338.2 428.3 341.0 438.0C353.0 479.5 393.1 519.4 463.5 560.0C475.6 566.9 517.2 588.3 531.5 594.8L540.5 598.9L522.0 598.8C511.8 598.7 495.2 598.3 485.0 597.9ZM402.4 392.6C403.2 383.4 406.9 368.0 411.0 357.1C415.3 345.3 425.9 323.9 431.7 315.0C474.7 249.5 574.6 201.5 707.0 182.5C727.1 179.7 765.0 175.7 765.7 176.4C766.0 176.6 764.0 177.2 761.3 177.5C750.5 179.1 723.5 184.4 707.0 188.2C620.0 208.3 549.3 241.0 494.3 286.4C462.1 313.1 429.5 352.2 409.0 388.8C405.6 395.0 402.5 400.0 402.2 400.0C402.0 400.0 402.0 396.7 402.4 392.6Z'

  const logo = (cls = '') =>
    `<svg class="logo ${cls}" viewBox="196 102 632 820" aria-label="Sonar" role="img"><path fill="currentColor" fill-rule="evenodd" d="${LOGO_PATH}"/></svg>`

  const fmt = (sec) => {
    const s = Math.max(0, Math.floor(sec))
    return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`
  }

  S.icon = icon
  S.icons = ICONS
  S.cover = cover
  S.badge = badge
  S.logo = logo
  S.fmt = fmt
})(window.Sonar)
