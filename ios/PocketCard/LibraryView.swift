import SwiftUI
import PocketCardCore

@MainActor
struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var wallet: WalletCoordinator
    @State private var path: [UUID] = []
    @State private var creating = false
    @State private var settings = false
    @State private var deleting: Card?

    var body: some View {
        NavigationStack(path:$path) {
            Group {
                if model.cards.isEmpty {
                    ContentUnavailableView {
                        Label("Важное — под рукой",systemImage:"rectangle.stack")
                    } description: {
                        if model.unreadableFiles.isEmpty {
                            Text("Создавайте карточки с фото и текстом. Сохраняйте их здесь и добавляйте в Apple Wallet.")
                        } else {
                            Text("Локальные записи не удалось прочитать. Исходные файлы оставлены для восстановления. Создание новой карточки их не удаляет.")
                        }
                    } actions: {
                        Button("Создать карточку") { creating = true }.buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        Section {
                            ForEach(model.cards) { card in
                                NavigationLink(value:card.id) {
                                    HStack(spacing:14) {
                                        CardThumbnail(card:card,repository:model.repository)
                                        VStack(alignment:.leading,spacing:6) {
                                            Text(verbatim:card.displayTitle).font(.headline).lineLimit(2)
                                            Text(card.template.title).font(.subheadline).foregroundStyle(.secondary)
                                            Text(wallet.status(for:card).rawValue).font(.caption).foregroundStyle(.secondary)
                                        }.padding(.vertical,5)
                                    }
                                }
                                .contextMenu {
                                    Button("Создать копию",systemImage:"doc.on.doc") { model.duplicate(card) }
                                    Button("Удалить",systemImage:"trash",role:.destructive) { deleting = card }
                                }
                                .swipeActions { Button("Удалить",role:.destructive) { deleting = card } }
                            }
                        } header: { Text("Моя коллекция · \(model.cards.count)") }
                        if !model.unreadableFiles.isEmpty {
                            Section {
                                Label("Часть локальных записей не читается. Исходные файлы оставлены для восстановления.",systemImage:"exclamationmark.triangle")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("PocketCard")
            .toolbar {
                ToolbarItem(placement:.topBarLeading) {
                    Button("Настройки",systemImage:"gearshape") { settings = true }.labelStyle(.iconOnly)
                }
                ToolbarItem(placement:.topBarTrailing) {
                    Button("Создать карточку",systemImage:"plus") { creating = true }.labelStyle(.iconOnly)
                }
            }
            .navigationDestination(for:UUID.self) { id in CardDetailView(cardID:id) }
            .sheet(isPresented:$creating) {
                CreateCardFlow { saved in creating = false; path.append(saved.id) }
            }
            .sheet(isPresented:$settings) { SettingsView() }
            .alert(item:$model.error) { item in
                Alert(title:Text(item.title),message:Text(item.text),dismissButton:.default(Text("Понятно")))
            }
            .confirmationDialog("Удалить карточку?",isPresented:Binding(get:{deleting != nil},set:{if !$0 {deleting = nil}}),titleVisibility:.visible) {
                Button("Удалить из PocketCard",role:.destructive) {
                    if let deleting {
                        do { try model.delete(deleting.id) } catch { model.error = model.message(for:error) }
                    }
                    deleting = nil
                }
            } message: { Text("Копия в Apple Wallet останется. Локальные исходники этой карточки будут удалены.") }
        }
    }
}

@MainActor
private struct CardThumbnail: View {
    let card: Card
    let repository: CardRepository
    @State private var image: UIImage?
    var body: some View {
        ZStack {
            card.theme.color
            if let image, card.template.usesImage { Image(uiImage:image).resizable().scaledToFill() }
            else { Image(systemName:card.template.symbol).font(.title2).foregroundStyle(card.theme.ink) }
        }.frame(width:64,height:76).clipShape(RoundedRectangle(cornerRadius:12))
        .accessibilityHidden(true)
        .task(id:card.revision) {
            guard card.template.usesImage else { image = nil; return }
            do {
                let data = try await Task.detached {
                    guard let source = try repository.imageData(for:card) else { return Data?.none }
                    return try ImagePipeline.render(data:source,crop:card.crop,maxDimension:180)
                }.value
                if !Task.isCancelled { image = data.flatMap { UIImage(data:$0) } }
            } catch { image = nil }
        }
    }
}

@MainActor
struct CreateCardFlow: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Card?
    let onSaved: (Card) -> Void
    var body: some View {
        if let selected {
            CardEditorView(initial:selected,onSaved:onSaved)
        } else {
            NavigationStack {
                ScrollView {
                    VStack(alignment:.leading,spacing:18) {
                        Text("С чего начнём?").font(.largeTitle.bold())
                        Text("Выберите готовую композицию. Тип карточки можно будет изменить, сохранив введённые данные.")
                            .foregroundStyle(.secondary)
                        ForEach(CardTemplate.allCases) { template in
                            Button {
                                selected = Card(template:template)
                            } label: {
                                HStack(spacing:18) {
                                    Image(systemName:template.symbol).font(.system(size:26)).frame(width:48)
                                    VStack(alignment:.leading,spacing:7) {
                                        Text(template.title).font(.headline)
                                        Text(description(template)).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                                    }
                                    Spacer(); Image(systemName:"chevron.right").font(.caption)
                                }.padding(22).background(Color(.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:20))
                            }.buttonStyle(.plain)
                        }
                        Text("Крупное фото в Wallet предусмотрено для iOS 27+. На более ранних версиях — миниатюра.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }.padding(24)
                }.background(Color(.systemGroupedBackground))
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Закрыть") { dismiss() } } }
            }
        }
    }
    private func description(_ template: CardTemplate) -> String {
        switch template {
        case .photo: return "Любимый снимок, название и подпись."
        case .information: return "Важные сведения в полях с вашими названиями."
        case .mixed: return "Фото и нужная информация в одной карточке."
        }
    }
}
