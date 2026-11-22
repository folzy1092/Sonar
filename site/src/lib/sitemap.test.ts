import { describe, expect, test } from 'vitest'
import { LANGS } from '../i18n'
import { SITEMAP_PATHS, sitemapXml } from './sitemap'

describe('sitemapXml', () => {
  const xml = sitemapXml('https://try-sonar.ru')

  test('каждая страница — на всех языках', () => {
    expect(xml.match(/<url>/g)).toHaveLength(SITEMAP_PATHS.length * LANGS.length)
    expect(xml).toContain('<loc>https://try-sonar.ru/</loc>')
    expect(xml).toContain('<loc>https://try-sonar.ru/en/pay</loc>')
    expect(xml).toContain('<loc>https://try-sonar.ru/uk/faq</loc>')
    expect(xml).toContain('<loc>https://try-sonar.ru/pl/faq</loc>')
  })

  test('у страницы есть hreflang-альтернативы и x-default', () => {
    expect(xml).toContain('hreflang="uk" href="https://try-sonar.ru/uk/terms"')
    expect(xml).toContain('hreflang="de" href="https://try-sonar.ru/de/terms"')
    expect(xml).toContain('hreflang="x-default" href="https://try-sonar.ru/terms"')
  })

  test('без 404 и профилей', () => {
    expect(xml).not.toMatch(/404|\/@/)
  })
})
