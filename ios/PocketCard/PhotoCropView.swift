import SwiftUI
import UIKit
import PocketCardCore

struct CropPhoto: Identifiable {
    let id = UUID()
    let data: Data
}

@MainActor
struct PhotoCropView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding private var crop: CropSettings
    @State private var draft: CropSettings
    @GestureState private var translation = CGSize.zero
    @GestureState private var magnification: CGFloat = 1
    private let image: UIImage?

    init(data: Data, crop: Binding<CropSettings>) {
        _crop = crop
        _draft = State(initialValue: crop.wrappedValue)
        image = UIImage(data: data)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Двигайте фото пальцем. Меняйте масштаб двумя пальцами.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal)
                GeometryReader { geometry in
                    if let image {
                        let width = max(1, min(geometry.size.width - 32, geometry.size.height * draft.aspect.ratio))
                        canvas(image: image, width: width)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    } else {
                        ContentUnavailableView("Фото недоступно", systemImage: "photo",
                                               description: Text("Закройте этот экран и выберите фото повторно."))
                    }
                }
                Picker("Форма кадра", selection: $draft.aspect) {
                    ForEach(CropAspect.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).padding(.horizontal)
                Button("Сбросить") {
                    let aspect = draft.aspect
                    draft = CropSettings(); draft.aspect = aspect
                }.padding(.bottom, 12)
            }
            .navigationTitle("Кадрирование")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { crop = draft; dismiss() }
                        .fontWeight(.semibold).disabled(image == nil).accessibilityIdentifier("apply-crop")
                }
            }
            .interactiveDismissDisabled()
        }
    }

    private func adjusted(_ image: UIImage, width: Double, translation: CGSize, magnification: CGFloat) -> CropSettings {
        (try? draft.applyingGesture(imageWidth: image.size.width, imageHeight: image.size.height,
                                    viewportWidth: width, translationX: translation.width,
                                    translationY: translation.height, magnification: magnification)) ?? draft
    }

    private func canvas(image: UIImage, width: CGFloat) -> some View {
        let current = adjusted(image, width: width, translation: translation, magnification: magnification)
        let rect = try? current.rect(imageWidth: image.size.width, imageHeight: image.size.height)
        let scale = width / (rect?.width ?? image.size.width)
        let height = width / current.aspect.ratio
        return ZStack(alignment: .topLeading) {
            Image(uiImage: image).resizable()
                .frame(width: image.size.width * scale, height: image.size.height * scale)
                .offset(x: -(rect?.x ?? 0) * scale, y: -(rect?.y ?? 0) * scale)
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .clipped()
        .overlay(Rectangle().strokeBorder(.white.opacity(0.9), lineWidth: 1))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .simultaneously(with: MagnifyGesture())
                .updating($translation) { value, state, _ in state = value.first?.translation ?? .zero }
                .updating($magnification) { value, state, _ in state = value.second?.magnification ?? 1 }
                .onEnded { value in
                    draft = adjusted(image, width: width, translation: value.first?.translation ?? .zero,
                                     magnification: value.second?.magnification ?? 1)
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Кадр фотографии")
        .accessibilityValue("Масштаб \(Int(current.zoom * 100)) процентов")
        .accessibilityIdentifier("crop-canvas")
        .accessibilityAdjustableAction { direction in
            let factor = direction == .increment ? 1.2 : 1 / 1.2
            draft = adjusted(image, width: width, translation: .zero, magnification: factor)
        }
        .accessibilityAction(named: "Сдвинуть фото влево") { move(image, width: width, x: -30, y: 0) }
        .accessibilityAction(named: "Сдвинуть фото вправо") { move(image, width: width, x: 30, y: 0) }
        .accessibilityAction(named: "Сдвинуть фото вверх") { move(image, width: width, x: 0, y: -30) }
        .accessibilityAction(named: "Сдвинуть фото вниз") { move(image, width: width, x: 0, y: 30) }
    }

    private func move(_ image: UIImage, width: CGFloat, x: CGFloat, y: CGFloat) {
        draft = adjusted(image, width: width, translation: CGSize(width: x, height: y), magnification: 1)
    }
}
