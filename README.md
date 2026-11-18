<div align="center">

<img src="brand/logo.svg" width="96" alt="Sonar" />

# Sonar

**SoundCloud и Яндекс Музыка в одном плеере.**
Свои Любимые и смешанные плейлисты, своя волна, тексты с караоке, интерфейс под цвет обложки.

![Windows](https://img.shields.io/badge/Windows-0.1-0078D4?style=flat-square&logo=windows)
![iOS](https://img.shields.io/badge/iOS-18%2B%20·%20бета-black?style=flat-square&logo=apple)
![Tauri](https://img.shields.io/badge/Tauri%202-Rust%20%2B%20Svelte%205-FFC131?style=flat-square&logo=tauri&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-SwiftUI-F05138?style=flat-square&logo=swift&logoColor=white)
![Server](https://img.shields.io/badge/сервер-скоро-555?style=flat-square&logo=python&logoColor=white)

[Скачать для Windows](https://github.com/folzy1092/Sonar/releases/latest/download/Sonar-setup.exe) ·
[IPA для iPhone](https://github.com/folzy1092/Sonar/releases/download/ios-latest/Sonar.ipa) ·
[Сайт](https://sonar.folzy.ru) · [Новости](https://t.me/SonarUpdates) · [Документация](docs/)

</div>

---

## Что умеет

| | |
|---|---|
| 🎧 **Два сервиса — одна очередь** | треки SoundCloud и Яндекса вперемешку, качество до FLAC |
| ❤️ **Свои Любимые и плейлисты** | смешанные плейлисты, перенос плейлистов из сервисов в один клик |
| 🌊 **Моя волна** | своя, на твоих лайках, пропусках и дослушанном; шесть настроений, работает без сети |
| 🎤 **Тексты песен** | lrclib → NetEase → Genius, караоке по словам, перевод, аннотации |
| 🎨 **Вид под тебя** | тема под обложку, готовые стили, раскладки вкладок и плеера, анимации везде |
| 🎛️ **Звук** | эквалайзер, кроссфейд, нормализация громкости, скорость Slowed / Sped up |
| 🌙 **Мелочи** | таймер сна, мини-окно поверх всех, горячие клавиши, Discord, OBS, трей |
| 📊 **Статистика** | день, неделя, месяц, год — минуты, любимые треки и артисты |
| 🔄 **Автообновление** | на ПК и на iPhone новая версия ставится прямо из приложения |

## Установка

**Windows 10 / 11** — скачай [Sonar-setup.exe](https://github.com/folzy1092/Sonar/releases/latest/download/Sonar-setup.exe)
и запусти. Дальше Sonar обновляется сам.

**iPhone (iOS 18+)** — скачай [Sonar.ipa](https://github.com/folzy1092/Sonar/releases/download/ios-latest/Sonar.ipa)
и подпиши своей парой сертификата (ESign, Feather). Потом укажи ту же пару в
«Профиль → Система → Обновления → Сертификат» — и обновления будут ставиться из приложения.

Подключение сервисов — в «Настройки → Сервисы»: SoundCloud и Яндекс Музыка, вход в один клик или своим ключом.
Ключи хранятся только на твоём устройстве.

## Что дальше

YouTube Music, VK Музыка и Spotify; резерв — трек сам играет из другого сервиса, если в одном недоступен;
импорт плейлиста по любой ссылке, умные плейлисты, итоги месяца и года, локальные файлы, пульт с iPhone.
Задание — [docs/NEXT_PROMPT.md](docs/NEXT_PROMPT.md), план — [docs/ROADMAP.md](docs/ROADMAP.md).
Потом — свой сервер: аккаунт, синхронизация между устройствами, бот [@SonarMusicApp](https://t.me/SonarMusicApp).

## Устройство репозитория

```
windows/   ПК-клиент: Tauri 2 (Rust) + Svelte 5
ios/       iPhone-клиент: SwiftUI, проект из XcodeGen
server/    Python: API и Telegram-бот (ждёт хостинга)
site/      sonar.folzy.ru
docs/      ТЗ, спека, API, база, настройки, карта проекта
brand/     знак Sonar и знаки сервисов
updates/   объявления обновлений для приложений
```

Подробная карта — [docs/MAP.md](docs/MAP.md). Сборки собирает GitHub Actions: каждый пуш в `main`
выпускает релиз, ветка `dev` — только тесты и сборка.

## Безопасность

Код открыт для чтения, чтобы было видно, что внутри нет ловушек.
Ключи сервисов лежат в системном хранилище (Windows Credential Manager, Keychain на iPhone) и в
логи не пишутся. На сервере пароли будут храниться только в виде argon2-хэша, токены — зашифрованы.
Подробно — [docs/SPEC.md](docs/SPEC.md#6-безопасность).

## Лицензия

Проприетарная, все права защищены. Можно скачать официальную сборку и пользоваться ею.
Копировать, изменять и использовать код где-либо ещё — нельзя. Подробно — [LICENSE](LICENSE).
