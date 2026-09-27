import SwiftUI
import PocketCardCore

@MainActor
struct CardDetailView: View {
    let cardID: UUID
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var wallet: WalletCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Card?
    @State private var previewing = false
    @State private var deleting = false
    @State private var fullPhoto = false
    @State private var source: Data?
    @State private var imageError = false
    @State private var error: UserMessage?
    var body: some View {
        Group {
            if let card = model.card(cardID) {
                ScrollView {
                    VStack(alignment:.leading,spacing:26) {
                        CardPreview(card:card,sourceData:source)
                        HStack {
                            Label(wallet.status(for:card).rawValue,systemImage:"wallet.pass")
                            Spacer(); Text("Версия \(card.revision)")
                        }.font(.caption).foregroundStyle(.secondary)
                        if imageError { Label("Фото недоступно. Выберите его повторно в редакторе.",systemImage:"exclamationmark.triangle").font(.footnote) }
                        if card.template.usesImage && source != nil {
                            Button("Открыть фото",systemImage:"arrow.up.left.and.arrow.down.right") { fullPhoto = true }
                        }
                        if card.template.usesImage && !card.caption.isEmpty {
                            VStack(alignment:.leading,spacing:8) {
                                Text("Подпись").font(.caption).foregroundStyle(.secondary)
                                Text(verbatim:card.caption).textSelection(.enabled)
                            }
                        }
                        if card.template.usesFields {
                            ForEach(card.fields) { field in
                                VStack(alignment:.leading,spacing:8) {
                                    Text(verbatim:field.label).font(.caption).foregroundStyle(.secondary)
                                    Text(verbatim:field.value).textSelection(.enabled)
                                }.frame(maxWidth:.infinity,alignment:.leading)
                                Divider()
                            }
                        }
                        Button { previewing = true } label: {
                            Label("Предпросмотр и выпуск",systemImage:"wallet.pass.fill").frame(maxWidth:.infinity).padding(.vertical,8)
                        }.buttonStyle(.borderedProminent).disabled(!card.isReady || imageError)
                        if !card.isReady {
                            Text("Это черновик. Добавьте название, фотографию и поля, необходимые выбранному шаблону.").font(.footnote).foregroundStyle(.secondary)
                        }
                        Text("Данные хранятся в PocketCard на этом iPhone. Для выпуска в Wallet потребуется отдельное подтверждение отправки.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }.padding(24)
                }
                .navigationTitle(card.displayTitle).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.topBarTrailing) {
                        Menu {
                            Button("Редактировать",systemImage:"pencil") { editing = card }
                            Button("Создать копию",systemImage:"doc.on.doc") { model.duplicate(card) }
                            Button("Удалить",systemImage:"trash",role:.destructive) { deleting = true }
                        } label: { Image(systemName:"ellipsis.circle").accessibilityLabel("Действия с карточкой") }
                    }
                }
                .task(id:"\(card.template.rawValue)|\(card.imageID?.uuidString ?? "none")") {
                    guard card.template.usesImage else { source = nil; imageError = false; return }
                    do {
                        let repository = model.repository
                        let data = try await Task.detached { try repository.imageData(for:card) }.value
                        if !Task.isCancelled { source = data; imageError = card.imageID != nil && data == nil }
                    } catch { if !Task.isCancelled { source = nil; imageError = true } }
                }
                .sheet(isPresented:$previewing) { WalletPreviewView(card:card,source:source) }
                .fullScreenCover(isPresented:$fullPhoto) {
                    NavigationStack {
                        Group {
                            if let source, let image = UIImage(data:source) { Image(uiImage:image).resizable().scaledToFit().padding() }
                            else { ContentUnavailableView("Фото недоступно",systemImage:"photo") }
                        }.frame(maxWidth:.infinity,maxHeight:.infinity).background(Color(.systemBackground))
                        .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Закрыть") { fullPhoto = false } } }
                    }
                }
            } else { ContentUnavailableView("Карточка удалена",systemImage:"rectangle.stack") }
        }
        .sheet(item:$editing) { card in CardEditorView(initial:card) { _ in editing = nil } }
        .confirmationDialog("Удалить карточку?",isPresented:$deleting,titleVisibility:.visible) {
            Button("Удалить из PocketCard",role:.destructive) {
                do { try model.delete(cardID); dismiss() } catch { self.error = model.message(for:error) }
            }
        } message: { Text("Карточка будет удалена из PocketCard. Копия в Apple Wallet останется.") }
        .alert(item:$error) { Alert(title:Text($0.title),message:Text($0.text),dismissButton:.default(Text("Понятно"))) }
    }
}
