import XCTest
import UIKit
import ImageIO
import PocketCardCore
@testable import PocketCard

final class ImagePipelineTests: XCTestCase {
    private func source() throws -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300), format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0,y: 0,width: 400,height: 300))
            UIColor.blue.setFill(); context.fill(CGRect(x: 200,y: 0,width: 200,height: 300))
        }
        return try XCTUnwrap(image.pngData())
    }
    func testNormalizeStripsMetadataAndCapsSize() throws {
        let result = try ImagePipeline.normalize(try source())
        let image = try XCTUnwrap(UIImage(data: result)?.cgImage)
        XCTAssertLessThanOrEqual(max(image.width, image.height), 2048)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(result as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any])
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
    }
    func testRenderHonorsSquareCrop() throws {
        var crop = CropSettings(); crop.aspect = .square
        let data = try ImagePipeline.render(data: try source(), crop: crop, maxDimension: 300)
        let image = try XCTUnwrap(UIImage(data: data)?.cgImage)
        XCTAssertEqual(image.width, image.height)
        XCTAssertEqual(image.width, 300)
    }
    func testInvalidAndOversizedImageIsRejected() {
        XCTAssertThrowsError(try ImagePipeline.normalize(Data([1,2,3])))
        XCTAssertThrowsError(try ImagePipeline.normalize(Data(repeating: 0, count: 25*1024*1024+1)))
    }
}
