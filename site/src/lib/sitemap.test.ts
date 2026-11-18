import { describe, expect, test } from 'vitest'
import { SITEMAP_PATHS, sitemapXml } from './sitemap'

describe('sitemapXml', () => {
  const xml = sitemapXml('https://sonar.folzy.ru')

  test('каждая страница — на трёх языках', () => {
    expect(xml.match(/<url>/g)).toHaveLength(SITEMAP_PATHS.length * 3)
    expect(xml).toContain('<loc>https://sonar.folzy.ru/</loc>')
    expect(xml).toContain('<loc>https://sonar.folzy.ru/en/pay</loc>')
    expect(xml).toContain('<loc>https://sonar.folzy.ru/uk/faq</loc>')
  })

  test('у страницы есть hreflang-альтернативы и x-default', () => {
    expect(xml).toContain('hreflang="uk" href="https://sonar.folzy.ru/uk/terms"')
    expect(xml).toContain('hreflang="x-default" href="https://sonar.folzy.ru/terms"')
  })

  test('без 404 и профилей', () => {
    expect(xml).not.toMatch(/404|\/@/)
  })
})
