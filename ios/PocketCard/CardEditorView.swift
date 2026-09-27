import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import PocketCardCore

@MainActor
struct CardEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    private let original: Card
    let onSaved: (Card) -> Void
    @State private var card: Card
    @State private var sourceData: Data?
    @State private var pendingImageData: Data?
    @State private var photoSelection: PhotosPickerItem?
    @State private var importing = false
    @State private var choosingFile = false
    @State private var croppingPhoto: CropPhoto?
    @State private var confirmingExit = false
    @State private var error: UserMessage?
    init(initial: Card, onSaved: @escaping (Card) -> Void) {
        self.original = initial; self.onSaved = onSaved
        _card = State(initialValue:initial)
    }
    private var changed: Bool { !card.hasSameContent(as:original) || pendingImageData != nil }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    CardPreview(card:card,sourceData:sourceData).listRowInsets(EdgeInsets(top:12,leading:0,bottom:16,trailing:0))
                        .listRowBackground(Color.clear)
                }
                Section("Карточка") {
                    TextField("Название",text:$card.title).textInputAutocapitalization(.sentences)
                        .accessibilityIdentifier("card-title")
                    Picker("Шаблон",selection:$card.template) { ForEach(CardTemplate.allCases) { Text($0.title).tag($0) } }
                    Text("Название — до 60 символов Unicode.").font(.caption).foregroundStyle(.secondary)
                }
                if card.template.usesImage { photoSection }
                if card.template.usesFields { fieldsSection }
                Section("Цветовая тема") {
                    Picker("Тема",selection:$card.theme) {
                        ForEach(CardTheme.allCases) { theme in Text(theme.title).tag(theme) }
                    }.pickerStyle(.segmented)
                }
                Section {
                    Text("Скрытые выбранным шаблоном фото и поля остаются локально. В Wallet попадут только данные текущего шаблона.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(model.card(card.id) == nil ? "Новая карточка" : "Редактирование")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) {
                    Button("Отмена") { if changed { confirmingExit = true } else { dismiss() } }.disabled(importing)
                }
                ToolbarItem(placement:.confirmationAction) {
                    Button("Сохранить",action:save).fontWeight(.semibold).disabled(importing).accessibilityIdentifier("save-card")
                }
            }
            .interactiveDismissDisabled(changed || importing)
            .task {
                guard sourceData == nil, original.imageID != nil else { return }
                do {
                    let repository = model.repository
                    let data = try await Task.detached { try repository.imageData(for:original) }.value
                    if !Task.isCancelled && pendingImageData == nil && card.imageID == original.imageID { sourceData = data }
                } catch { self.error = UserMessage("Фото недоступно. Выберите его повторно или удалите из карточки.") }
            }
            .task(id:photoSelection) {
                guard let selected = photoSelection else { return }
                importing = true; defer { importing = false }
                do {
                    guard let photo = try await selected.loadTransferable(type:ImportedPhoto.self) else { throw PocketCardError.missingImage }
                    guard !Task.isCancelled else { return }
                    acceptPhoto(photo.data)
                } catch { if !Task.isCancelled { self.error = model.message(for:error) } }
            }
            .fileImporter(isPresented:$choosingFile,allowedContentTypes:[.image]) { result in
                switch result {
                case .success(let url):
                    importing = true
                    Task {
                        defer { importing = false }
                        do { let data = try await Task.detached { try ImagePipeline.importFile(url) }.value; acceptPhoto(data) }
                        catch { self.error = model.message(for:error) }
                    }
                case .failure: error = UserMessage("Изображение не выбрано. Попробуйте открыть другой файл.")
                }
            }
            .fullScreenCover(item:$croppingPhoto) { photo in
                PhotoCropView(data:photo.data,crop:$card.crop)
            }
            .alert(item:$error) { Alert(title:Text($0.title),message:Text($0.text),dismissButton:.default(Text("Понятно"))) }
            .confirmationDialog("Сохранить изменения?",isPresented:$confirmingExit,titleVisibility:.visible) {
                Button("Сохранить",action:save)
                Button("Не сохранять",role:.destructive) { dismiss() }
                Button("Продолжить редактирование",role:.cancel) {}
            }
        }
    }
    private var photoSection: some View {
        let photoPickerTitle = sourceData == nil ? "Выбрать фото" : "Заменить фото"
        return Section {
            PhotosPicker(selection:$photoSelection,matching:.images,preferredItemEncoding:.compatible) {
                Label(photoPickerTitle,systemImage:"photo.on.rectangle")
            }.disabled(importing)
            Button("Выбрать из Файлов",systemImage:"folder") { choosingFile = true }.disabled(importing)
            if importing { ProgressView("Подготовка фото…") }
            if let sourceData {
                Button("Кадрировать фото", systemImage:"crop") { croppingPhoto = CropPhoto(data:sourceData) }
                    .disabled(importing).accessibilityIdentifier("crop-photo")
            }
            if card.imageID != nil {
                Button("Убрать фото",role:.destructive) {
                    sourceData = nil; pendingImageData = nil; card.imageID = nil; card.crop = CropSettings(); photoSelection = nil
                }.disabled(importing)
            }
            TextField("Подпись — необязательно",text:$card.caption,axis:.vertical).lineLimit(2...5)
        } header: { Text("Фотография") } footer: {
            Text("Фото до 25 MiB и 50 мегапикселей. Рабочая копия уменьшается до 2048 пикселей. Подпись — до 500 символов. Wallet может дополнительно кадрировать изображение.")
        }
    }
    private var fieldsSection: some View {
        Section {
            ForEach($card.fields) { $field in
                VStack(alignment:.leading,spacing:10) {
                    HStack {
                        TextField("Название поля",text:$field.label)
                        Button(role:.destructive) { card.fields.removeAll { $0.id == field.id } } label: {
                            Image(systemName:"minus.circle")
                        }.buttonStyle(.borderless).accessibilityLabel("Удалить поле \(field.label)")
                    }
                    TextField("Значение",text:$field.value,axis:.vertical).lineLimit(2...6)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }.padding(.vertical,6)
            }
            Button("Добавить поле",systemImage:"plus.circle") { card.fields.append(CardField()) }
                .disabled(card.fields.count >= 10).accessibilityIdentifier("add-field")
        } header: { Text("Ваши поля · \(card.fields.count)/10") } footer: {
            Text("Название поля — до 40 символов, значение — до 2000. Все значения сохраняются как текст, включая ведущие нули. Для Wallet нужны заполненные поля.")
        }
    }
    private func acceptPhoto(_ data: Data) {
        sourceData = data; pendingImageData = data; card.imageID = UUID(); card.crop = CropSettings()
        croppingPhoto = CropPhoto(data:data)
    }
    private func save() {
        do { let saved = try model.save(card,image:pendingImageData); onSaved(saved); dismiss() }
        catch { self.error = model.message(for:error) }
    }
}
