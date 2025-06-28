//
//  MicroficheApp.swift
//  Microfiche
//
//  Created by David Hoang on 6/8/25.
//

import SwiftUI

@main
struct MicroficheApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(after: .newItem) {
                Divider()
                Button("Clear Image Cache") {
                    ImageCache.shared.clearCache()
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                
                Button("Cache Info") {
                    showCacheInfo()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }
        }
    }
    
    private func showCacheInfo() {
        let monitor = PerformanceMonitor.shared
        let hitRate = String(format: "%.1f%%", monitor.cacheHitRate * 100)
        let totalRequests = monitor.totalRequests
        let cacheHits = monitor.cacheHits
        
        let alert = NSAlert()
        alert.messageText = "Cache Performance"
        alert.informativeText = """
        Cache Hit Rate: \(hitRate)
        Total Requests: \(totalRequests)
        Cache Hits: \(cacheHits)
        
        Image cache is stored in the app's cache directory and will be automatically managed. You can clear it manually if needed.
        """
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Reset Stats")
        
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            monitor.reset()
        }
    }
}
