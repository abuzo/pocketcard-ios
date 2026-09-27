import SwiftUI
import UIKit
import PocketCardCore

extension CardTheme {
    var color: Color { Color(red:backgroundRGB[0]/255,green:backgroundRGB[1]/255,blue:backgroundRGB[2]/255) }
    var ink: Color { usesDarkText ? Color(red:0.12,green:0.14,blue:0.16) : .white }
}

enum PreviewMode: String, CaseIterable, Identifiable {
    case pocket = "PocketCard", classic = "Классический Wallet", poster = "Wallet iOS 27+"
    var id: String { rawValue }
}

@MainActor
struct CardPreview: View {
    let card: Card
    let sourceData: Data?
    var mode: PreviewMode = .pocket
    @State private var image: UIImage?
    private var renderKey: String {
        "\(card.template.rawValue)|\(card.imageID?.uuidString ?? "none")|\(sourceData?.count ?? 0)|\(card.crop.aspect.rawValue)|\(card.crop.zoom)|\(card.crop.horizontal)|\(card.crop.vertical)"
    }
    var body: some View {
        CardCanvas(card:card,image:image,mode:mode)
            .task(id:renderKey) {
                guard card.template.usesImage, let data = sourceData else { image = nil; return }
                let crop = card.crop
                do {
                    let result = try await Task.detached(priority:.userInitiated) {
                        try ImagePipeline.render(data:data,crop:crop,maxDimension:900)
                    }.value
                    guard !Task.isCancelled else { return }
                    image = UIImage(data:result)
                } catch { if !Task.isCancelled { image = nil } }
            }
    }
}

@MainActor
struct CardCanvas: View {
    let card: Card
    let image: UIImage?
    let mode: PreviewMode
    var body: some View {
        Group {
            if mode == .poster && card.template.usesImage { poster }
            else { regular }
        }
        .foregroundStyle(card.theme.ink)
        .background(card.theme.color)
        .clipShape(RoundedRectangle(cornerRadius:24,style:.continuous))
        .overlay(RoundedRectangle(cornerRadius:24,style:.continuous).strokeBorder(.primary.opacity(0.08)))
        .shadow(color:.black.opacity(0.12),radius:12,y:5)
    }
    private var brand: some View {
        HStack(spacing:7) {
            Image(systemName:"rectangle.stack.fill")
            Text("POCKETCARD").font(.caption.weight(.semibold)).tracking(2)
            Spacer()
            Image(systemName:card.template.symbol)
        }.opacity(0.8)
    }
    private var regular: some View {
        VStack(alignment:.leading,spacing:20) {
            brand
            if mode == .classic {
                HStack(alignment:.top,spacing:16) {
                    Text(verbatim:card.displayTitle).font(.title2.weight(.bold)).frame(maxWidth:.infinity,alignment:.leading)
                    if card.template.usesImage { artwork(height:78).frame(width:78).clipShape(RoundedRectangle(cornerRadius:12)) }
                }
            } else {
                if card.template.usesImage { artwork(height:card.template == .photo ? 240 : 170).clipShape(RoundedRectangle(cornerRadius:16)) }
                Text(verbatim:card.displayTitle).font(.title2.weight(.bold))
            }
            if card.template.usesFields && !card.fields.isEmpty { frontFields }
            if mode == .pocket && card.template.usesImage && !card.caption.isEmpty {
                Text(verbatim:card.caption).font(.subheadline).lineLimit(3).opacity(0.85)
            }
        }.padding(22).frame(maxWidth:.infinity,alignment:.leading)
    }
    private var poster: some View {
        VStack(spacing:0) {
            ZStack(alignment:.topLeading) {
                artwork(height:360)
                LinearGradient(colors:[.black.opacity(0.7),.clear],startPoint:.top,endPoint:.center)
                VStack(alignment:.leading,spacing:16) {
                    brand
                    Text(verbatim:card.displayTitle).font(.title2.weight(.bold)).lineLimit(3)
                }.padding(22).foregroundStyle(.white)
            }
            if card.template.usesFields && !card.fields.isEmpty { frontFields.padding(22) }
        }
    }
    private var frontFields: some View {
        VStack(alignment:.leading,spacing:14) {
            ForEach(Array(card.fields.prefix(2))) { field in
                VStack(alignment:.leading,spacing:5) {
                    Text(verbatim:field.label.isEmpty ? "Название поля" : field.label).font(.caption.weight(.semibold)).opacity(0.7)
                    Text(verbatim:field.value.isEmpty ? "Значение" : field.frontValue).font(.body.weight(.medium)).lineLimit(3)
                }
            }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private func artwork(height: CGFloat) -> some View {
        GeometryReader { geometry in
            if let image {
                Image(uiImage:image).resizable().scaledToFill().frame(width:geometry.size.width,height:height).clipped()
                    .accessibilityLabel("Фотография карточки")
            } else {
                ZStack {
                    card.theme.ink.opacity(0.08)
                    VStack(spacing:10) {
                        Image(systemName:"photo").font(.system(size:32,weight:.light))
                        Text("Место для фото").font(.caption)
                    }.opacity(0.6)
                }.frame(width:geometry.size.width,height:height)
            }
        }.frame(height:height)
    }
}
