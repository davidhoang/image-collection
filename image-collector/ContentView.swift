//
//  ContentView.swift
//  image-collector
//
//  Created by David Hoang on 6/8/25.
//
import SwiftUI

struct ImageFile: Identifiable {
    let id = UUID()
    let url: URL
    var name: String { url.lastPathComponent }
}

struct ContentView: View {
    @State private var folderURL: URL?
    @State private var imageFiles: [ImageFile] = []
    
    let supportedExtensions = ["jpg", "jpeg", "png", "pdf", "svg", "gif", "tiff"]
    
    var body: some View {
        VStack {
            HStack {
                Button("Link Folder") {
                    selectFolder()
                }
                if let folderURL = folderURL {
                    Text("Linked: \(folderURL.path)")
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding()
            
            if imageFiles.isEmpty {
                Text("No images found. Link a folder to begin.")
                    .foregroundColor(.secondary)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))]) {
                        ForEach(imageFiles) { file in
                            VStack {
                                // For now, just show the file name. You can add thumbnail loading later.
                                Text(file.name)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                            .frame(width: 100, height: 100)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }
    
    func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                folderURL = url
                loadImages(from: url)
            }
        }
    }
    
    func loadImages(from folder: URL) {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey]
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
        guard let enumerator = fileManager.enumerator(at: folder, includingPropertiesForKeys: keys, options: options) else {
            imageFiles = []
            return
        }
        var foundFiles: [ImageFile] = []
        for case let fileURL as URL in enumerator {
            if supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                foundFiles.append(ImageFile(url: fileURL))
            }
        }
        imageFiles = foundFiles
    }
}
