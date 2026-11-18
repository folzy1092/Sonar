import type { APIRoute } from 'astro'
import { SITE_URL } from '../config'
import { sitemapXml } from '../lib/sitemap'

export const GET: APIRoute = () =>
  new Response(sitemapXml(SITE_URL), { headers: { 'Content-Type': 'application/xml; charset=utf-8' } })
