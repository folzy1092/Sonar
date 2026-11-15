// CI (windows.yml): собирает latest.json для tauri-plugin-updater из подписанного установщика NSIS.
// Заметки берутся из updates/changelog.json (запись этой версии), иначе из env RELEASE_NOTES. Запуск из windows/:
//   node scripts/latest-json.mjs <tag> > latest.json
import { readFileSync, readdirSync } from 'node:fs'
import { join } from 'node:path'

const tag = process.argv[2]
if (!tag) throw new Error('нужен тег релиза, например windows-v0.1.0')

const conf = JSON.parse(readFileSync('src-tauri/tauri.conf.json', 'utf8'))
const version = conf.version
const dir = process.env.NSIS_DIR ?? 'src-tauri/target/release/bundle/nsis'
const exe = readdirSync(dir).find((f) => f.endsWith('-setup.exe') && f.includes(version))
if (!exe) throw new Error(`нет установщика ${version} в ${dir}`)
const signature = readFileSync(join(dir, `${exe}.sig`), 'utf8').trim()

let notes = ''
try {
  const log = JSON.parse(readFileSync('../updates/changelog.json', 'utf8'))
  const entry = log.find((e) => e.version === version && (!e.platform || e.platform === 'windows'))
  if (entry) notes = entry.changes.map((c) => `- ${c}`).join('\n')
} catch {
  // без заметок — клиент покажет «Описание обновления отсутствует»
}
// авто-версия из CI (нет записи в changelog) — сообщения коммитов с прошлого релиза
if (!notes && process.env.RELEASE_NOTES) notes = process.env.RELEASE_NOTES.trim()

const asset = exe.replaceAll(' ', '.')
const out = {
  version,
  notes,
  pub_date: new Date().toISOString(),
  platforms: {
    'windows-x86_64': {
      signature,
      url: `https://github.com/folzy1092/Sonar/releases/download/${tag}/${asset}`,
    },
  },
}
process.stdout.write(JSON.stringify(out, null, 2) + '\n')
