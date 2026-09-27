import SwiftUI
import PocketCardCore

@MainActor
struct WalletPreviewView: View {
    let card: Card
    let source: Data?
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var wallet: WalletCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var mode: PreviewMode = .classic
    @State private var configuration: SignerConfiguration?
    @State private var settings = false
    @State private var consent = false
    @State private var issueTask: Task<Void,Never>?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if card.template.usesImage {
                        Picker("Отображение",selection:$mode) {
                            Text("Классический").tag(PreviewMode.classic)
                            Text("iOS 27+").tag(PreviewMode.poster)
                        }.pickerStyle(.segmented)
                    }
                    CardPreview(card:card,sourceData:source,mode:mode)
                        .listRowInsets(EdgeInsets(top:14,leading:0,bottom:14,trailing:0)).listRowBackground(Color.clear)
                } footer: {
                    Text("Это ориентировочный предпросмотр. Wallet определяет конечную компоновку. На iOS 27+ фотокарточка использует Poster Generic; на более ранних версиях — миниатюру. Значения длиннее 80 символов доступны в подробностях.")
                }
                Section("Будет передано и добавлено в Wallet") {
                    dataRow("Название",card.title)
                    if card.template.usesImage {
                        Label("Подготовленная фотография без исходных геометок",systemImage:"photo")
                        if !card.caption.isEmpty { dataRow("Подпись",card.caption) }
                    }
                    if card.template.usesFields {
                        ForEach(card.fields) { field in dataRow(field.label,field.value) }
                    }
                    Text("В технические данные входят ID карточки, версия, тема и контрольная сумма. Скрытые поля и исходное фото не передаются.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Сервис выпуска") {
                    if let configuration {
                        LabeledContent("Оператор",value:configuration.operatorName)
                        Text(verbatim:configuration.baseURL).font(.footnote).textSelection(.enabled)
                    } else {
                        Text("Адрес и токен ещё не настроены. Карточки можно сохранять без сервиса.").font(.subheadline)
                    }
                    Button("Настроить сервис",systemImage:"gearshape") { settings = true }.disabled(wallet.isIssuing)
                    if !BuildIdentity.isConfigured {
                        Text("Для Wallet нужно настроить Team ID, Pass Type ID и entitlement в Xcode. Инструкция находится в docs/SETUP.md проекта.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Label("Wallet — не сейф для паролей",systemImage:"lock.open")
                    Text("Подпись подтверждает целостность файла, но не шифрует его содержимое. Сервис увидит отправленные данные во время выпуска. Не добавляйте банковские пароли и коды восстановления.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if wallet.isIssuing {
                        ProgressView("Выпускаем карточку…")
                        Button("Отменить выпуск",role:.cancel) { issueTask?.cancel() }
                    } else {
                        Button {
                            consent = true
                        } label: {
                            Label(wallet.status(for:model.card(card.id) ?? card) == .changed ? "Обновить в Wallet" : "Выпустить для Wallet",systemImage:"wallet.pass")
                                .frame(maxWidth:.infinity).padding(.vertical,8)
                        }.buttonStyle(.borderedProminent)
                            .disabled(configuration == nil || !BuildIdentity.isConfigured)
                    }
                    if let notice = wallet.notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
                    Text(wallet.status(for:model.card(card.id) ?? card).rawValue).font(.caption.weight(.semibold))
                }
            }
            .navigationTitle("Перед добавлением").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Закрыть") { dismiss() }.disabled(wallet.isIssuing) } }
            .interactiveDismissDisabled(wallet.isIssuing)
            .task {
                loadConfiguration()
                mode = card.template.usesImage && ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 ? .poster : .classic
                wallet.refresh()
            }
            .sheet(isPresented:$settings,onDismiss:loadConfiguration) { SettingsView() }
            .sheet(item:$wallet.pendingPass,onDismiss:{wallet.refresh()}) { presentation in
                WalletAddSheet(pass:presentation.pass,onFinish:wallet.sheetFinished)
            }
            .confirmationDialog("Передать данные сервису?",isPresented:$consent,titleVisibility:.visible) {
                Button("Продолжить") {
                    guard let configuration else { return }
                    issueTask = Task { await wallet.issue(card:card,model:model,configuration:configuration) }
                }
                Button("Отмена",role:.cancel) {}
            } message: {
                Text("Текст и подготовленное фото получит \(configuration?.operatorName ?? "оператор сервиса") по адресу \(configuration?.baseURL ?? ""). Сервис получает доступ к ним во время обработки. Карточка Wallet не является защищённым хранилищем паролей.")
            }
            .alert(item:$wallet.message) { Alert(title:Text($0.title),message:Text($0.text),dismissButton:.default(Text("Понятно"))) }
        }
    }
    private func dataRow(_ label: String, _ value: String) -> some View {
        VStack(alignment:.leading,spacing:7) {
            Text(verbatim:label).font(.caption).foregroundStyle(.secondary)
            Text(verbatim:value).textSelection(.enabled)
        }.padding(.vertical,4)
    }
    private func loadConfiguration() {
        do { configuration = try model.configurationStore.load() }
        catch { wallet.message = model.message(for:error) }
    }
}
