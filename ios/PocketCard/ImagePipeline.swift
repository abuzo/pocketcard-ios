import Foundation
import UIKit
import ImageIO
import CoreTransferable
import UniformTypeIdentifiers
import PocketCardCore

struct ImportedPhoto: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            ImportedPhoto(data: try ImagePipeline.importFile(received.file))
        }
    }
}

enum ImagePipeline {
    static let maximumImportBytes = 25 * 1024 * 1024
    static let maximumImportPixels: Double = 50_000_000

    static func importFile(_ url: URL) throws -> Data {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= maximumImportBytes else {
            throw PocketCardError.validation("Выберите фото размером до 25 MiB.")
        }
        return try normalize(Data(contentsOf: url, options: .mappedIfSafe))
    }

    static func normalize(_ data: Data) throws -> Data {
        guard !data.isEmpty, data.count <= maximumImportBytes else {
            throw PocketCardError.validation("Выберите фото размером до 25 MiB.")
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
              let w = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let h = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              w.doubleValue > 0, h.doubleValue > 0, w.doubleValue * h.doubleValue <= maximumImportPixels else {
            throw PocketCardError.validation("Выберите неподвижное изображение до 50 мегапикселей.")
        }
        let options: [CFString:Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                      kCGImageSourceCreateThumbnailWithTransform: true,
                                      kCGImageSourceThumbnailMaxPixelSize: 2048,
                                      kCGImageSourceShouldCacheImmediately: true]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source,0,options as CFDictionary) else {
            throw PocketCardError.validation("Фото не удалось прочитать. Выберите другое изображение.")
        }
        return try raster(UIImage(cgImage:cgImage), size:CGSize(width:CGFloat(cgImage.width),height:CGFloat(cgImage.height)))
    }

    static func render(data: Data, crop: CropSettings, maxDimension: Int = 1600) throws -> Data {
        guard maxDimension > 0, maxDimension <= 2048,
              let source = UIImage(data:data)?.cgImage else { throw PocketCardError.missingImage }
        let rect = try crop.rect(imageWidth:Double(source.width), imageHeight:Double(source.height))
        let area = CGRect(x:CGFloat(rect.x),y:CGFloat(rect.y),width:CGFloat(rect.width),height:CGFloat(rect.height)).integral
            .intersection(CGRect(x:0,y:0,width:CGFloat(source.width),height:CGFloat(source.height)))
        guard let cropped = source.cropping(to:area), cropped.width > 0, cropped.height > 0 else {
            throw PocketCardError.validation("Выберите другую область фотографии.")
        }
        let scale = min(1,Double(maxDimension)/Double(max(cropped.width,cropped.height)))
        let size = CGSize(width:CGFloat(max(1,(Double(cropped.width)*scale).rounded())),height:CGFloat(max(1,(Double(cropped.height)*scale).rounded())))
        return try raster(UIImage(cgImage:cropped),size:size)
    }

    private static func raster(_ image: UIImage, size: CGSize) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = true; format.preferredRange = .standard
        let result = UIGraphicsImageRenderer(size:size,format:format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin:.zero,size:size))
            image.draw(in:CGRect(origin:.zero,size:size))
        }
        guard let data = result.jpegData(compressionQuality:0.9) else {
            throw PocketCardError.validation("Фото не удалось подготовить.")
        }
        return data
    }
}
