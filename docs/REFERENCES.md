# Первичные технические источники

Проверены при подготовке исходников 27 сентября 2026. Ссылки подтверждают устройство платформы, а не прохождение тестов этой конкретной сборкой.

- Apple — Creating a poster generic pass: https://developer.apple.com/documentation/walletpasses/creating-a-poster-generic-pass — Poster Generic для iOS/watchOS 27 и совместное наличие generic fallback.
- Apple — Wallet Human Interface Guidelines: https://developer.apple.com/design/human-interface-guidelines/wallet — artwork и ограничения компоновки.
- Apple — PassKit Programming Guide, Creating a Pass: https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/PassKit_PG/Creating.html — пакет, manifest, assets и подпись.
- Apple — Wallet identifiers and certificates: https://developer.apple.com/help/account/capabilities/create-wallet-identifiers-and-certificates/ — идентичность издателя.
- Apple PKI: https://www.apple.com/certificateauthority/ — официальные сертификаты; выбирайте цепочку вашего pass-сертификата.
- Apple — pass-type-identifiers entitlement: https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.pass-type-identifiers — доступ к библиотеке.
- Apple — PKPassLibrary: https://developer.apple.com/documentation/passkit/pkpasslibrary — операции и ограничение одного потока.
- Apple — replacePass(with:): https://developer.apple.com/documentation/passkit/pkpasslibrary/replacepass(with:) — обновление по Pass Type ID и serial number.
- Apple — PKPassLibraryDidChange: https://developer.apple.com/documentation/passkit/pkpasslibrarynotificationname/pkpasslibrarydidchange — уведомления и необходимость живого экземпляра библиотеки.
- Apple — Required reason API types: https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype — C617.1 и 3B52.1 для своих/выбранных файлов.
- Apple — App Review Guidelines, 3.2.1(iv): https://developer.apple.com/app-store/review/guidelines/ — допустимые назначения Wallet. Конструктор произвольных фото/заметок требует отдельной оценки App Review.
- cryptography — PKCS7: https://cryptography.io/en/latest/hazmat/primitives/asymmetric/serialization/#pkcs7 — detached CMS.
- FastAPI: https://fastapi.tiangolo.com/ — ASGI и обработка ответов.
- GitHub — Building and testing Python: https://docs.github.com/en/actions/tutorials/build-and-test-code/python — структура CI; workflow в этой поставке не запускался на GitHub.
