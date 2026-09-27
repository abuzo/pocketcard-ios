import SwiftUI
import PassKit
import PocketCardCore

struct PassPresentation: Identifiable {
    let id = UUID()
    let pass: PKPass
}

@MainActor
final class WalletCoordinator: ObservableObject {
    @Published private(set) var isIssuing = false
    @Published private(set) var changeSerial = 0
    @Published var pendingPass: PassPresentation?
    @Published var message: UserMessage?
    @Published private(set) var notice: String?
    private let library = PKPassLibrary()
    private var observer: NSObjectProtocol?

    init() {
        let name = Notification.Name(rawValue:PKPassLibraryNotificationName.PKPassLibraryDidChange.rawValue)
        observer = NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    func refresh() { changeSerial &+= 1 }
    func observation(for card: Card) -> WalletObservation {
        guard BuildIdentity.isConfigured, PKPassLibrary.isPassLibraryAvailable() else { return .unavailable }
        guard let pass = library.pass(withPassTypeIdentifier:BuildIdentity.passTypeIdentifier,serialNumber:card.id.uuidString.lowercased()) else { return .missing }
        guard let revision = (pass.userInfo?["revision"] as? NSNumber)?.intValue,
              pass.userInfo?["pocketcardID"] as? String == card.id.uuidString.lowercased() else { return .unavailable }
        if let receipt = card.lastIssued, receipt.revision == revision,
           pass.userInfo?["contentHash"] as? String != receipt.contentHash { return .unavailable }
        return .present(revision:revision)
    }
    func status(for card: Card) -> WalletStatus { card.walletStatus(observation:observation(for:card)) }

    /// Called only after the disclosure dialog confirms a specific saved-card snapshot.
    func issue(card: Card, model: AppModel, configuration: SignerConfiguration) async {
        guard !isIssuing else { return }
        isIssuing = true; notice = nil
        defer { isIssuing = false }
        do {
            guard BuildIdentity.isConfigured else { throw PocketCardError.validation("В сборке ещё не настроен Wallet. Откройте инструкцию docs/SETUP.md и заполните ios/Local.xcconfig.") }
            guard PKAddPassesViewController.canAddPasses() else { throw PocketCardError.validation("Добавление в Wallet на этом устройстве недоступно.") }
            guard let current = model.card(card.id), current.revision == card.revision, current.hasSameContent(as:card) else {
                throw PocketCardError.staleRevision
            }
            let source = card.template.usesImage ? try model.repository.imageData(for:card) : nil
            let prepared = try await Task.detached(priority:.userInitiated) {
                let image = try source.map { try ImagePipeline.render(data:$0,crop:card.crop) }
                return try PreparedIssue(card:card,image:image)
            }.value
            try Task.checkCancellation()
            let data = try await WalletClient.issue(prepared,configuration:configuration)
            try Task.checkCancellation()
            guard let latest = model.card(card.id), latest.revision == card.revision, latest.hasSameContent(as:card) else {
                throw PocketCardError.staleRevision
            }
            let pass: PKPass
            do { pass = try PKPass(data:data) }
            catch { throw PocketCardError.validation("Wallet не распознал выпущенную карточку. Проверьте сертификат и настройки сервиса.") }
            guard let info = pass.userInfo,
                  let issuedID = info["pocketcardID"] as? String,
                  let revision = (info["revision"] as? NSNumber)?.intValue,
                  let hash = info["contentHash"] as? String,
                  let team = info["teamIdentifier"] as? String,
                  (info["schemaVersion"] as? NSNumber)?.intValue == 1,
                  pass.serialNumber == prepared.cardID.uuidString.lowercased() else {
                throw PocketCardError.validation("Ответ сервиса не соответствует запросу PocketCard.")
            }
            let evidence = PassEvidence(cardID:issuedID,revision:revision,contentHash:hash,passTypeIdentifier:pass.passTypeIdentifier,teamIdentifier:team)
            try evidence.validate(cardID:prepared.cardID,revision:prepared.revision,contentHash:prepared.envelope.contentHash,
                                  passTypeIdentifier:BuildIdentity.passTypeIdentifier,teamIdentifier:BuildIdentity.teamIdentifier)
            var updated = latest
            updated.lastIssued = IssueRecord(revision:revision,contentHash:hash,passTypeIdentifier:pass.passTypeIdentifier,serialNumber:pass.serialNumber)
            _ = try model.save(updated)
            if library.pass(withPassTypeIdentifier:pass.passTypeIdentifier,serialNumber:pass.serialNumber) != nil {
                guard library.replacePass(with:pass) else {
                    throw PocketCardError.validation("Wallet отклонил обновление. Проверьте доступ к Pass Type ID в настройках сборки.")
                }
                refresh()
                notice = "Обновление передано Wallet. Статус определяется по фактической версии карточки."
            } else {
                pendingPass = PassPresentation(pass:pass)
                notice = "Карточка выпущена. Подтвердите добавление на системном экране Wallet."
            }
        } catch is CancellationError { notice = "Выпуск отменён. Локальная карточка сохранена." }
        catch {
            if Task.isCancelled { notice = "Выпуск отменён. Локальная карточка сохранена." }
            else { message = model.message(for:error) }
        }
    }
    func sheetFinished() {
        pendingPass = nil
        notice = "Системный экран закрыт. Наличие карточки проверяется в Wallet."
        refresh()
    }
}

struct WalletAddSheet: UIViewControllerRepresentable {
    let pass: PKPass
    let onFinish: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onFinish:onFinish) }
    func makeUIViewController(context: Context) -> UIViewController {
        guard let controller = PKAddPassesViewController(pass:pass) else {
            return UIHostingController(rootView:VStack(spacing:20) {
                Text("Wallet сейчас недоступен")
                Button("Закрыть",action:onFinish)
            }.padding())
        }
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    final class Coordinator: NSObject, PKAddPassesViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func addPassesViewControllerDidFinish(_ controller: PKAddPassesViewController) { onFinish() }
    }
}
