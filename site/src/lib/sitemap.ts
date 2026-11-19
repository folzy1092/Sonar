// sitemap.xml: каждая страница на всех языках сайта, с hreflang-альтернативами (robots.txt ссылается сюда).
import { LANGS, href } from '../i18n'

/** Страницы для поисковиков; 404 и профили `/@…` сюда не входят. */
export const SITEMAP_PATHS = [
  '/',
  '/download',
  '/pay',
  '/faq',
  '/status',
  '/privacy',
  '/terms',
  '/subscription',
  '/delete',
  '/licenses',
] as const

const abs = (site: string, path: string) => new URL(path, site).href

export function sitemapXml(site: string, paths: readonly string[] = SITEMAP_PATHS): string {
  const urls = paths.flatMap((path) => {
    const alternates = [
      ...LANGS.map((l) => `<xhtml:link rel="alternate" hreflang="${l}" href="${abs(site, href(l, path))}"/>`),
      `<xhtml:link rel="alternate" hreflang="x-default" href="${abs(site, href('ru', path))}"/>`,
    ].join('')
    return LANGS.map((lang) => `<url><loc>${abs(site, href(lang, path))}</loc>${alternates}</url>`)
  })
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">',
    ...urls,
    '</urlset>',
    '',
  ].join('\n')
}
