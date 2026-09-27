# Private signer API v1

`GET /health` возвращает `{ "status": "ready" }` или `{ "status": "unconfigured" }`. Никаких подробностей сертификатов или секретов. CLI preflight не запускает сервер с неверной конфигурацией; фабрика ASGI-приложения сохраняет безопасное поведение 503 при неправильной настройке.

`POST /v1/passes` — HTTPS, `Authorization: Bearer <installation-token>`, `Content-Type: application/json`. Тело:

```json
{
  "metadata": "<точная UTF-8 JSON-строка ExportMetadata>",
  "imageBase64": null,
  "contentHash": "<lowercase SHA-256>"
}
```

Хеш: `SHA256(metadataUTF8 + byte(0) + decodedImageBytes)`. При отсутствии фотографии image bytes пустые. После вычисления хеша нельзя повторно сериализовать внутренний объект с другими пробелами/порядком ключей; сервер проверяет именно исходную строку. Внешний JSON может быть сериализован любым корректным способом.

Metadata: `schemaVersion=1`, `id` (канонический lowercase UUID), `revision` (целое от 1 до 2^63−2), `template` (`photo`, `information`, `mixed`), `title`, `caption` (optional), `fields` (array ID/label/value), `theme` (`ocean`, `forest`, `plum`, `sand`), `includesImage` (Boolean). Типы строгие; неизвестные свойства и повторные JSON-ключи отклоняются.

Название до 60 Unicode scalars, подпись 500, до 10 полей; label 40, value 2000. Photo требует изображение и пустой fields; information требует поля и исключает caption/image; mixed требует оба. NUL и непарные surrogate недопустимы. Файл может быть не более 5 MiB, metadata — 64 KiB, изображение — статичный JPEG/PNG до 4 MP и 4096 по стороне; клиент экспортирует максимум 1600 по стороне.

Успех: HTTP 200, `application/vnd.apple.pkpass`, `Cache-Control: no-store`. Сервер выбирает идентичность и строит известные assets: generic, опционально posterGeneric, icon/thumbnail/artwork, manifest и signature. Клиент не управляет путями, certificate ID и issuer.

Ошибки имеют форму `{ "error": { "code": "invalid_request" } }`, без исходных значений. Основные статусы: 401 авторизация; 413 лимит; 415 Content-Type/Encoding; 422 валидация/hash/image; 429 занято/лимит; 503 сертификат/конфигурация; 500 обезличенная внутренняя ошибка. В первой версии нет серверного хранилища карточек, idempotency cache, пользователя/регистрации и Wallet push-webservice.
