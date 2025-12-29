//
//  PreviewImageCache.swift
//  Microfiche
//
//  Created by Claude on 12/28/25.
//

import Foundation
import AppKit

class PreviewImageCache {
    static let shared = PreviewImageCache()

    private let cache = NSCache<NSURL, NSImage>()
    private let processingQueue = DispatchQueue(label: "com.microfiche.previewcache", qos: .userInitiated, attributes: .concurrent)

    private init() {
        // Configure cache limits - store up to 10 preview images (roughly 100-200MB)
        cache.countLimit = 10
        cache.totalCostLimit = 200 * 1024 * 1024 // 200MB
    }

    func getImage(for url: URL) -> NSImage? {
        return cache.object(forKey: url as NSURL)
    }

    func preloadImage(for url: URL, completion: ((NSImage?) -> Void)? = nil) {
        // Check cache first
        if let cached = cache.object(forKey: url as NSURL) {
            completion?(cached)
            return
        }

        // Load on background queue
        processingQueue.async { [weak self] in
            guard let self = self else { return }

            // Load and decode image
            guard let image = self.loadAndOptimizeImage(from: url) else {
                DispatchQueue.main.async {
                    completion?(nil)
                }
                return
            }

            // Store in cache (cost = rough memory size)
            let cost = Int(image.size.width * image.size.height * 4) // RGBA
            self.cache.setObject(image, forKey: url as NSURL, cost: cost)

            DispatchQueue.main.async {
                completion?(image)
            }
        }
    }

    private func loadAndOptimizeImage(from url: URL) -> NSImage? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        // Get image properties without decoding
        guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight as String] as? CGFloat else {
            return NSImage(contentsOf: url)
        }

        // Calculate optimal size for preview (max 2000px on longest side)
        let maxDimension: CGFloat = 2000
        let scale: CGFloat
        if max(width, height) > maxDimension {
            scale = maxDimension / max(width, height)
        } else {
            scale = 1.0
        }

        let targetWidth = width * scale
        let targetHeight = height * scale

        // Create thumbnail with decoding
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(targetWidth, targetHeight),
            kCGImageSourceShouldCache: false // We handle our own caching
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            return NSImage(contentsOf: url)
        }

        // Convert to NSImage
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: targetWidth, height: targetHeight))
        return nsImage
    }

    func clearCache() {
        cache.removeAllObjects()
    }
}
