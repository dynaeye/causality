import AppKit
import Foundation
import ImageIO
import CausalityCore
import UniformTypeIdentifiers

/// 按需解码：画布与详情只要像素够用的缩略图，4K 原图只在查看原图时读。
actor ThumbnailService {
    static let shared = ThumbnailService()

    /// 有上限的内存缓存：缩略图最多 128 张、约 64 MB，超出自动淘汰。
    private let cache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.countLimit = 128
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    func jpegData(packageURL: URL, asset: Asset, maxPixel: Int) -> Data? {
        let key = "\(packageURL.path)|\(asset.fileName)|\(maxPixel)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached as Data
        }
        let url = ProjectPackage.assetURL(for: asset, in: packageURL)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let mutable = CFDataCreateMutable(nil, 0)
        guard let mutable,
              let destination = CGImageDestinationCreateWithData(
                  mutable,
                  UTType.jpeg.identifier as CFString,
                  1,
                  nil
              ) else {
            return nil
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        let data = mutable as Data
        cache.setObject(data as NSData, forKey: key, cost: data.count)
        return data
    }

    func pixelSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        return CGSize(width: width, height: height)
    }
}
