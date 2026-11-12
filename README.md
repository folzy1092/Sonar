<div align="center">

# Sonar

**SoundCloud и Яндекс Музыка в одном плеере.**
Свои лайки и смешанные плейлисты, своя волна, статистика, интерфейс под цвет обложки.

![iOS](https://img.shields.io/badge/iOS-18%2B-black?style=flat-square&logo=apple)
![Swift](https://img.shields.io/badge/Swift-SwiftUI-F05138?style=flat-square&logo=swift&logoColor=white)
![Python](https://img.shields.io/badge/server-Python%203.13-3776AB?style=flat-square&logo=python&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-скоро-555?style=flat-square&logo=windows)
![Status](https://img.shields.io/badge/статус-проектирование-00D7E0?style=flat-square)

[Скачать](https://github.com/folzy1092/Sonar/releases) · [Сайт](https://sonar.folzy.is-a.dev) · [Документация](docs/)

</div>

---

## Что внутри

| | |
|---|---|
| 🎧 **Два сервиса — одна очередь** | треки SoundCloud и Яндекса играют вперемешку |
| ❤️ **Свои Любимые и плейлисты** | хранятся в Sonar, синхронизируются между устройствами |
| 🌊 **Моя волна** | подстраивается под лайки, пропуски и то, что дослушиваешь |
| 🎨 **Тема под обложку** | весь интерфейс перекрашивается в цвет играющего трека |
| 📊 **Статистика** | неделя, месяц, год — минуты, любимые артисты |
| 🔄 **Автообновление** | новая версия ставится из приложения, без компьютера |

## Устройство репозитория

```
docs/      ТЗ, спека, API, база, настройки, карта проекта
server/    Python: API + Telegram-бот входа
ios/       SwiftUI-приложение
windows/   Rust-клиент (позже)
site/      sonar.folzy.is-a.dev
updates/   объявления обновлений для приложения
```

Подробная карта — [docs/MAP.md](docs/MAP.md), план — [docs/ROADMAP.md](docs/ROADMAP.md).

## Безопасность

Код открыт для чтения, чтобы было видно, что внутри нет ловушек.
Пароли хранятся только в виде argon2-хэша, токены сервисов — зашифрованы на сервере,
в логи не пишутся. Подробно — [docs/SPEC.md](docs/SPEC.md#6-безопасность).

## Лицензия

Проприетарная, все права защищены. Можно скачать официальную сборку и пользоваться ею.
Копировать, изменять и использовать код где-либо ещё — нельзя. Подробно — [LICENSE](LICENSE).
