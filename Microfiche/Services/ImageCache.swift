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
        cacheDirectory = cachesDirectory.appendingPathComponent("Microfiche/ImageCache")
        
        // Create cache directory if it doesn't exist
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        // Configure NSCache
        cache.countLimit = 100 // Limit to 100 images
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB limit
    }
    
    func clearCache() {
        // Clear memory cache
        cache.removeAllObjects()
        
        // Clear disk cache
        do {
            let contents = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            for fileURL in contents {
                try fileManager.removeItem(at: fileURL)
            }
            print("Image cache cleared successfully")
        } catch {
            print("Error clearing image cache: \(error)")
        }
        
        // Notify performance monitor
        PerformanceMonitor.shared.notifyCacheCleared()
    }
    
    func setImage(_ image: NSImage, forKey key: String) {
        // Store in memory cache
        cache.setObject(image, forKey: key as NSString)
        
        // Optionally store to disk for persistence
        let fileURL = cacheDirectory.appendingPathComponent(key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key)
        
        DispatchQueue.global(qos: .background).async {
            if let tiffData = image.tiffRepresentation,
               let bitmapRep = NSBitmapImageRep(data: tiffData),
               let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                try? pngData.write(to: fileURL)
            }
        }
    }
    
    func image(forKey key: String) -> NSImage? {
        // Check memory cache first
        if let cachedImage = cache.object(forKey: key as NSString) {
            PerformanceMonitor.shared.recordCacheHit()
            return cachedImage
        }
        
        // Check disk cache
        let fileURL = cacheDirectory.appendingPathComponent(key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key)
        if let image = NSImage(contentsOf: fileURL) {
            // Store back in memory cache
            cache.setObject(image, forKey: key as NSString)
            PerformanceMonitor.shared.recordCacheHit()
            return image
        }
        
        PerformanceMonitor.shared.recordCacheMiss()
        return nil
    }
}