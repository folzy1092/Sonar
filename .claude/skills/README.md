# Навыки агента для Sonar

Claude Code сам подхватывает навыки из `.claude/skills/` проекта: склонировал репо — они уже есть, ставить ничего
не надо. Вызвать — `/имя` (например, `/ponytail-audit`) или просто попросить словами («сделай аудит», «приведи
экран в порядок»). Добавлены 2026-11-21, отобраны под Sonar из четырёх наборов.

| Навык | Когда | Откуда |
|---|---|---|
| `unslop` | экран выглядит «сгенерированным» — довести отступы, цвет, иконки, текст, шрифты, движение («не слопно») | [heydamir/unslop](https://github.com/heydamir/unslop), CC BY 4.0 |
| `ponytail-audit` | аудит всего репо: баги, дыры, нагрузка, код без тестов, лишнее. Последний — `docs/AUDIT.md` | [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail), MIT |
| `ponytail-review` | ревью изменения перед пушем в `main`, с чтением связанного кода | там же |
| `ponytail` | режим «самая маленькая правка, которая решает задачу» | там же |
| `debugging-and-error-recovery` | баг или красный тест — искать причину по шагам, а не гадать | [slicksys/AgentSkills](https://github.com/slicksys/AgentSkills), MIT |
| `performance-optimization` | тормоза: замерить, найти узкое место, проверить, что стало быстрее | там же |
| `security-and-hardening` | сервер, вход, токены сервисов, API — всё, что принимает чужие данные | там же |
| `graphify` | граф кода всего монорепо: что с чем связано (`/graphify .`) | [Graphify-Labs/graphify](https://github.com/Graphify-Labs/graphify), Apache-2.0 / MIT |

`graphify` — единственный, которому нужна программа: `uv tool install graphifyy` (или `pipx install graphifyy`).
`graphify install` и `graphify claude install` **не запускать**: навык уже лежит здесь, а они дописывают свои
строки в CLAUDE.md и ставят хук. Результат — в `graphify-out/` (в `.gitignore`).

Хуки этих наборов (`ponytail`, `AgentSkills`) сюда не перенесены: они встраиваются в каждую сессию.

**Лицензии.** У каждой папки — лицензия её автора (`LICENSE` рядом с `SKILL.md`), она касается только этой
папки. Код Sonar остаётся под проприетарной лицензией из корневого `LICENSE`. Обновить навык — скачать заново из
источника и заменить папку целиком, не правя внутри: так проще сверяться с автором.
