//
//  ContentView.swift
//  image-collector
//
//  Created by David Hoang on 6/8/25.
//
import SwiftUI
import PDFKit
import ImageIO

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
    @State private var gridThumbnailSize: GridThumbnailSize = .medium
    @State private var selectedImageFileIDs: Set<UUID> = []
    @State private var lastSelectedImageFileID: UUID?
    @State private var showDeleteAlert: Bool = false
    @State private var dontAskAgain: Bool = UserDefaults.standard.bool(forKey: "dontAskDeleteConfirm")
    @State private var pendingDeleteFiles: [ImageFile] = []
    @State private var previewedImageFile: ImageFile?
    @State private var scrollToID: UUID?
    @State private var gridColumnCount: Int = 1
    
    let supportedExtensions = ["jpg", "jpeg", "png", "pdf", "svg", "gif", "tiff"]
    
    enum ViewMode: String, CaseIterable, Identifiable {
        case grid = "Grid"
        case list = "List"
        var id: String { rawValue }
    }
    
    enum GridThumbnailSize: String, CaseIterable, Identifiable {
        case small = "Small"
        case medium = "Medium"
        case large = "Large"
        var id: String { rawValue }
    }
    
    enum ArrowDirection {
        case up, down, left, right
    }
    
    var body: some View {
        ZStack {
            NavigationSplitView {
                SidebarView(
                    folderURLs: folderURLs,
                    selectedFolderURL: selectedFolderURL,
                    onLinkFolder: linkFolder,
                    onSelectFolder: { url in
                        selectedFolderURL = url
                        selectedImageFileIDs = []
                        lastSelectedImageFileID = nil
                    }
                )
            } detail: {
                MainContentView(
                    imageFiles: imageFiles,
                    viewMode: $viewMode,
                    gridThumbnailSize: $gridThumbnailSize,
                    gridColumnCount: $gridColumnCount,
                    selectedImageFileIDs: $selectedImageFileIDs,
                    onSelectImage: handleImageSelection,
                    selectedFolderURL: selectedFolderURL,
                    scrollToID: $scrollToID
                )
            }
            .navigationTitle("")
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
            .onChange(of: showDeleteAlert) { _, isShowing in
                if !isShowing {
                    pendingDeleteFiles = []
                }
            }
            .background(KeyboardEventHandlingView(
                onDeletePressed: {
                    let filesToDelete = imageFiles.filter { selectedImageFileIDs.contains($0.id) }
                    if !filesToDelete.isEmpty {
                        if dontAskAgain {
                            moveFilesToTrash(filesToDelete)
                        } else {
                            pendingDeleteFiles = filesToDelete
                            showDeleteAlert = true
                        }
                    }
                },
                onEscapePressed: {
                    if previewedImageFile != nil {
                        previewedImageFile = nil
                    } else if !selectedImageFileIDs.isEmpty {
                        selectedImageFileIDs = []
                        lastSelectedImageFileID = nil
                    }
                },
                onSpacebarPressed: {
                    if previewedImageFile != nil {
                        previewedImageFile = nil
                        return
                    }
                    
                    guard !selectedImageFileIDs.isEmpty else { return }

                    let idToPreview = selectedImageFileIDs.count == 1 ? selectedImageFileIDs.first : lastSelectedImageFileID
                    
                    if let id = idToPreview, let file = imageFiles.first(where: { $0.id == id }) {
                        previewedImageFile = file
                    }
                },
                onArrowPressed: handleArrowKey
            ))
            .alert("Move to Trash?", isPresented: $showDeleteAlert) {
                Button("Move to Trash", role: .destructive) {
                    moveFilesToTrash(pendingDeleteFiles)
                    if dontAskAgain {
                        UserDefaults.standard.set(true, forKey: "dontAskDeleteConfirm")
                    }
                }
                .keyboardShortcut(.defaultAction)

                Button("Cancel", role: .cancel) { }
            } message: {
                let fileCount = pendingDeleteFiles.count
                let messageText = fileCount == 1 ?
                    "Are you sure you want to move \(pendingDeleteFiles.first?.name ?? "this file") to the Trash?" :
                    "Are you sure you want to move \(fileCount) items to the Trash?"
                Text(messageText)
            }
            
            if let file = previewedImageFile {
                PreviewView(file: file) {
                    previewedImageFile = nil
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: previewedImageFile)
    }
    
    private struct SidebarView: View {
        let folderURLs: [URL]
        let selectedFolderURL: URL?
        let onLinkFolder: () -> Void
        let onSelectFolder: (URL) -> Void
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("Folders")
                    .font(.headline)
                    .padding([.top, .horizontal])

                List {
                    ForEach(folderURLs, id: \.self) { url in
                        HStack {
                            Image(systemName: "folder")
                            Text(url.lastPathComponent)
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

                HStack {
                    Button(action: onLinkFolder) {
                        Label("Add Folder", systemImage: "plus")
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .padding()
                    Spacer()
                }
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
    }
    
    private struct MainContentView: View {
        let imageFiles: [ImageFile]
        @Binding var viewMode: ContentView.ViewMode
        @Binding var gridThumbnailSize: ContentView.GridThumbnailSize
        @Binding var gridColumnCount: Int
        @Binding var selectedImageFileIDs: Set<UUID>
        let onSelectImage: (UUID) -> Void
        let selectedFolderURL: URL?
        @Binding var scrollToID: UUID?
        var body: some View {
            VStack {
                if imageFiles.isEmpty {
                    Spacer()
                    Text("No images found. Link a folder to begin.")
                        .foregroundColor(.secondary)
                    Spacer()
                } else {
                    if viewMode == .grid {
                        ImageGridView(imageFiles: imageFiles, selectedImageFileIDs: $selectedImageFileIDs, onSelectImage: onSelectImage, thumbnailSize: gridThumbnailSize, scrollToID: $scrollToID, columnCount: $gridColumnCount)
                    } else {
                        ImageListView(imageFiles: imageFiles, selectedImageFileIDs: $selectedImageFileIDs, onSelectImage: onSelectImage, scrollToID: $scrollToID)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $viewMode) {
                        ForEach(ContentView.ViewMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }

                if viewMode == .grid {
                    ToolbarItem {
                        Picker("Size", selection: $gridThumbnailSize) {
                            ForEach(ContentView.GridThumbnailSize.allCases) { size in
                                Text(size.rawValue).tag(size)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width: 150)
                        .padding(.trailing)
                    }
                }
            }
        }
    }
    
    private struct ImageGridView: View {
        let imageFiles: [ImageFile]
        @Binding var selectedImageFileIDs: Set<UUID>
        let onSelectImage: (UUID) -> Void
        let thumbnailSize: ContentView.GridThumbnailSize
        @Binding var scrollToID: UUID?
        @Binding var columnCount: Int

        private var itemSize: CGFloat {
            switch thumbnailSize {
            case .small: return 80
            case .medium: return 120
            case .large: return 160
            }
        }

        private var columns: [GridItem] {
            [GridItem(.adaptive(minimum: itemSize))]
        }

        var body: some View {
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: columns) {
                            ForEach(imageFiles) { file in
                                VStack {
                                    FileThumbnailView(file: file, size: itemSize - 20)
                                        .frame(width: itemSize - 20, height: itemSize - 20)
                                        .background(selectedImageFileIDs.contains(file.id) ? Color.accentColor.opacity(0.3) : Color.gray.opacity(0.1))
                                        .cornerRadius(8)
                                        .onTapGesture {
                                            onSelectImage(file.id)
                                        }
                                    Text(file.name)
                                        .font(.caption)
                                        .lineLimit(1)
                                }
                                .frame(width: itemSize, height: itemSize)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selectedImageFileIDs.contains(file.id) ? Color.accentColor : Color.clear, lineWidth: 2)
                                )
                                .id(file.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: scrollToID) { _, newID in
                        if let id = newID {
                            withAnimation {
                                proxy.scrollTo(id, anchor: .center)
                            }
                            DispatchQueue.main.async {
                                scrollToID = nil
                            }
                        }
                    }
                }
                .onAppear {
                    recalculateColumnCount(width: geometry.size.width)
                }
                .onChange(of: geometry.size.width) { _, newWidth in
                    recalculateColumnCount(width: newWidth)
                }
            }
        }
        
        private func recalculateColumnCount(width: CGFloat) {
            // Standard SwiftUI padding is ~16. LazyVGrid default spacing is ~8.
            let horizontalPadding: CGFloat = 32
            let spacing: CGFloat = 8
            let availableWidth = width - horizontalPadding
            
            // Formula for adaptive grid: N = floor((W + S) / (I + S))
            let newColumnCount = Int((availableWidth + spacing) / (itemSize + spacing))

            if newColumnCount > 0 && self.columnCount != newColumnCount {
                self.columnCount = newColumnCount
            }
        }
    }
    
    private struct ImageListView: View {
        let imageFiles: [ImageFile]
        @Binding var selectedImageFileIDs: Set<UUID>
        let onSelectImage: (UUID) -> Void
        @Binding var scrollToID: UUID?
        var body: some View {
            ScrollViewReader { proxy in
                List {
                    ForEach(imageFiles) { file in
                        HStack {
                            FileThumbnailView(file: file, size: 40)
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
                        .background(selectedImageFileIDs.contains(file.id) ? Color.accentColor.opacity(0.2) : Color.clear)
                        .id(file.id)
                    }
                }
                .listStyle(PlainListStyle())
                .onChange(of: scrollToID) { _, newID in
                    if let id = newID {
                        withAnimation {
                            proxy.scrollTo(id, anchor: .center)
                        }
                        DispatchQueue.main.async {
                            scrollToID = nil
                        }
                    }
                }
            }
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
                selectedImageFileIDs = []
                lastSelectedImageFileID = nil
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
    
    func moveFilesToTrash(_ files: [ImageFile]) {
        let fileURLs = files.map { $0.url }
        let ws = NSWorkspace.shared
        ws.recycle(fileURLs) { (newURLs, error) in
            if error == nil {
                DispatchQueue.main.async {
                    let idsToRemove = Set(files.map { $0.id })
                    imageFiles.removeAll { idsToRemove.contains($0.id) }
                    selectedImageFileIDs.subtract(idsToRemove)
                    if let lastID = self.lastSelectedImageFileID, idsToRemove.contains(lastID) {
                        self.lastSelectedImageFileID = nil
                    }
                }
            } else {
                // Optionally, show an error to the user
                print("Error recycling files: \(error?.localizedDescription ?? "unknown error")")
            }
        }
    }
    
    private func handleArrowKey(_ direction: ArrowDirection) {
        if previewedImageFile != nil {
            guard direction == .left || direction == .right else { return }
            let offset = direction == .left ? -1 : 1
            
            guard let currentFile = previewedImageFile, let currentIndex = imageFiles.firstIndex(of: currentFile) else { return }
            let newIndex = (currentIndex + offset + imageFiles.count) % imageFiles.count
            previewedImageFile = imageFiles[newIndex]

        } else {
            guard !imageFiles.isEmpty else { return }

            let offset: Int
            if viewMode == .grid {
                switch direction {
                case .up: offset = -gridColumnCount
                case .down: offset = gridColumnCount
                case .left: offset = -1
                case .right: offset = 1
                }
            } else { // List Mode
                switch direction {
                case .up, .left: offset = -1
                case .down, .right: offset = 1
                }
            }
            
            let newID: UUID
            if let lastID = lastSelectedImageFileID, let currentIndex = imageFiles.firstIndex(where: { $0.id == lastID }) {
                let newIndex = currentIndex + offset
                
                if viewMode == .grid {
                    if direction == .left && currentIndex % gridColumnCount == 0 { return }
                    if direction == .right && (currentIndex % gridColumnCount == gridColumnCount - 1 || currentIndex == imageFiles.count - 1) { return }
                }

                guard (0..<imageFiles.count).contains(newIndex) else { return }
                newID = imageFiles[newIndex].id

            } else {
                newID = imageFiles[0].id
            }

            selectedImageFileIDs = [newID]
            lastSelectedImageFileID = newID
            scrollToID = newID
        }
    }

    private func handleImageSelection(for fileID: UUID) {
        let modifiers = NSEvent.modifierFlags
        let isCommandPressed = modifiers.contains(.command)
        let isShiftPressed = modifiers.contains(.shift)

        if isShiftPressed, let lastID = lastSelectedImageFileID,
           let lastIndex = imageFiles.firstIndex(where: { $0.id == lastID }),
           let currentIndex = imageFiles.firstIndex(where: { $0.id == fileID })
        {
            let range = min(lastIndex, currentIndex)...max(lastIndex, currentIndex)
            let idsToSelect = imageFiles[range].map { $0.id }
            if isCommandPressed {
                selectedImageFileIDs.formUnion(idsToSelect)
            } else {
                selectedImageFileIDs = Set(idsToSelect)
            }
        } else if isCommandPressed {
            if selectedImageFileIDs.contains(fileID) {
                selectedImageFileIDs.remove(fileID)
            } else {
                selectedImageFileIDs.insert(fileID)
            }
            lastSelectedImageFileID = fileID
        } else {
            selectedImageFileIDs = [fileID]
            lastSelectedImageFileID = fileID
        }
    }
}

struct FileThumbnailView: View {
    let file: ImageFile
    let size: CGFloat
    @State private var thumbnailImage: NSImage?
    
    var body: some View {
        Group {
            if let image = thumbnailImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                placeholder
            }
        }
        .onAppear(perform: generateThumbnail)
        .onChange(of: file) {
            generateThumbnail()
        }
        .onChange(of: size) {
            generateThumbnail()
        }
    }
    
    private func generateThumbnail() {
        DispatchQueue.global(qos: .userInitiated).async {
            let image: NSImage?
            let thumbnailSize = CGSize(width: size * 2, height: size * 2) // Retina size for view size

            if ["jpg", "jpeg", "png", "gif", "tiff"].contains(file.url.pathExtension.lowercased()) {
                image = createThumbnail(for: file.url, size: thumbnailSize)
            } else if file.url.pathExtension.lowercased() == "pdf" {
                if let pdfDoc = PDFDocument(url: file.url), let page = pdfDoc.page(at: 0) {
                    image = page.thumbnail(of: thumbnailSize, for: .cropBox)
                } else {
                    image = nil
                }
            } else if file.url.pathExtension.lowercased() == "svg" {
                // For SVGs, we can load them directly as they are vector-based.
                image = NSImage(contentsOf: file.url)
            } else {
                image = nil
            }
            
            DispatchQueue.main.async {
                self.thumbnailImage = image
            }
        }
    }

    private func createThumbnail(for url: URL, size: CGSize) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(size.width, size.height)
        ]

        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            // Fallback to loading the full image if thumbnail creation fails
            return NSImage(contentsOf: url)
        }
        return NSImage(cgImage: cgImage, size: .zero)
    }
    
    var placeholder: some View {
        Image(systemName: "doc")
            .resizable()
            .scaledToFit()
            .foregroundColor(.gray)
            .opacity(0.5)
    }
}

struct PreviewView: View {
    let file: ImageFile
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 16) {
                Group {
                    if ["jpg", "jpeg", "png", "gif", "tiff", "svg"].contains(file.url.pathExtension.lowercased()) {
                        if let nsImage = NSImage(contentsOf: file.url) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .scaledToFit()
                        } else {
                            previewError
                        }
                    } else if file.url.pathExtension.lowercased() == "pdf" {
                        if let pdfDoc = PDFDocument(url: file.url), let page = pdfDoc.page(at: 0) {
                            let pageRect = page.bounds(for: .cropBox)
                            let image = page.thumbnail(of: NSSize(width: pageRect.width, height: pageRect.height), for: .cropBox)
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                        } else {
                            previewError
                        }
                    } else {
                        previewError
                    }
                }
                .shadow(radius: 20)

                Text(file.name)
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.top)
            }
            .padding(40)
        }
    }
    
    var previewError: some View {
        Text("Cannot preview this file type.")
            .foregroundColor(.white)
    }
}

struct KeyboardEventHandlingView: NSViewRepresentable {
    var onDeletePressed: () -> Void
    var onEscapePressed: () -> Void
    var onSpacebarPressed: () -> Void
    var onArrowPressed: (ContentView.ArrowDirection) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyCatcherView()
        view.onDeletePressed = onDeletePressed
        view.onEscapePressed = onEscapePressed
        view.onSpacebarPressed = onSpacebarPressed
        view.onArrowPressed = onArrowPressed
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    class KeyCatcherView: NSView {
        var onDeletePressed: (() -> Void)?
        var onEscapePressed: (() -> Void)?
        var onSpacebarPressed: (() -> Void)?
        var onArrowPressed: ((ContentView.ArrowDirection) -> Void)?

        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 51: // Delete
                onDeletePressed?()
            case 53: // Escape
                onEscapePressed?()
            case 49: // Spacebar
                onSpacebarPressed?()
            case 123: onArrowPressed?(.left)
            case 124: onArrowPressed?(.right)
            case 125: onArrowPressed?(.down)
            case 126: onArrowPressed?(.up)
            default:
                super.keyDown(with: event)
            }
        }
        override func viewDidMoveToWindow() {
            window?.makeFirstResponder(self)
        }
    }
}
