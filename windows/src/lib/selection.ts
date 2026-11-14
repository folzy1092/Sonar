// Клик по выделяемому тексту не должен никуда уводить, если человек только что выделял его мышью.
export const hasSelection = () => (window.getSelection()?.toString() ?? '').length > 0
