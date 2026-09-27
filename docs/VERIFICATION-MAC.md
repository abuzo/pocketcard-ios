# Проверка на Mac — 27 сентября 2026

## Результат

Локальный сценарий фотокарточки работает в симуляторе. Выпуск в Apple Wallet с настоящим сертификатом Apple и готовность к App Store ещё не подтверждены.

Среда: macOS arm64, Xcode 26.6 (17F113), iOS SDK 26.5, iPhone 16 Pro Simulator iOS 18.5, Python 3.14.4.

| Проверка | Результат |
|---|---|
| Swift core `swift test` | 23 прошли |
| Signer `pytest -q signer/tests` | 52 прошли; предупреждение устаревшего alias AnyIO в Starlette |
| Структура проекта `unittest discover -s scripts/tests -v` | 4 прошли |
| Генератор `generate_xcode_project.py --check` | Совпадает с проектом |
| Swift → Python wire contract | Все 3 шаблона прошли |
| Debug build, generic iOS Simulator | BUILD SUCCEEDED |
| Обычная Debug build с подписью Xcode для Simulator | BUILD SUCCEEDED |
| Нативные XCTest | 7 прошли, 1 пропущен, 0 ошибок; TEST SUCCEEDED |
| UI smoke test | Импорт стандартного фото водопада из Photos, название Photo test 0001, сохранение, перезапуск, открытие карточки и предпросмотра |

## Исправления при проверке

- `CardEditorView`: текст кнопки выбора фото вычисляется на MainActor перед передачей в Sendable closure. Предупреждение actor isolation устранено; поведение не изменено.
- `RepositoryProtectionTests`: проверка `NSFileProtectionComplete` явно пропускается только при `targetEnvironment(simulator)`. На настоящем устройстве assertion сохранён. Первый запуск показал nil вместо атрибута защиты; это не доказательство ошибки записи приложения. Нельзя считать защиту файлов проверенной до запуска на iPhone. Аналогичное ограничение описано в [Apple Developer Forums](https://developer.apple.com/forums/tags/apfs?page=2).

## Особенности локальной среды

Оболочка simctl в Xcode ожидает CoreSimulator 1051.55, установлен CoreSimulator 1155.4. Она зависала в `xcodebuild -runFirstLaunch`. Для этой проверки использовался установленный бинарник `/Library/Developer/PrivateFrameworks/CoreSimulator.framework/Versions/A/Resources/bin/simctl`; файлы Xcode не менялись. Перед обычным использованием следует согласовать установку Xcode/CoreSimulator.

Неподписанная сборка (`CODE_SIGNING_ALLOWED=NO`) запускалась, но показывала ошибку чтения Keychain в предпросмотре. Обычная подписанная симуляторная сборка устранила эту ошибку. Для ручной проверки используйте обычный Run в Xcode. Для воспроизведения нативных тестов:

```sh
xcodebuild -project ios/PocketCard.xcodeproj -scheme PocketCard \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  -derivedDataPath .build/DerivedData -parallel-testing-enabled NO \
  -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO test
```

Локальный результат XCTest: `.build/DerivedData/Logs/Test/Test-PocketCard-2026.09.27_15-30-11-+0300.xcresult`. Артефакты сборки и пользовательские данные не коммитятся. В симуляторе оставлена тестовая фотокарточка.

## Следующие шаги перед выпуском

1. Настроить собственные Bundle ID, Apple Developer Team, Pass Type ID и сертификат подписи; значения вынесены в `ios/Local.xcconfig.example` и `.env.example`.
2. Развернуть HTTPS signer и определить модель авторизации публичного приложения: текущая реализация рассчитана на личную установку с одним токеном.
3. На физическом iPhone проверить настоящий выпуск, отмену/добавление/обновление Wallet pass, защиту файлов при блокировке и отображение фото на поддерживаемых версиях iOS.
4. Пройти полный сценарный список из `VERIFICATION.md`, включая Files, кадрирование, копирование/удаление, все шаблоны, VoiceOver и Dynamic Type. Текущий smoke test этот список не заменяет.
5. Подготовить App Store Connect, privacy/support URL, скриншоты, метаданные, архив с distribution signing и TestFlight. Отдельно проверить применимость карточек и актуальные требования Apple.
6. Проверить результат GitHub Actions после отправки; локальный запуск не подтверждает прохождение CI.

Исторический Linux-отчёт: [VERIFICATION.md](VERIFICATION.md).
