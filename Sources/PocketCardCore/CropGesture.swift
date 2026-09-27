import Foundation

public extension CropSettings {
    /// Applies screen-space movement to the existing export crop, keeping its center during zoom.
    func applyingGesture(imageWidth: Double, imageHeight: Double, viewportWidth: Double,
                         translationX: Double, translationY: Double, magnification: Double) throws -> CropSettings {
        guard viewportWidth.isFinite, viewportWidth > 0, translationX.isFinite,
              translationY.isFinite, magnification.isFinite, magnification > 0 else {
            throw PocketCardError.validation("Проверьте параметры кадрирования.")
        }
        let previous = try rect(imageWidth: imageWidth, imageHeight: imageHeight)
        var result = self
        result.zoom = min(3, max(1, zoom * magnification))
        let next = try result.rect(imageWidth: imageWidth, imageHeight: imageHeight)
        let scale = viewportWidth / next.width
        let x = previous.x + previous.width / 2 - next.width / 2 - translationX / scale
        let y = previous.y + previous.height / 2 - next.height / 2 - translationY / scale
        result.horizontal = imageWidth > next.width ? min(1, max(0, x / (imageWidth - next.width))) : 0.5
        result.vertical = imageHeight > next.height ? min(1, max(0, y / (imageHeight - next.height))) : 0.5
        return result
    }
}
