#!/usr/bin/env swift

import SwiftUI
import AppKit

// Icon sizes required for macOS App Store
let iconSizes = [
    (16, 1), (16, 2),    // 16x16 @1x, 16x16 @2x
    (32, 1), (32, 2),    // 32x32 @1x, 32x32 @2x
    (128, 1), (128, 2),  // 128x128 @1x, 128x128 @2x
    (256, 1), (256, 2),  // 256x256 @1x, 256x256 @2x
    (512, 1), (512, 2)   // 512x512 @1x, 512x512 @2x
]

struct PlaceholderIconView: View {
    var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.gray.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.2), lineWidth: 2)
                )
            // Large P
            Text("P")
                .font(.system(size: 60, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .shadow(radius: 2)
            // Diagonal banner
            GeometryReader { geo in
                Text("PLACEHOLDER")
                    .font(.system(size: geo.size.width * 0.13, weight: .bold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.7))
                    .rotationEffect(.degrees(-30))
                    .offset(x: geo.size.width * 0.05, y: geo.size.height * 0.35)
            }
        }
        .frame(width: 100, height: 100)
    }
}

func generateIcon(size: Int, scale: Int) -> NSImage {
    let finalSize = size * scale
    let view = PlaceholderIconView()
        .frame(width: CGFloat(finalSize), height: CGFloat(finalSize))
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = NSRect(x: 0, y: 0, width: finalSize, height: finalSize)
    let image = NSImage(size: NSSize(width: finalSize, height: finalSize))
    image.addRepresentation(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: finalSize, pixelsHigh: finalSize, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!)
    image.lockFocus()
    hostingView.layer?.render(in: NSGraphicsContext.current!.cgContext)
    image.unlockFocus()
    return image
}

func saveIcon(image: NSImage, filename: String) {
    guard let tiffData = image.tiffRepresentation,
          let bitmapRep = NSBitmapImageRep(data: tiffData),
          let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
        print("Failed to create PNG data for \(filename)")
        return
    }
    let outputPath = "Microfiche/Assets.xcassets/AppIcon.appiconset/\(filename)"
    do {
        try pngData.write(to: URL(fileURLWithPath: outputPath))
        print("Generated: \(filename)")
    } catch {
        print("Failed to save \(filename): \(error)")
    }
}

// Generate all icons
print("Generating placeholder app icons...")

for (size, scale) in iconSizes {
    let image = generateIcon(size: size, scale: scale)
    let filename = "icon_\(size)x\(size)@\(scale)x.png"
    saveIcon(image: image, filename: filename)
}

print("Placeholder app icon generation complete!") 