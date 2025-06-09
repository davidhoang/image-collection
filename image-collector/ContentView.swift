//
//  ContentView.swift
//  image-collector
//
//  Created by David Hoang on 6/8/25.
//
import SwiftUI
import PDFKit

struct ImageFile: Identifiable, Equatable, Hashable {
    let id = UUID()
    let url: URL
    var name: String { url.lastPathComponent }
    static func == (lhs: ImageFile, rhs: ImageFile) -> Bool {
        lhs.id == rhs.id && lhs.url == rhs.url
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(url)
    }
}

struct ContentView: View {
    @State private var folderURLs: [URL] = []
    @State private var selectedFolderURL: URL?
    @State private var imageFiles: [ImageFile] = []
    @State private var viewMode: ViewMode = .grid
    @State private var sidebarExpanded: Bool = true
    @State private var selectedImageFileID: UUID? = nil
    @State private var showDeleteAlert: Bool = false
    @State private var dontAskAgain: Bool = UserDefaults.standard.bool(forKey: "dontAskDeleteConfirm")
    @State private var pendingDeleteFile: ImageFile? = nil
    
    let supportedExtensions = ["jpg", "jpeg", "png", "pdf", "svg", "gif", "tiff"]
    
    enum ViewMode: String, CaseIterable, Identifiable {
        case grid = "Grid"
        case list = "List"
        var id: String { rawValue }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            SidebarView(
                folderURLs: folderURLs,
                selectedFolderURL: selectedFolderURL,
                sidebarExpanded: sidebarExpanded,
                onToggleSidebar: { sidebarExpanded.toggle() },
                onLinkFolder: linkFolder,
                onSelectFolder: { selectedFolderURL = $0 }
            )
            Divider()
            MainContentView(
                imageFiles: imageFiles,
                viewMode: $viewMode,
                selectedImageFileID: selectedImageFileID,
                onSelectImage: { selectedImageFileID = $0 },
                selectedFolderURL: selectedFolderURL
            )
        }
        .onAppear {
            // Optionally, load persisted folders here
        }
        .onChange(of: selectedFolderURL) { oldValue, newValue in
            if let url = newValue {
                loadImages(from: url)
            } else {
                imageFiles = []
            }
        }
        .background(KeyboardEventHandlingView(onDeletePressed: {
            if let file = imageFiles.first(where: { $0.id == selectedImageFileID }) {
                if dontAskAgain {
                    moveFileToTrash(file)
                } else {
                    pendingDeleteFile = file
                    showDeleteAlert = true
                }
            }
        }))
        .alert(isPresented: $showDeleteAlert) {
            Alert(
                title: Text("Move to Trash?"),
                message: Text("Are you sure you want to move \(pendingDeleteFile?.name ?? "this file") to the Trash?"),
                primaryButton: .destructive(Text("Move to Trash")) {
                    if let file = pendingDeleteFile {
                        moveFileToTrash(file)
                        if dontAskAgain {
                            UserDefaults.standard.set(true, forKey: "dontAskDeleteConfirm")
                        }
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }
    
    private struct SidebarView: View {
        let folderURLs: [URL]
        let selectedFolderURL: URL?
        let sidebarExpanded: Bool
        let onToggleSidebar: () -> Void
        let onLinkFolder: () -> Void
        let onSelectFolder: (URL) -> Void
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    if sidebarExpanded {
                        Text("Folders")
                            .font(.headline)
                    }
                    Spacer()
                    Button(action: onToggleSidebar) {
                        Image(systemName: sidebarExpanded ? "chevron.left" : "chevron.right")
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    if sidebarExpanded {
                        Button(action: onLinkFolder) {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                }
                .padding([.top, .horizontal])
                List {
                    ForEach(folderURLs, id: \.self) { url in
                        HStack {
                            Image(systemName: "folder")
                            if sidebarExpanded {
                                Text(url.lastPathComponent)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelectFolder(url)
                        }
                        .background(selectedFolderURL == url ? Color.accentColor.opacity(0.2) : Color.clear)
                    }
                }
                .listStyle(SidebarListStyle())
                Spacer()
            }
            .frame(width: sidebarExpanded ? 200 : 40)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }
    
    private struct MainContentView: View {
        let imageFiles: [ImageFile]
        @Binding var viewMode: ContentView.ViewMode
        let selectedImageFileID: UUID?
        let onSelectImage: (UUID) -> Void
        let selectedFolderURL: URL?
        var body: some View {
            VStack {
                HeaderView(viewMode: $viewMode, selectedFolderURL: selectedFolderURL)
                if imageFiles.isEmpty {
                    Text("No images found. Link a folder to begin.")
                        .foregroundColor(.secondary)
                } else {
                    if viewMode == .grid {
                        ImageGridView(imageFiles: imageFiles, selectedImageFileID: selectedImageFileID, onSelectImage: onSelectImage)
                    } else {
                        ImageListView(imageFiles: imageFiles, selectedImageFileID: selectedImageFileID, onSelectImage: onSelectImage)
                    }
                }
            }
            .frame(minWidth: 600, minHeight: 600)
        }
    }
    
    private struct HeaderView: View {
        @Binding var viewMode: ContentView.ViewMode
        let selectedFolderURL: URL?
        var body: some View {
            HStack {
                Picker("View", selection: $viewMode) {
                    ForEach(ContentView.ViewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                Spacer()
                if let selectedFolderURL = selectedFolderURL {
                    Text("Linked: \(selectedFolderURL.path)")
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding()
        }
    }
    
    private struct ImageGridView: View {
        let imageFiles: [ImageFile]
        let selectedImageFileID: UUID?
        let onSelectImage: (UUID) -> Void
        var body: some View {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))]) {
                    ForEach(imageFiles) { file in
                        VStack {
                            FileThumbnailView(file: file)
                                .frame(width: 80, height: 80)
                                .background(selectedImageFileID == file.id ? Color.accentColor.opacity(0.3) : Color.gray.opacity(0.1))
                                .cornerRadius(8)
                                .onTapGesture {
                                    onSelectImage(file.id)
                                }
                            Text(file.name)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .frame(width: 100, height: 100)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedImageFileID == file.id ? Color.accentColor : Color.clear, lineWidth: 2)
                        )
                    }
                }
                .padding()
            }
        }
    }
    
    private struct ImageListView: View {
        let imageFiles: [ImageFile]
        let selectedImageFileID: UUID?
        let onSelectImage: (UUID) -> Void
        var body: some View {
            List {
                ForEach(imageFiles) { file in
                    HStack {
                        FileThumbnailView(file: file)
                            .frame(width: 40, height: 40)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(6)
                        VStack(alignment: .leading) {
                            Text(file.name)
                                .font(.body)
                                .lineLimit(1)
                            Text(file.url.path)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onSelectImage(file.id)
                    }
                    .background(selectedImageFileID == file.id ? Color.accentColor.opacity(0.2) : Color.clear)
                }
            }
            .listStyle(PlainListStyle())
        }
    }
    
    func linkFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                if !folderURLs.contains(url) {
                    folderURLs.append(url)
                }
                selectedFolderURL = url
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
    
    func moveFileToTrash(_ file: ImageFile) {
        let ws = NSWorkspace.shared
        ws.recycle([file.url]) { (newURLs, error) in
            if error == nil {
                imageFiles.removeAll { $0.id == file.id }
                if selectedImageFileID == file.id {
                    selectedImageFileID = nil
                }
            } else {
                // Optionally, show an error to the user
            }
        }
    }
}

struct FileThumbnailView: View {
    let file: ImageFile
    
    var body: some View {
        if ["jpg", "jpeg", "png", "gif", "tiff"].contains(file.url.pathExtension.lowercased()) {
            if let nsImage = NSImage(contentsOf: file.url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
            } else {
                placeholder
            }
        } else if file.url.pathExtension.lowercased() == "pdf" {
            if let pdfDoc = PDFDocument(url: file.url), let page = pdfDoc.page(at: 0) {
                let pdfThumb = page.thumbnail(of: NSSize(width: 80, height: 80), for: .cropBox)
                Image(nsImage: pdfThumb)
                    .resizable()
                    .scaledToFit()
            } else {
                placeholder
            }
        } else {
            // SVG or unsupported
            placeholder
        }
    }
    
    var placeholder: some View {
        Image(systemName: "doc")
            .resizable()
            .scaledToFit()
            .foregroundColor(.gray)
            .opacity(0.5)
    }
}

struct KeyboardEventHandlingView: NSViewRepresentable {
    var onDeletePressed: () -> Void
    func makeNSView(context: Context) -> NSView {
        let view = KeyCatcherView()
        view.onDeletePressed = onDeletePressed
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    class KeyCatcherView: NSView {
        var onDeletePressed: (() -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 51 { // Delete key
                onDeletePressed?()
            } else {
                super.keyDown(with: event)
            }
        }
        override func viewDidMoveToWindow() {
            window?.makeFirstResponder(self)
        }
    }
}
