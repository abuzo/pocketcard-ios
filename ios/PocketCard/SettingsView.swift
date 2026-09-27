import SwiftUI
import PocketCardCore

@MainActor
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var baseURL = ""
    @State private var operatorName = ""
    @State private var token = ""
    @State private var previous: SignerConfiguration?
    @State private var error: UserMessage?
    @State private var deleting = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Ваши карточки — на вашем iPhone",systemImage:"iphone")
                    Text("PocketCard хранит текст и рабочие копии фото в закрытой папке приложения. Интернет требуется только для выпуска в Wallet.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section("Личный сервис выпуска") {
                    TextField("https://passes.example.com",text:$baseURL).keyboardType(.URL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Кто управляет сервисом",text:$operatorName)
                    SecureField(previous == nil ? "Токен установки" : "Новый токен — необязательно",text:$token)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                    if previous != nil { Text("Токен уже сохранён в Keychain этого iPhone.").font(.caption).foregroundStyle(.secondary) }
                    Text("Только HTTPS, без пути и параметров. При смене адреса введите токен заново. Сохранение настроек не отправляет карточки.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Настройка сборки") {
                    LabeledContent("Team ID",value:BuildIdentity.teamIdentifier.isEmpty ? "Не задан" : BuildIdentity.teamIdentifier)
                    VStack(alignment:.leading,spacing:7) {
                        Text("Pass Type ID").font(.caption).foregroundStyle(.secondary)
                        Text(verbatim:BuildIdentity.passTypeIdentifier.isEmpty ? "Не задан" : BuildIdentity.passTypeIdentifier).font(.footnote).textSelection(.enabled)
                    }
                    Label(BuildIdentity.isConfigured ? "Настройки Wallet указаны" : "Wallet требует настройки в Xcode",systemImage:BuildIdentity.isConfigured ? "checkmark.circle" : "wrench.and.screwdriver")
                    Text("Инструкция: docs/SETUP.md. Эти значения должны совпадать с сертификатом сервиса. Приложение не хранит закрытый ключ подписи.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Хранение и конфиденциальность") {
                    Text("Файлы защищены системной защитой iOS при блокировке устройства. Отдельного входа по Face ID в этой версии нет.")
                    Text("Собственной iCloud-синхронизации нет. Данные приложения могут входить в системную резервную копию iPhone согласно настройкам устройства. Удаление приложения удаляет локальные карточки.")
                    Text("Копия в Wallet независима: удаление карточки в PocketCard не удаляет её из Wallet. Скрытие кнопки «Поделиться» не шифрует содержимое pass.")
                    Text("Открытые экраны прикрываются в переключателе приложений. Обычные снимки экрана не блокируются.")
                }.font(.footnote)
                if previous != nil {
                    Section { Button("Удалить настройки сервиса",role:.destructive) { deleting = true } }
                }
                Section { Text("PocketCard 0.1 · Личная тестовая версия").font(.caption).foregroundStyle(.secondary) }
            }
            .navigationTitle("Настройки").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Закрыть") { dismiss() } }
                ToolbarItem(placement:.confirmationAction) { Button("Сохранить",action:save) }
            }
            .task {
                do {
                    previous = try model.configurationStore.load()
                    if let previous { baseURL = previous.baseURL; operatorName = previous.operatorName }
                } catch { self.error = model.message(for:error) }
            }
            .alert(item:$error) { Alert(title:Text($0.title),message:Text($0.text),dismissButton:.default(Text("Понятно"))) }
            .confirmationDialog("Удалить настройки сервиса?",isPresented:$deleting,titleVisibility:.visible) {
                Button("Удалить",role:.destructive) {
                    do { try model.configurationStore.delete(); previous = nil; baseURL = ""; operatorName = ""; token = "" }
                    catch { self.error = model.message(for:error) }
                }
            } message: { Text("Локальные карточки останутся. Для нового выпуска потребуется снова указать адрес и токен.") }
        }
    }
    private func save() {
        do {
            let endpoint = try SignerEndpoint(baseURL)
            let url = endpoint.baseURL.absoluteString
            let newToken: String
            if token.isEmpty, let previous, (try? SignerEndpoint(previous.baseURL).baseURL) == endpoint.baseURL {
                newToken = previous.token
            } else {
                guard !token.isEmpty else { throw PocketCardError.validation("Для нового адреса введите токен сервиса.") }
                newToken = token
            }
            let configuration = SignerConfiguration(baseURL:url,operatorName:operatorName.trimmed,token:newToken)
            try model.configurationStore.save(configuration)
            token = ""; dismiss()
        } catch { self.error = model.message(for:error) }
    }
}
