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
    @State private var selection: Selection?
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
    
    enum Selection: Hashable {
        case all
        case folder(URL)
    }
    
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
                    selection: selection,
                    onLinkFolder: linkFolder,
                    onSelect: { newSelection in
                        selection = newSelection
                    },
                    onRemoveFolder: removeFolder
                )
            } detail: {
                MainContentView(
                    imageFiles: imageFiles,
                    viewMode: $viewMode,
                    gridThumbnailSize: $gridThumbnailSize,
                    gridColumnCount: $gridColumnCount,
                    selectedImageFileIDs: $selectedImageFileIDs,
                    onSelectImage: handleImageSelection,
                    scrollToID: $scrollToID,
                    onRename: renameFile
                )
            }
            .navigationTitle("")
            .onAppear {
                // Optionally, load persisted folders here
            }
            .onChange(of: selection) { oldValue, newValue in
                switch newValue {
                case .all:
                    loadImages(from: folderURLs)
                case .folder(let url):
                    loadImages(from: [url])
                case .none:
                    imageFiles = []
                }
                selectedImageFileIDs = []
                lastSelectedImageFileID = nil
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

    private func linkFolder() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = true
        
        if openPanel.runModal() == .OK {
            for url in openPanel.urls {
                if !folderURLs.contains(url) {
                    folderURLs.append(url)
                }
            }
            if selection == nil, let firstURL = openPanel.urls.first {
                selection = .folder(firstURL)
            }
        }
    }
    
    private func loadImages(from folderURLs: [URL]) {
        var newImageFiles: [ImageFile] = []
        let fileManager = FileManager.default
        
        for folderURL in folderURLs {
            if let enumerator = fileManager.enumerator(at: folderURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                for case let fileURL as URL in enumerator {
                    if supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                        newImageFiles.append(ImageFile(url: fileURL))
                    }
                }
            }
        }
        imageFiles = newImageFiles
    }
    
    private func handleImageSelection(for fileID: UUID) {
        if NSApp.currentEvent?.modifierFlags.contains(.shift) == true, let lastID = lastSelectedImageFileID, let lastIndex = imageFiles.firstIndex(where: { $0.id == lastID }), let currentIndex = imageFiles.firstIndex(where: { $0.id == fileID }) {
            let range = min(lastIndex, currentIndex)...max(lastIndex, currentIndex)
            selectedImageFileIDs = Set(imageFiles[range].map { $0.id })
        } else if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
            if selectedImageFileIDs.contains(fileID) {
                selectedImageFileIDs.remove(fileID)
            } else {
                selectedImageFileIDs.insert(fileID)
            }
        } else {
            selectedImageFileIDs = [fileID]
        }
        lastSelectedImageFileID = fileID
    }
    
    private func moveFilesToTrash(_ files: [ImageFile]) {
        for file in files {
            do {
                try FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
                imageFiles.removeAll { $0.id == file.id }
                selectedImageFileIDs.remove(file.id)
            } catch {
                print("Error moving file to trash: \(error)")
            }
        }
    }
    
    private func handleArrowKey(_ direction: ArrowDirection) {
        guard !imageFiles.isEmpty else { return }

        if let currentFile = previewedImageFile, let currentIndex = imageFiles.firstIndex(of: currentFile) {
            var nextIndex: Int?
            
            switch direction {
            case .left:
                if currentIndex > 0 {
                    nextIndex = currentIndex - 1
                }
            case .right:
                if currentIndex < imageFiles.count - 1 {
                    nextIndex = currentIndex + 1
                }
            default:
                break // Up/Down do nothing in preview
            }
            
            if let newIndex = nextIndex {
                let nextFile = imageFiles[newIndex]
                previewedImageFile = nextFile
                // Also update selection to follow the preview
                selectedImageFileIDs = [nextFile.id]
                lastSelectedImageFileID = nextFile.id
                scrollToID = nextFile.id
            }
            return // End here if we were in preview mode
        }

        let sortedFiles = imageFiles
        
        guard let lastID = lastSelectedImageFileID, let currentIndex = sortedFiles.firstIndex(where: { $0.id == lastID }) else {
            if let firstFile = sortedFiles.first {
                selectedImageFileIDs = [firstFile.id]
                lastSelectedImageFileID = firstFile.id
                scrollToID = firstFile.id
            }
            return
        }

        var nextIndex: Int?
        
        switch direction {
        case .up:
            if currentIndex >= gridColumnCount {
                nextIndex = currentIndex - gridColumnCount
            }
        case .down:
            if currentIndex + gridColumnCount < sortedFiles.count {
                nextIndex = currentIndex + gridColumnCount
            }
        case .left:
            if currentIndex > 0 {
                nextIndex = currentIndex - 1
            }
        case .right:
            if currentIndex < sortedFiles.count - 1 {
                nextIndex = currentIndex + 1
            }
        }
        
        if let newIndex = nextIndex {
            let nextFile = sortedFiles[newIndex]
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                selectedImageFileIDs.insert(nextFile.id)
            } else {
                selectedImageFileIDs = [nextFile.id]
            }
            lastSelectedImageFileID = nextFile.id
            scrollToID = nextFile.id
        }
    }
    
    private func renameFile(from oldURL: URL, to newName: String) {
        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(newName)
        do {
            try FileManager.default.moveItem(at: oldURL, to: newURL)
            // Update the state
            if let index = imageFiles.firstIndex(where: { $0.url == oldURL }) {
                imageFiles[index] = ImageFile(url: newURL)
            }
            if let index = folderURLs.firstIndex(of: oldURL) {
                folderURLs[index] = newURL
            }
        } catch {
            print("Error renaming file: \(error)")
        }
    }
    
    private func removeFolder(_ url: URL) {
        if let index = folderURLs.firstIndex(of: url) {
            let wasSelected = (selection == .folder(url))
            folderURLs.remove(at: index)

            if wasSelected {
                if !folderURLs.isEmpty {
                    let newIndex = min(index, folderURLs.count - 1)
                    selection = .folder(folderURLs[newIndex])
                } else {
                    selection = .all
                }
            }
        }
    }
    
    private struct EditableFileNameView: View {
        let file: ImageFile
        let onRename: (URL, String) -> Void
        
        @State private var isEditing = false
        @State private var newName: String
        @FocusState private var isFocused: Bool

        init(file: ImageFile, onRename: @escaping (URL, String) -> Void) {
            self.file = file
            self.onRename = onRename
            _newName = State(initialValue: file.name)
        }
        
        var body: some View {
            if isEditing {
                TextField("New name", text: $newName, onCommit: {
                    onRename(file.url, newName)
                    isEditing = false
                })
                .focused($isFocused)
                .onChange(of: isFocused) { oldValue, newValue in
                    if !newValue {
                        isEditing = false
                    }
                }
            } else {
                Text(file.name)
                    .highPriorityGesture(
                        TapGesture(count: 2)
                            .onEnded {
                                self.isEditing = true
                                self.isFocused = true
                            }
                    )
            }
        }
    }
    
    private struct SidebarView: View {
        let folderURLs: [URL]
        let selection: Selection?
        let onLinkFolder: () -> Void
        let onSelect: (Selection) -> Void
        let onRemoveFolder: (URL) -> Void
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("Folders")
                    .font(.headline)
                    .padding([.top, .horizontal])

                List {
                    HStack {
                        Image(systemName: "photo.stack")
                        Text("All")
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onSelect(.all)
                    }
                    .background(selection == .all ? Color.accentColor.opacity(0.2) : Color.clear)
                    
                    ForEach(folderURLs, id: \.self) { url in
                        HStack {
                            Image(systemName: "folder")
                            Text(url.lastPathComponent)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelect(.folder(url))
                        }
                        .background(selection == .folder(url) ? Color.accentColor.opacity(0.2) : Color.clear)
                        .contextMenu {
                            Button("Remove Folder", role: .destructive) {
                                onRemoveFolder(url)
                            }
                        }
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
        @Binding var scrollToID: UUID?
        let onRename: (URL, String) -> Void
        var body: some View {
            VStack {
                if imageFiles.isEmpty {
                    Spacer()
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary.opacity(0.6))
                        .padding(.bottom)
                    Text("No images found. Link a folder to begin.")
                        .foregroundColor(.secondary)
                    Spacer()
                } else {
                    if viewMode == .grid {
                        ImageGridView(imageFiles: imageFiles, selectedImageFileIDs: $selectedImageFileIDs, onSelectImage: onSelectImage, thumbnailSize: gridThumbnailSize, scrollToID: $scrollToID, columnCount: $gridColumnCount, onRename: onRename)
                    } else {
                        ImageListView(imageFiles: imageFiles, selectedImageFileIDs: $selectedImageFileIDs, onSelectImage: onSelectImage, scrollToID: $scrollToID, onRename: onRename)
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
        let thumbnailSize: GridThumbnailSize
        @Binding var scrollToID: UUID?
        @Binding var columnCount: Int
        let onRename: (URL, String) -> Void
        
        var body: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: Array(repeating: .init(.flexible()), count: columnCount), spacing: 20) {
                        ForEach(imageFiles) { file in
                            VStack {
                                FileThumbnailView(file: file, size: thumbnailSizeValue, onRename: onRename)
                                    .frame(width: thumbnailSizeValue, height: thumbnailSizeValue)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(8)
                                    .onTapGesture {
                                        onSelectImage(file.id)
                                    }
                                EditableFileNameView(file: file, onRename: onRename)
                                    .font(.caption)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(4)
                            .background(selectedImageFileIDs.contains(file.id) ? Color.accentColor.opacity(0.2) : Color.clear)
                            .cornerRadius(8)
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
                .onChange(of: thumbnailSize) { _, newSize in
                    updateColumnCount(for: newSize)
                }
                .onAppear {
                    updateColumnCount(for: thumbnailSize)
                }
            }
        }
        
        private func updateColumnCount(for size: GridThumbnailSize) {
            columnCount = size == .large ? 3 : (size == .medium ? 5 : 8)
        }
        
        private var thumbnailSizeValue: CGFloat {
            switch thumbnailSize {
            case .small: return 80
            case .medium: return 120
            case .large: return 180
            }
        }
    }

    private struct ImageListView: View {
        let imageFiles: [ImageFile]
        @Binding var selectedImageFileIDs: Set<UUID>
        let onSelectImage: (UUID) -> Void
        @Binding var scrollToID: UUID?
        let onRename: (URL, String) -> Void

        var body: some View {
            ScrollViewReader { proxy in
                List {
                    ForEach(imageFiles) { file in
                        HStack {
                            FileThumbnailView(file: file, size: 40, onRename: onRename)
                                .frame(width: 40, height: 40)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(6)
                            VStack(alignment: .leading) {
                                EditableFileNameView(file: file, onRename: onRename)
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
}

struct PreviewView: View {
    let file: ImageFile
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.8)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture(perform: onDismiss)
            
            if file.url.pathExtension.lowercased() == "pdf" {
                PDFKitView(url: file.url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if file.url.pathExtension.lowercased() == "svg" {
                SVGImageView(url: file.url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .aspectRatio(contentMode: .fit)
            } else {
                AsyncImage(url: file.url) { image in
                    image.resizable()
                         .aspectRatio(contentMode: .fit)
                } placeholder: {
                    ProgressView()
                }
            }
        }
    }
}

struct PDFKitView: NSViewRepresentable {
    let url: URL
    
    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = PDFDocument(url: self.url)
        pdfView.autoScales = true
        return pdfView
    }
    
    func updateNSView(_ nsView: PDFView, context: Context) {
        nsView.document = PDFDocument(url: self.url)
    }
}

struct SVGImageView: NSViewRepresentable {
    let url: URL
    
    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.image = NSImage(contentsOf: url)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        return imageView
    }
    
    func updateNSView(_ nsView: NSImageView, context: Context) {
        nsView.image = NSImage(contentsOf: url)
    }
}

struct FileThumbnailView: View {
    let file: ImageFile
    let size: CGFloat
    let onRename: (URL, String) -> Void

    var body: some View {
        if file.url.pathExtension.lowercased() == "pdf" {
            PDFThumbnailView(url: file.url, size: size)
        } else if file.url.pathExtension.lowercased() == "svg" {
            SVGThumbnailView(url: file.url)
        } else {
            AsyncImage(url: file.url) { image in
                image.resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.gray.opacity(0.1)
            }
            .frame(width: size, height: size)
            .clipped()
        }
    }
}

struct PDFThumbnailView: View {
    let url: URL
    let size: CGFloat

    @State private var thumbnail: NSImage?

    var body: some View {
        Group {
            if let image = thumbnail {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.gray.opacity(0.1)
            }
        }
        .onAppear(perform: generateThumbnail)
    }

    private func generateThumbnail() {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let pdfDocument = PDFDocument(url: url),
                  let page = pdfDocument.page(at: 0) else {
                return
            }
            let image = page.thumbnail(of: .init(width: size * 2, height: size * 2), for: .cropBox)
            DispatchQueue.main.async {
                self.thumbnail = image
            }
        }
    }
}

struct SVGThumbnailView: View {
    let url: URL
    
    var body: some View {
        if let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Color.gray.opacity(0.1)
        }
    }
}

struct KeyboardEventHandlingView: NSViewRepresentable {
    var onDeletePressed: () -> Void
    var onEscapePressed: () -> Void
    var onSpacebarPressed: () -> Void
    var onArrowPressed: (ContentView.ArrowDirection) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyView()
        view.onDeletePressed = onDeletePressed
        view.onEscapePressed = onEscapePressed
        view.onSpacebarPressed = onSpacebarPressed
        view.onArrowPressed = onArrowPressed
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
    
    class KeyView: NSView {
        var onDeletePressed: (() -> Void)?
        var onEscapePressed: (() -> Void)?
        var onSpacebarPressed: (() -> Void)?
        var onArrowPressed: ((ContentView.ArrowDirection) -> Void)?
        
        override var acceptsFirstResponder: Bool { true }
        
        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 51: // Backspace/Delete
                onDeletePressed?()
            case 53: // Escape
                onEscapePressed?()
            case 49: // Spacebar
                onSpacebarPressed?()
            case 123: // Left arrow
                onArrowPressed?(.left)
            case 124: // Right arrow
                onArrowPressed?(.right)
            case 125: // Down arrow
                onArrowPressed?(.down)
            case 126: // Up arrow
                onArrowPressed?(.up)
            default:
                super.keyDown(with: event)
            }
        }
    }
}
