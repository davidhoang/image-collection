//
//  ImageCache.swift
//  Microfiche
//
//  Created by David Hoang on 6/8/25.
//

import Foundation
import SwiftUI

class ImageCache {
    static let shared = ImageCache()
    private var cache = NSCache<NSString, NSImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    
    private init() {
        // Set up cache directory
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cachesDirectory.appendingPathComponent("MicroficheThumbnails")
        
        // Create cache directory if it doesn't exist
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        // Configure NSCache
        cache.countLimit = 200 // Max 200 images in memory
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB limit
    }
    
    func clearCache() {
        cache.removeAllObjects()
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    func getImage(for url: URL, size: CGFloat) -> NSImage? {
        let key = cacheKey(for: url, size: size)
        
        // Check memory cache first
        if let cachedImage = cache.object(forKey: key as NSString) {
            return cachedImage
        }
        
        // Check disk cache
        let cacheURL = cacheDirectory.appendingPathComponent(key)
        if let image = NSImage(contentsOf: cacheURL) {
            // Check if the source file has been modified since cache was created
            if let cacheAttributes = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
               let sourceAttributes = try? FileManager.default.attributesOfItem(atPath: url.path),
               let cacheModDate = cacheAttributes[.modificationDate] as? Date,
               let sourceModDate = sourceAttributes[.modificationDate] as? Date {
                
                if sourceModDate > cacheModDate {
                    // Source file is newer than cache, invalidate cache
                    print("🔄 Cache invalidated for \(url.lastPathComponent) - file modified")
                    try? FileManager.default.removeItem(at: cacheURL)
                    return nil
                }
            }
            
            cache.setObject(image, forKey: key as NSString)
            return image
        }
        
        return nil
    }
    
    func setImage(_ image: NSImage, for url: URL, size: CGFloat) {
        let key = cacheKey(for: url, size: size)
        
        // Store in memory cache
        cache.setObject(image, forKey: key as NSString)
        
        // Store in disk cache
        let cacheURL = cacheDirectory.appendingPathComponent(key)
        if let data = image.tiffRepresentation {
            try? data.write(to: cacheURL)
        }
    }
    
    private func cacheKey(for url: URL, size: CGFloat) -> String {
        // Use a hash of the full path to avoid collisions with files of the same name
        let pathHash = url.path.hash
        let sizeString = String(format: "%.0f", size)
        return "\(pathHash)_\(sizeString)"
    }
    
    func clearCacheForFile(at url: URL) {
        let key = cacheKey(for: url, size: 0) // Size doesn't matter for clearing
        let baseKey = key.components(separatedBy: "_").first ?? ""
        
        // Remove from memory cache
        cache.removeObject(forKey: key as NSString)
        
        // Remove from disk cache (all sizes)
        do {
            let contents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            for file in contents {
                if file.lastPathComponent.hasPrefix(baseKey) {
                    try fileManager.removeItem(at: file)
                    print("🗑️ Cleared cache for \(url.lastPathComponent)")
                }
            }
        } catch {
            print("⚠️ Error clearing cache for \(url.lastPathComponent): \(error)")
        }
    }
}