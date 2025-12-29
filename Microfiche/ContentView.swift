//
//  ContentView.swift
//  image-collector
//
//  Created by David Hoang on 6/8/25.
//
import SwiftUI
import PDFKit
import ImageIO
import UniformTypeIdentifiers



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
            print("✅ Cache hit for \(url.lastPathComponent) at path: \(url.path)")
            self.image = cachedImage
            return
        }
        
        // Load from disk
        isLoading = true
        hasError = false
        print("🔄 Loading image for \(url.lastPathComponent) at path: \(url.path)")
        
        DispatchQueue.global(qos: .userInitiated).async {
            let image = loadAndResizeImage()
            DispatchQueue.main.async {
                self.isLoading = false
                if let image = image {
                    self.image = image
                    ImageCache.shared.setImage(image, for: url, size: size)
                    print("✅ Loaded and cached \(url.lastPathComponent)")
                } else {
                    self.hasError = true
                    print("❌ Failed to load \(url.lastPathComponent)")
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


// MARK: - Image Detail View
struct ImageDetailView: View {
    let file: ImageFile
    let onBack: () -> Void

    @State private var tags: [String] = []
    @State private var labels: [String] = []
    @State private var comments: String = ""
    @State private var whereFrom: String = ""
    @State private var isEditingTags = false
    @State private var isEditingLabels = false
    @State private var isEditingComments = false
    @State private var isEditingWhereFrom = false
    @State private var newTag: String = ""
    @State private var newLabel: String = ""
    @State private var escapeMonitor: Any?
    @State private var detailImage: NSImage?
    @State private var isLoadingImage = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: onBack) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
                .buttonStyle(BorderlessButtonStyle())
                
                Spacer()
                
                Text(file.name)
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
                // Placeholder for potential future actions
                HStack(spacing: 16) {
                    Button(action: {
                        saveMetadata()
                    }) {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .help("Save metadata")
                    
                    Button(action: {}) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    
                    Button(action: {}) {
                        Image(systemName: "ellipsis.circle")
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Main content
            HStack(spacing: 0) {
                // Left side - Image
                VStack {
                    if file.url.pathExtension.lowercased() == "pdf" {
                        PDFKitView(url: file.url)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if file.url.pathExtension.lowercased() == "svg" {
                        SVGImageView(url: file.url)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .aspectRatio(contentMode: .fit)
                    } else {
                        if let image = detailImage {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } else if isLoadingImage {
                            ProgressView()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
                .onAppear {
                    loadDetailImage()
                }
                
                Divider()
                
                // Right side - Metadata
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Tags Section
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Tags")
                                    .font(.headline)
                                Spacer()
                                Button(action: { 
                                    isEditingTags.toggle()
                                    if !isEditingTags {
                                        saveMetadata()
                                    }
                                }) {
                                    Image(systemName: isEditingTags ? "checkmark" : "plus")
                                }
                                .buttonStyle(BorderlessButtonStyle())
                            }
                            
                            if isEditingTags {
                                HStack {
                                    TextField("Add tag", text: $newTag)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                    Button("Add") {
                                        if !newTag.isEmpty && !tags.contains(newTag) {
                                            tags.append(newTag)
                                            newTag = ""
                                            saveMetadata()
                                        }
                                    }
                                    .buttonStyle(BorderlessButtonStyle())
                                }
                            }
                            
                            if tags.isEmpty {
                                Text("No tags")
                                    .foregroundColor(.secondary)
                                    .italic()
                            } else {
                                LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 2), spacing: 8) {
                                    ForEach(tags, id: \.self) { tag in
                                        HStack {
                                            Text(tag)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.accentColor.opacity(0.2))
                                                .cornerRadius(8)
                                            Spacer()
                                            if isEditingTags {
                                                Button(action: { 
                                                    tags.removeAll { $0 == tag }
                                                    saveMetadata()
                                                }) {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .foregroundColor(.red)
                                                }
                                                .buttonStyle(BorderlessButtonStyle())
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Labels Section
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Labels")
                                    .font(.headline)
                                Spacer()
                                Button(action: { 
                                    isEditingLabels.toggle()
                                    if !isEditingLabels {
                                        saveMetadata()
                                    }
                                }) {
                                    Image(systemName: isEditingLabels ? "checkmark" : "plus")
                                }
                                .buttonStyle(BorderlessButtonStyle())
                            }
                            
                            if isEditingLabels {
                                HStack {
                                    TextField("Add label", text: $newLabel)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                    Button("Add") {
                                        if !newLabel.isEmpty && !labels.contains(newLabel) {
                                            labels.append(newLabel)
                                            newLabel = ""
                                            saveMetadata()
                                        }
                                    }
                                    .buttonStyle(BorderlessButtonStyle())
                                }
                            }
                            
                            if labels.isEmpty {
                                Text("No labels")
                                    .foregroundColor(.secondary)
                                    .italic()
                            } else {
                                LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 2), spacing: 8) {
                                    ForEach(labels, id: \.self) { label in
                                        HStack {
                                            Text(label)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.orange.opacity(0.2))
                                                .cornerRadius(8)
                                            Spacer()
                                            if isEditingLabels {
                                                Button(action: { 
                                                    labels.removeAll { $0 == label }
                                                    saveMetadata()
                                                }) {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .foregroundColor(.red)
                                                }
                                                .buttonStyle(BorderlessButtonStyle())
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Comments Section
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Comments")
                                    .font(.headline)
                                Spacer()
                                Button(action: {
                                    isEditingComments.toggle()
                                    if !isEditingComments {
                                        saveMetadata()
                                    }
                                }) {
                                    Image(systemName: isEditingComments ? "checkmark" : "pencil")
                                }
                                .buttonStyle(BorderlessButtonStyle())
                            }
                            if isEditingComments {
                                TextEditor(text: $comments)
                                    .frame(minHeight: 100)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .onChange(of: comments) { _ in
                                        saveMetadata()
                                    }
                            } else {
                                if comments.isEmpty {
                                    Text("No comments")
                                        .foregroundColor(.secondary)
                                        .italic()
                                } else {
                                    Text(comments)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        
                        // Where From Section
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Where From")
                                    .font(.headline)
                                Spacer()
                                Button(action: {
                                    isEditingWhereFrom.toggle()
                                    if !isEditingWhereFrom {
                                        saveMetadata()
                                    }
                                }) {
                                    Image(systemName: isEditingWhereFrom ? "checkmark" : "pencil")
                                }
                                .buttonStyle(BorderlessButtonStyle())
                            }
                            if isEditingWhereFrom {
                                TextField("Enter source", text: $whereFrom)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .onSubmit {
                                        saveMetadata()
                                    }
                                    .onChange(of: whereFrom) { _ in
                                        saveMetadata()
                                    }
                            } else {
                                if whereFrom.isEmpty {
                                    Text("No source specified")
                                        .foregroundColor(.secondary)
                                        .italic()
                                } else {
                                    Text(whereFrom)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        
                        // File Info Section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("File Info")
                                .font(.headline)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                InfoRow(label: "Name", value: file.name)
                                InfoRow(label: "Path", value: file.url.path)
                                InfoRow(label: "Type", value: file.url.pathExtension.uppercased())
                                
                                if let fileSize = getFileSize() {
                                    InfoRow(label: "Size", value: fileSize)
                                }
                                
                                if let creationDate = getCreationDate() {
                                    InfoRow(label: "Created", value: creationDate)
                                }
                                
                                if let modificationDate = getModificationDate() {
                                    InfoRow(label: "Modified", value: modificationDate)
                                }
                            }
                        }
                    }
                    .padding()
                }
                .frame(width: 300)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .onAppear {
            loadMetadata()
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 { // Escape
                    onBack()
                    return nil // Don't propagate
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = escapeMonitor {
                NSEvent.removeMonitor(monitor)
                escapeMonitor = nil
            }
            saveMetadata()
        }
    }
    
    private func loadMetadata() {
        // Load saved metadata from file system attributes
        print("🔍 Attempting to load metadata for: \(file.name)")
        print("📁 File path: \(file.url.path)")
        
        var loadedFromFileSystem = false
        
        // Try to load from extended attributes first
        if let tagsData = try? file.url.extendedAttribute(forName: "com.microfiche.tags"),
           let tagsString = String(data: tagsData, encoding: .utf8) {
            tags = tagsString.components(separatedBy: ",").filter { !$0.isEmpty }
            print("✅ Loaded tags: \(tags)")
            loadedFromFileSystem = true
        } else {
            print("ℹ️ No tags found or error loading tags")
        }
        
        if let labelsData = try? file.url.extendedAttribute(forName: "com.microfiche.labels"),
           let labelsString = String(data: labelsData, encoding: .utf8) {
            labels = labelsString.components(separatedBy: ",").filter { !$0.isEmpty }
            print("✅ Loaded labels: \(labels)")
            loadedFromFileSystem = true
        } else {
            print("ℹ️ No labels found or error loading labels")
        }
        
        if let commentsData = try? file.url.extendedAttribute(forName: "com.microfiche.comments"),
           let commentsString = String(data: commentsData, encoding: .utf8) {
            comments = commentsString
            print("✅ Loaded comments: \(comments)")
            loadedFromFileSystem = true
        } else {
            print("ℹ️ No comments found or error loading comments")
        }
        
        if let whereFromData = try? file.url.extendedAttribute(forName: "com.microfiche.whereFrom"),
           let whereFromString = String(data: whereFromData, encoding: .utf8) {
            whereFrom = whereFromString
            print("✅ Loaded whereFrom: \(whereFrom)")
            loadedFromFileSystem = true
        } else {
            print("ℹ️ No whereFrom found or error loading whereFrom")
        }
        
        if loadedFromFileSystem {
            print("✅ Metadata loaded from file system for \(file.name)")
        } else {
            print("🔄 No file system metadata found, trying UserDefaults")
            loadFromUserDefaults()
        }
    }
    
    private func saveMetadata() {
        do {
            print("💾 Attempting to save metadata for: \(file.name)")
            print("📁 File path: \(file.url.path)")
            
            // Check if file is writable
            guard FileManager.default.isWritableFile(atPath: file.url.path) else {
                print("❌ File is not writable: \(file.url.path)")
                saveToUserDefaults() // Fallback to UserDefaults
                return
            }
            
            // Save Finder comment
            print("💬 Saving Finder comment: \(comments)")
            try file.url.setFinderComment(comments)
            
            // Save Finder tags and labels
            print("🏷️ Saving Finder tags: \(tags), labels: \(labels)")
            try file.url.setFinderTagsAndLabels(tags: tags, labels: labels)
            
            print("✅ Finder metadata saved for \(file.name)")
            
            // Verify the save by listing extended attributes
            do {
                let attributes = try file.url.listExtendedAttributes()
                print("🔍 Extended attributes on file: \(attributes)")
            } catch {
                print("⚠️ Could not verify extended attributes: \(error)")
            }
            
        } catch {
            print("❌ Error saving Finder metadata for \(file.name): \(error)")
            print("❌ Error details: \(error.localizedDescription)")
            
            // Try to get more specific error information
            if let posixError = error as? POSIXError {
                print("❌ POSIX Error code: \(posixError.code.rawValue)")
                print("❌ POSIX Error description: \(posixError.localizedDescription)")
            }
            
            // Fallback to UserDefaults
            print("🔄 Falling back to UserDefaults storage")
            saveToUserDefaults()
        }
    }
    
    private func saveToUserDefaults() {
        let metadata = [
            "tags": tags,
            "labels": labels,
            "comments": comments,
            "whereFrom": whereFrom
        ] as [String : Any]
        
        let key = "metadata_\(file.id.uuidString)"
        UserDefaults.standard.set(metadata, forKey: key)
        UserDefaults.standard.synchronize()
        print("✅ Metadata saved to UserDefaults for \(file.name)")
    }
    
    private func loadFromUserDefaults() {
        let key = "metadata_\(file.id.uuidString)"
        if let metadata = UserDefaults.standard.dictionary(forKey: key) {
            tags = metadata["tags"] as? [String] ?? []
            labels = metadata["labels"] as? [String] ?? []
            comments = metadata["comments"] as? String ?? ""
            whereFrom = metadata["whereFrom"] as? String ?? ""
            print("✅ Metadata loaded from UserDefaults for \(file.name)")
        }
    }
    
    private func getFileSize() -> String? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.url.path)
            if let size = attributes[.size] as? Int64 {
                return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            }
        } catch {
            print("Error getting file size: \(error)")
        }
        return nil
    }
    
    private func getCreationDate() -> String? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.url.path)
            if let date = attributes[.creationDate] as? Date {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                return formatter.string(from: date)
            }
        } catch {
            print("Error getting creation date: \(error)")
        }
        return nil
    }
    
    private func getModificationDate() -> String? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.url.path)
            if let date = attributes[.modificationDate] as? Date {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                return formatter.string(from: date)
            }
        } catch {
            print("Error getting modification date: \(error)")
        }
        return nil
    }

    private func loadDetailImage() {
        // Check cache first for instant display
        if let cached = PreviewImageCache.shared.getImage(for: file.url) {
            self.detailImage = cached
            self.isLoadingImage = false
            return
        }

        // If not cached, load it
        PreviewImageCache.shared.preloadImage(for: file.url) { image in
            self.detailImage = image
            self.isLoadingImage = false
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
            Spacer()
        }
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
    @State private var detailViewFile: ImageFile?
    @StateObject private var contactSheetStorage = ContactSheetStorage.shared

    let supportedExtensions = ["jpg", "jpeg", "png", "pdf", "svg", "gif", "tiff"]
    
    enum Selection: Hashable {
        case all
        case folder(URL)
        case contactSheet(UUID)
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
            if let detailFile = detailViewFile {
                ImageDetailView(file: detailFile) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        detailViewFile = nil
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            } else {
                NavigationSplitView {
                    SidebarView(
                        folderURLs: folderURLs,
                        contactSheets: contactSheetStorage.contactSheets,
                        selection: selection,
                        onLinkFolder: linkFolder,
                        onSelect: { newSelection in
                            selection = newSelection
                        },
                        onRemoveFolder: removeFolder,
                        onCreateContactSheet: {
                            let newSheet = contactSheetStorage.createContactSheet()
                            selection = .contactSheet(newSheet.id)
                        },
                        onRenameContactSheet: { id, newName in
                            contactSheetStorage.renameContactSheet(id: id, newName: newName)
                        },
                        onDeleteContactSheet: { id in
                            contactSheetStorage.deleteContactSheet(id: id)
                            if selection == .contactSheet(id) {
                                selection = .all
                            }
                        },
                        onDropToContactSheet: { sheetID, urls in
                            handleDropToContactSheet(sheetID: sheetID, urls: urls)
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
                        onDoubleClickImage: handleDoubleClickImage,
                        scrollToID: $scrollToID,
                        onRename: renameFile,
                        contactSheets: contactSheetStorage.contactSheets,
                        onAddToContactSheet: handleAddToContactSheet
                    )
                }
                .navigationTitle("")
                .onAppear {
                    // Optionally, load persisted folders here
                }
                .onChange(of: selection) { newValue in
                    switch newValue {
                    case .all:
                        loadImages(from: folderURLs)
                    case .folder(let url):
                        loadImages(from: [url])
                    case .contactSheet(let id):
                        imageFiles = contactSheetStorage.getImages(for: id)
                        // Preload entire contact sheet immediately
                        let urls = imageFiles.map { $0.url }
                        PreviewImageCache.shared.preloadLibrary(urls: urls, priority: .userInitiated)
                    case .none:
                        imageFiles = []
                    }
                    selectedImageFileIDs = []
                    lastSelectedImageFileID = nil
                }
                .onChange(of: showDeleteAlert) { isShowing in
                    if !isShowing {
                        pendingDeleteFiles = []
                    }
                }
                .background(KeyboardEventHandlingView(
                    onDeletePressed: { bypassConfirmation in
                        let filesToDelete = imageFiles.filter { selectedImageFileIDs.contains($0.id) }
                        if !filesToDelete.isEmpty {
                            if bypassConfirmation {
                                moveFilesToTrash(filesToDelete)
                            } else if dontAskAgain {
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
        }
        .animation(.easeInOut(duration: 0.3), value: detailViewFile)
        .animation(.easeInOut(duration: 0.08), value: previewedImageFile)
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

    private func handleDropToContactSheet(sheetID: UUID, urls: [URL]) {
        for url in urls {
            // Validate file type
            guard supportedExtensions.contains(url.pathExtension.lowercased()) else {
                continue
            }

            // Add image to contact sheet (copies file to permanent storage)
            _ = contactSheetStorage.addImage(from: url, to: sheetID)
        }

        // If this contact sheet is currently selected, refresh the view
        if selection == .contactSheet(sheetID) {
            imageFiles = contactSheetStorage.getImages(for: sheetID)
        }
    }

    private func handleAddToContactSheet(sheetID: UUID, imageURL: URL) {
        // Validate file type
        guard supportedExtensions.contains(imageURL.pathExtension.lowercased()) else {
            return
        }

        // Add image to contact sheet (copies file to permanent storage)
        _ = contactSheetStorage.addImage(from: imageURL, to: sheetID)

        // If this contact sheet is currently selected, refresh the view
        if selection == .contactSheet(sheetID) {
            imageFiles = contactSheetStorage.getImages(for: sheetID)
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
                // Preload entire library immediately for instant previews
                let urls = newImageFiles.map { $0.url }
                PreviewImageCache.shared.preloadLibrary(urls: urls, priority: .userInitiated)
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

        // Preload the selected image for instant preview
        if let file = imageFiles.first(where: { $0.id == fileID }) {
            preloadImageForPreview(file: file)
        }
    }

    private func preloadImageForPreview(file: ImageFile) {
        // Preload using preview cache for instant display
        PreviewImageCache.shared.preloadImage(for: file.url)
    }
    
    private func handleDoubleClickImage(for fileID: UUID) {
        if let file = imageFiles.first(where: { $0.id == fileID }) {
            withAnimation(.easeInOut(duration: 0.3)) {
                detailViewFile = file
            }
        }
    }
    
    private func moveFilesToTrash(_ files: [ImageFile]) {
        let deletedIDs = Set(files.map { $0.id })
        let wasPreviewedDeleted = previewedImageFile != nil && deletedIDs.contains(previewedImageFile!.id)
        var previewIndex: Int? = nil
        if wasPreviewedDeleted, let current = previewedImageFile, let idx = imageFiles.firstIndex(of: current) {
            previewIndex = idx
        }
        // Capture an anchor index among the items being deleted to decide the next selection afterwards
        let originalFilesSnapshot = imageFiles
        let anchorIndexBeforeDeletion: Int? = files
            .compactMap { file in originalFilesSnapshot.firstIndex(of: file) }
            .min()
        
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
        } else {
            // Not in preview: select the next logical item
            let remaining = imageFiles
            let idx = anchorIndexBeforeDeletion
            if let idx = idx {
                // Prefer the same position if available, else previous
                let candidate = idx < remaining.count ? idx : (remaining.count - 1)
                if candidate >= 0, remaining.indices.contains(candidate) {
                    let nextFile = remaining[candidate]
                    selectedImageFileIDs = [nextFile.id]
                    lastSelectedImageFileID = nextFile.id
                    scrollToID = nextFile.id
                } else {
                    selectedImageFileIDs = []
                    lastSelectedImageFileID = nil
                }
            } else if let first = remaining.first {
                selectedImageFileIDs = [first.id]
                lastSelectedImageFileID = first.id
                scrollToID = first.id
            } else {
                selectedImageFileIDs = []
                lastSelectedImageFileID = nil
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
                .onChange(of: isFocused) { isFocused in
                    if !isFocused {
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
    
    private struct ContactSheetSidebarItem: View {
        let contactSheet: ContactSheet
        let isSelected: Bool
        @State private var isEditing: Bool = false
        @State private var editedName: String
        @State private var isDropTargeted: Bool = false
        let onSelect: () -> Void
        let onRename: (String) -> Void
        let onDelete: () -> Void
        let onDrop: ([URL]) -> Void

        init(contactSheet: ContactSheet, isSelected: Bool, onSelect: @escaping () -> Void, onRename: @escaping (String) -> Void, onDelete: @escaping () -> Void, onDrop: @escaping ([URL]) -> Void) {
            self.contactSheet = contactSheet
            self.isSelected = isSelected
            self.onSelect = onSelect
            self.onRename = onRename
            self.onDelete = onDelete
            self.onDrop = onDrop
            _editedName = State(initialValue: contactSheet.name)
        }

        var body: some View {
            HStack {
                Image(systemName: "square.grid.2x2")
                if isEditing {
                    TextField("Name", text: $editedName, onCommit: {
                        if !editedName.isEmpty {
                            onRename(editedName)
                        }
                        isEditing = false
                    })
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                } else {
                    Text(contactSheet.name)
                        .onTapGesture(count: 2) {
                            isEditing = true
                        }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if !isEditing {
                    onSelect()
                }
            }
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isDropTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .onDrop(of: [UTType.fileURL, UTType.url, UTType.image], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers: providers)
                return true
            }
            .contextMenu {
                Button("Rename") {
                    isEditing = true
                }
                Button("Delete", role: .destructive) {
                    onDelete()
                }
            }
        }

        private func handleDrop(providers: [NSItemProvider]) {
            for provider in providers {
                // Try different type identifiers
                let typeIdentifiers = [
                    UTType.fileURL.identifier,
                    UTType.url.identifier,
                    "public.file-url"
                ]

                for typeIdentifier in typeIdentifiers {
                    if provider.hasItemConformingToTypeIdentifier(typeIdentifier) {
                        provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { (urlData, error) in
                            DispatchQueue.main.async {
                                if let error = error {
                                    print("Drop error: \(error)")
                                    return
                                }

                                var fileURL: URL?

                                if let url = urlData as? URL {
                                    fileURL = url
                                } else if let data = urlData as? Data {
                                    fileURL = URL(dataRepresentation: data, relativeTo: nil)
                                } else if let path = urlData as? String {
                                    fileURL = URL(fileURLWithPath: path)
                                }

                                if let fileURL = fileURL, fileURL.isFileURL {
                                    print("Dropped file: \(fileURL.path)")
                                    self.onDrop([fileURL])
                                }
                            }
                        }
                        break
                    }
                }
            }
        }
    }

    private struct SidebarView: View {
        let folderURLs: [URL]
        let contactSheets: [ContactSheet]
        let selection: Selection?
        let onLinkFolder: () -> Void
        let onSelect: (Selection) -> Void
        let onRemoveFolder: (URL) -> Void
        let onCreateContactSheet: () -> Void
        let onRenameContactSheet: (UUID, String) -> Void
        let onDeleteContactSheet: (UUID) -> Void
        let onDropToContactSheet: (UUID, [URL]) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Folders")
                        .font(.headline)
                    Spacer()
                    Button(action: onLinkFolder) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .help("Add Folder")
                }
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
                    .listRowSeparator(.hidden)

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
                        .listRowSeparator(.hidden)
                        .contextMenu {
                            Button("Remove Folder", role: .destructive) {
                                onRemoveFolder(url)
                            }
                        }
                    }
                }
                .listStyle(PlainListStyle())
                .scrollContentBackground(.hidden)

                Spacer()
                    .frame(height: 24)

                HStack {
                    Text("Contact Sheets")
                        .font(.headline)
                    Spacer()
                    Button(action: onCreateContactSheet) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .help("New Contact Sheet")
                }
                .padding([.horizontal])

                List {
                    ForEach(contactSheets) { sheet in
                        ContactSheetSidebarItem(
                            contactSheet: sheet,
                            isSelected: selection == .contactSheet(sheet.id),
                            onSelect: {
                                onSelect(.contactSheet(sheet.id))
                            },
                            onRename: { newName in
                                onRenameContactSheet(sheet.id, newName)
                            },
                            onDelete: {
                                onDeleteContactSheet(sheet.id)
                            },
                            onDrop: { urls in
                                onDropToContactSheet(sheet.id, urls)
                            }
                        )
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(PlainListStyle())
                .scrollContentBackground(.hidden)

                Spacer()
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
        let onDoubleClickImage: (UUID) -> Void
        @Binding var scrollToID: UUID?
        let onRename: (URL, String) -> Void
        let contactSheets: [ContactSheet]
        let onAddToContactSheet: (UUID, URL) -> Void
        @State private var lastKnownWidth: CGFloat = 0
        var body: some View {
            VStack(spacing: 0) {
                Divider()
                    .background(Color(NSColor.separatorColor))

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
                        ImageGridView(
                            imageFiles: imageFiles,
                            selectedImageFileIDs: $selectedImageFileIDs,
                            onSelectImage: onSelectImage,
                            onDoubleClickImage: onDoubleClickImage,
                            thumbnailSize: gridThumbnailSize,
                            scrollToID: $scrollToID,
                            columnCount: $gridColumnCount,
                            onRename: onRename,
                            contactSheets: contactSheets,
                            onAddToContactSheet: onAddToContactSheet
                        )
                    } else {
                        ImageListView(
                            imageFiles: imageFiles,
                            selectedImageFileIDs: $selectedImageFileIDs,
                            onSelectImage: onSelectImage,
                            onDoubleClickImage: onDoubleClickImage,
                            scrollToID: $scrollToID,
                            onRename: onRename
                        )
                    }
                }
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WidthReader { width in
                updateColumns(for: width)
            })
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
            .toolbarBackground(Color(NSColor.windowBackgroundColor), for: .windowToolbar)
            .toolbarBackground(.visible, for: .windowToolbar)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.15), radius: 8, x: -2, y: 0)
            .padding(.leading, 2)
            .padding(.trailing, 2)
            .padding(.vertical, 2)
            .onChange(of: gridThumbnailSize) { _ in
                updateColumns(for: lastKnownWidth)
            }
        }
        
        private func updateColumns(for width: CGFloat) {
            lastKnownWidth = width
            // Match paddings/spacings used by grid
            let horizontalPadding: CGFloat = 64 // 32 leading + 32 trailing
            let spacing: CGFloat = 20
            let thumb: CGFloat = {
                switch gridThumbnailSize {
                case .small: return 80
                case .medium: return 120
                case .large: return 180
                }
            }()
            let itemOuterWidth: CGFloat = thumb + 12 // thumbnail + cell padding (6 each side)
            let usableWidth = max(0, width - horizontalPadding)
            let computed = max(1, Int( (usableWidth + spacing) / (itemOuterWidth + spacing) ))
            if computed != gridColumnCount { gridColumnCount = computed }
        }
    }
    
    private struct ImageGridView: View {
        let imageFiles: [ImageFile]
        @Binding var selectedImageFileIDs: Set<UUID>
        let onSelectImage: (UUID) -> Void
        let onDoubleClickImage: (UUID) -> Void
        let thumbnailSize: GridThumbnailSize
        @Binding var scrollToID: UUID?
        @Binding var columnCount: Int
        let onRename: (URL, String) -> Void
        let contactSheets: [ContactSheet]
        let onAddToContactSheet: (UUID, URL) -> Void
        
        var body: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 20) {
                        ForEach(imageFiles) { file in
                            GridCell(
                                file: file,
                                isSelected: selectedImageFileIDs.contains(file.id),
                                size: thumbnailSizeValue,
                                onSelectImage: onSelectImage,
                                onDoubleClickImage: onDoubleClickImage,
                                onRename: onRename,
                                contactSheets: contactSheets,
                                onAddToContactSheet: onAddToContactSheet
                            )
                            .id(file.id)
                            .onAppear { prefetchNearbyImages(for: file) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .onChange(of: scrollToID) { newID in
                    if let id = newID {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                        DispatchQueue.main.async { scrollToID = nil }
                    }
                }
            }
            .animation(.spring(), value: thumbnailSize)
        }
        
        private var gridColumns: [GridItem] {
            Array(repeating: GridItem(.flexible(), spacing: 20), count: max(1, columnCount))
        }
        
        private func prefetchNearbyImages(for file: ImageFile) {
            guard let currentIndex = imageFiles.firstIndex(where: { $0.id == file.id }) else { return }

            // Prefetch thumbnails for grid view
            let prefetchRange = (currentIndex + 1)..<min(currentIndex + 6, imageFiles.count)
            for index in prefetchRange {
                let prefetchFile = imageFiles[index]
                if prefetchFile.url.pathExtension.lowercased() != "pdf" && prefetchFile.url.pathExtension.lowercased() != "svg" {
                    DispatchQueue.global(qos: .background).async {
                        _ = ImageCache.shared.getImage(for: prefetchFile.url, size: thumbnailSizeValue)
                    }
                }
            }

            // Aggressively prefetch for PREVIEW - preload current and next 5 images
            let previewRange = currentIndex..<min(currentIndex + 6, imageFiles.count)
            for index in previewRange {
                let prefetchFile = imageFiles[index]
                if prefetchFile.url.pathExtension.lowercased() != "pdf" && prefetchFile.url.pathExtension.lowercased() != "svg" {
                    PreviewImageCache.shared.preloadImage(for: prefetchFile.url)
                }
            }
        }
        
        private var thumbnailSizeValue: CGFloat {
            switch thumbnailSize {
            case .small: return 80
            case .medium: return 120
            case .large: return 180
            }
        }
        
        private struct GridCell: View {
            let file: ImageFile
            let isSelected: Bool
            let size: CGFloat
            let onSelectImage: (UUID) -> Void
            let onDoubleClickImage: (UUID) -> Void
            let onRename: (URL, String) -> Void
            let contactSheets: [ContactSheet]
            let onAddToContactSheet: (UUID, URL) -> Void

            var body: some View {
                VStack {
                    FileThumbnailView(file: file, size: size, onRename: onRename)
                        .frame(width: size, height: size)
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Color.accentColor : Color(NSColor.separatorColor), lineWidth: isSelected ? 4 : 3)
                )
                .shadow(color: isSelected ? Color.accentColor.opacity(0.4) : .clear, radius: isSelected ? 10 : 0)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { onDoubleClickImage(file.id) }
                .onTapGesture { onSelectImage(file.id) }
                .contextMenu {
                    if !contactSheets.isEmpty {
                        Menu("Add to Contact Sheet") {
                            ForEach(contactSheets) { sheet in
                                Button(sheet.name) {
                                    onAddToContactSheet(sheet.id, file.url)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private struct ImageListView: View {
        let imageFiles: [ImageFile]
        @Binding var selectedImageFileIDs: Set<UUID>
        let onSelectImage: (UUID) -> Void
        let onDoubleClickImage: (UUID) -> Void
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
                        .background(selectedImageFileIDs.contains(file.id) ? Color.accentColor.opacity(0.2) : Color.clear)
                        .simultaneousGesture(
                            TapGesture(count: 1)
                                .onEnded { _ in
                                    onSelectImage(file.id)
                                }
                        )
                        .simultaneousGesture(
                            TapGesture(count: 2)
                                .onEnded { _ in
                                    onDoubleClickImage(file.id)
                                }
                        )
                        .id(file.id)
                        .onAppear {
                            // Prefetch nearby images in list view
                            prefetchNearbyImages(for: file)
                        }
                    }
                }
                .listStyle(PlainListStyle())
                .onChange(of: scrollToID) { newID in
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

            // Prefetch thumbnails for list view (more since list view shows more items)
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

            // Aggressively prefetch for PREVIEW - preload current and next 5 images
            let previewRange = currentIndex..<min(currentIndex + 6, imageFiles.count)
            for index in previewRange {
                let prefetchFile = imageFiles[index]
                if prefetchFile.url.pathExtension.lowercased() != "pdf" && prefetchFile.url.pathExtension.lowercased() != "svg" {
                    PreviewImageCache.shared.preloadImage(for: prefetchFile.url)
                }
            }
        }
    }
}

// Helper to read available width without complicating layout trees
private struct WidthReader: View {
    let onChange: (CGFloat) -> Void
    var body: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { onChange(geo.size.width) }
                .onChange(of: geo.size.width) { newWidth in
                    onChange(newWidth)
                }
        }
    }
}

struct PreviewView: View {
    let file: ImageFile
    let onDismiss: () -> Void
    @State private var previewImage: NSImage?
    @State private var isLoading = true

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
                                if let image = previewImage {
                                    Image(nsImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                } else if isLoading {
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
        .onAppear {
            loadPreviewImage()
        }
    }

    private func loadPreviewImage() {
        // Check cache first for instant display
        if let cached = PreviewImageCache.shared.getImage(for: file.url) {
            self.previewImage = cached
            self.isLoading = false
            return
        }

        // If not cached, load it
        PreviewImageCache.shared.preloadImage(for: file.url) { image in
            self.previewImage = image
            self.isLoading = false
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
    var onDeletePressed: (_ bypassConfirmation: Bool) -> Void
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
        var onDeletePressed: ((Bool) -> Void)?
        var onEscapePressed: (() -> Void)?
        var onSpacebarPressed: (() -> Void)?
        var onArrowPressed: ((ContentView.ArrowDirection) -> Void)?
        
        override var acceptsFirstResponder: Bool { true }
        
        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 51, 117: // 51: Delete, 117: Forward Delete
                let bypass = event.modifierFlags.contains(.command) || event.modifierFlags.contains(.shift)
                onDeletePressed?(bypass)
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
