//
//  ContentView.swift
//  image-collector
//
//  Created by David Hoang on 6/8/25.
//
import SwiftUI
import PDFKit
import ImageIO

// MARK: - Performance Monitoring
class PerformanceMonitor: ObservableObject {
    static let shared = PerformanceMonitor()
    @Published var cacheHitRate: Double = 0.0
    @Published var totalRequests: Int = 0
    @Published var cacheHits: Int = 0
    
    private init() {}
    
    func recordCacheHit() {
        totalRequests += 1
        cacheHits += 1
        updateHitRate()
    }
    
    func recordCacheMiss() {
        totalRequests += 1
        updateHitRate()
    }
    
    private func updateHitRate() {
        if totalRequests > 0 {
            cacheHitRate = Double(cacheHits) / Double(totalRequests)
        }
    }
    
    func reset() {
        totalRequests = 0
        cacheHits = 0
        cacheHitRate = 0.0
    }
}

// MARK: - Image Cache
class ImageCache: ObservableObject {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, NSImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    
    private init() {
        // Create cache directory in app's cache folder
        let appCache = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = appCache.appendingPathComponent("MicroficheThumbnails")
        
        // Set cache limits
        cache.countLimit = 200 // Max 200 images in memory
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB limit
        
        // Create cache directory if it doesn't exist
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    func getImage(for url: URL, size: CGFloat) -> NSImage? {
        let key = cacheKey(for: url, size: size)
        
        // Check memory cache first
        if let cachedImage = cache.object(forKey: key as NSString) {
            PerformanceMonitor.shared.recordCacheHit()
            return cachedImage
        }
        
        // Check disk cache
        let cacheURL = cacheDirectory.appendingPathComponent(key)
        if let image = NSImage(contentsOf: cacheURL) {
            cache.setObject(image, forKey: key as NSString)
            PerformanceMonitor.shared.recordCacheHit()
            return image
        }
        
        PerformanceMonitor.shared.recordCacheMiss()
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
        let filename = url.lastPathComponent
        let sizeString = String(format: "%.0f", size)
        return "\(filename)_\(sizeString)"
    }
    
    func clearCache() {
        cache.removeAllObjects()
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
}

// MARK: - Optimized Image Loading
struct OptimizedAsyncImage: View {
    let url: URL
    let size: CGFloat
    @State private var image: NSImage?
    @State private var isLoading = false
    @State private var hasError = false
    
    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                ProgressView()
                    .scaleEffect(0.5)
            } else if hasError {
                Image(systemName: "photo")
                    .foregroundColor(.secondary)
                    .font(.system(size: size * 0.3))
            } else {
                Color.gray.opacity(0.1)
            }
        }
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        // Check cache first
        if let cachedImage = ImageCache.shared.getImage(for: url, size: size) {
            self.image = cachedImage
            return
        }
        
        // Load from disk
        isLoading = true
        hasError = false
        
        DispatchQueue.global(qos: .userInitiated).async {
            let image = loadAndResizeImage()
            DispatchQueue.main.async {
                self.isLoading = false
                if let image = image {
                    self.image = image
                    ImageCache.shared.setImage(image, for: url, size: size)
                } else {
                    self.hasError = true
                }
            }
        }
    }
    
    private func loadAndResizeImage() -> NSImage? {
        guard let sourceImage = NSImage(contentsOf: url) else { return nil }
        let targetSize = NSSize(width: size, height: size)
        let thumbnail = NSImage(size: targetSize)

        // Calculate aspect-fit rect
        let imageAspect = sourceImage.size.width / sourceImage.size.height
        let targetAspect = targetSize.width / targetSize.height
        var drawRect = NSRect(origin: .zero, size: targetSize)
        if imageAspect > targetAspect {
            // Image is wider than target: pillarbox
            let scaledHeight = targetSize.width / imageAspect
            drawRect.origin.y = (targetSize.height - scaledHeight) / 2
            drawRect.size = NSSize(width: targetSize.width, height: scaledHeight)
        } else {
            // Image is taller than target: letterbox
            let scaledWidth = targetSize.height * imageAspect
            drawRect.origin.x = (targetSize.width - scaledWidth) / 2
            drawRect.size = NSSize(width: scaledWidth, height: targetSize.height)
        }

        thumbnail.lockFocus()
        sourceImage.draw(in: drawRect,
                         from: NSRect(origin: .zero, size: sourceImage.size),
                         operation: .copy,
                         fraction: 1.0)
        thumbnail.unlockFocus()
        return thumbnail
    }
}

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
    @State private var showCacheMenu: Bool = false
    
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
            var added = false
            for url in openPanel.urls {
                if !folderURLs.contains(url) {
                    folderURLs.append(url)
                    added = true
                }
            }
            if selection == nil, let firstURL = openPanel.urls.first {
                selection = .folder(firstURL)
            }
            // Always refresh 'All' after adding folders
            if added {
                loadImages(from: folderURLs)
            }
        }
    }
    
    private func loadImages(from folderURLs: [URL]) {
        // Clear current images first for better performance
        imageFiles = []
        
        DispatchQueue.global(qos: .userInitiated).async {
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
            
            // Sort files by name for consistent ordering
            newImageFiles.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            
            DispatchQueue.main.async {
                self.imageFiles = newImageFiles
            }
        }
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
        let deletedIDs = Set(files.map { $0.id })
        let wasPreviewedDeleted = previewedImageFile != nil && deletedIDs.contains(previewedImageFile!.id)
        var previewIndex: Int? = nil
        if wasPreviewedDeleted, let current = previewedImageFile, let idx = imageFiles.firstIndex(of: current) {
            previewIndex = idx
        }
        
        for file in files {
            do {
                try FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
                imageFiles.removeAll { $0.id == file.id }
                selectedImageFileIDs.remove(file.id)
            } catch {
                print("Error moving file to trash: \(error)")
            }
        }
        
        // Handle preview advance
        if wasPreviewedDeleted {
            let remaining = imageFiles
            if let idx = previewIndex {
                // Try next image, else previous, else nil
                let nextIdx = idx < remaining.count ? idx : (remaining.count - 1)
                if nextIdx >= 0, nextIdx < remaining.count {
                    let nextFile = remaining[nextIdx]
                    previewedImageFile = nextFile
                    selectedImageFileIDs = [nextFile.id]
                    lastSelectedImageFileID = nextFile.id
                    scrollToID = nextFile.id
                } else {
                    previewedImageFile = nil
                }
            } else {
                previewedImageFile = nil
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
                    ZStack {
                        // Adaptive microfiche sheet background
                        Color(nsColor: NSColor.windowBackgroundColor)
                            .opacity(0.7)
                            .edgesIgnoringSafeArea(.all)
                        LazyVGrid(columns: Array(repeating: .init(.flexible(), spacing: 20), count: columnCount), spacing: 20) {
                            ForEach(imageFiles) { file in
                                VStack {
                                    FileThumbnailView(file: file, size: thumbnailSizeValue, onRename: onRename)
                                        .frame(width: thumbnailSizeValue, height: thumbnailSizeValue)
                                }
                                .padding(6)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color(NSColor.controlBackgroundColor))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(
                                            selectedImageFileIDs.contains(file.id) ? Color.accentColor : Color(NSColor.separatorColor),
                                            lineWidth: selectedImageFileIDs.contains(file.id) ? 4 : 3
                                        )
                                        .shadow(color: selectedImageFileIDs.contains(file.id) ? Color.accentColor.opacity(0.4) : .clear, radius: selectedImageFileIDs.contains(file.id) ? 10 : 0)
                                )
                                .id(file.id)
                                .onTapGesture {
                                    onSelectImage(file.id)
                                }
                                .onAppear {
                                    prefetchNearbyImages(for: file)
                                }
                            }
                        }
                        .padding(.horizontal, 32)
                        .padding(.vertical, 56)
                    }
                }
                .onChange(of: scrollToID) { _, newID in
                    if let id = newID {
                        withAnimation(.easeInOut(duration: 0.3)) {
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
            .animation(.spring(), value: thumbnailSize)
        }
        
        private func prefetchNearbyImages(for file: ImageFile) {
            guard let currentIndex = imageFiles.firstIndex(where: { $0.id == file.id }) else { return }
            
            // Prefetch next 5 images
            let prefetchRange = (currentIndex + 1)..<min(currentIndex + 6, imageFiles.count)
            for index in prefetchRange {
                let prefetchFile = imageFiles[index]
                if prefetchFile.url.pathExtension.lowercased() != "pdf" && 
                   prefetchFile.url.pathExtension.lowercased() != "svg" {
                    // Trigger cache load for nearby images
                    DispatchQueue.global(qos: .background).async {
                        _ = ImageCache.shared.getImage(for: prefetchFile.url, size: thumbnailSizeValue)
                    }
                }
            }
        }
        
        private func updateColumnCount(for size: GridThumbnailSize) {
            columnCount = size == .large ? 4 : (size == .medium ? 5 : 8)
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
                        .onAppear {
                            // Prefetch nearby images in list view
                            prefetchNearbyImages(for: file)
                        }
                    }
                }
                .listStyle(PlainListStyle())
                .onChange(of: scrollToID) { _, newID in
                    if let id = newID {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                        DispatchQueue.main.async {
                            scrollToID = nil
                        }
                    }
                }
            }
        }
        
        private func prefetchNearbyImages(for file: ImageFile) {
            guard let currentIndex = imageFiles.firstIndex(where: { $0.id == file.id }) else { return }
            
            // Prefetch next 10 images in list view (more since list view shows more items)
            let prefetchRange = (currentIndex + 1)..<min(currentIndex + 11, imageFiles.count)
            for index in prefetchRange {
                let prefetchFile = imageFiles[index]
                if prefetchFile.url.pathExtension.lowercased() != "pdf" && 
                   prefetchFile.url.pathExtension.lowercased() != "svg" {
                    // Trigger cache load for nearby images
                    DispatchQueue.global(qos: .background).async {
                        _ = ImageCache.shared.getImage(for: prefetchFile.url, size: 40)
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
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.8)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture(perform: onDismiss)

                // Centered preview container
                VStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(NSColor.controlBackgroundColor))
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 4)
                        Group {
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
                        .padding(32)
                    }
                    .frame(width: geometry.size.width * 0.75, height: geometry.size.height * 0.75)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        ZStack {
            // Consistent cell background
            Color(NSColor.controlBackgroundColor)
            Group {
                if file.url.pathExtension.lowercased() == "pdf" {
                    PDFThumbnailView(url: file.url, size: size)
                        .aspectRatio(contentMode: .fit)
                } else if file.url.pathExtension.lowercased() == "svg" {
                    SVGThumbnailView(url: file.url)
                        .aspectRatio(contentMode: .fit)
                } else {
                    OptimizedAsyncImage(url: file.url, size: size)
                        .aspectRatio(contentMode: .fit)
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(width: size, height: size)
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
        // Check cache first
        if let cachedImage = ImageCache.shared.getImage(for: url, size: size) {
            self.thumbnail = cachedImage
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            guard let pdfDocument = PDFDocument(url: url),
                  let page = pdfDocument.page(at: 0) else {
                return
            }
            let image = page.thumbnail(of: .init(width: size * 2, height: size * 2), for: .cropBox)
            DispatchQueue.main.async {
                self.thumbnail = image
                ImageCache.shared.setImage(image, for: url, size: size)
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
