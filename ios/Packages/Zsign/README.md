# Zsign

Сторонний код: [zsign](https://github.com/zhlynn/zsign) (MIT, `LICENSE`) — подпись `.app` прямо на
iPhone. Взят из Shadow (`third-party/zsign`, основа — `khcrysalis/Zsign-Package`, коммит `c4ba9da`):
только части Mach-O, бандла и подписи кода.

Отличия от upstream (сделаны в Shadow, переносим как есть):
- `openssl.cpp` заменён на `openssl_apple.mm` — сертификат и ключ из `.p12` через Security.framework,
  подпись `SecKey`, CMS SignedData собирается вручную; OpenSSL не нужен вовсе;
- `pkcs12_apple.mm` — свой разбор `.p12`, которые iOS не открывает сама (экспорт OpenSSL 3: PBES2/AES,
  MAC на SHA-256);
- `shim/openssl/sha.h` — SHA из CommonCrypto.

Изменено в Sonar: `bundle.cpp`, `GenerateCodeResources` — условие удаления `embedded.mobileprovision`
было перевёрнуто относительно остального кода (`bRemoveProvision = true` в этом форке значит «положить
профиль»), и профиль, записанный в `SignFolder`, тут же удалялся. Теперь он остаётся и запечатан в
`CodeResources` (проверяет `SigningTests.testSignsDummyApp`).

Своё в Sonar — только обёртка `ZsignSigner` (`include/Zsign/ZsignSigner.h`, `ZsignSigner.mm`):
`sign(appPath:provisionPath:p12Path:password:)` и `check(...)`, ошибки — текстом по-русски.
