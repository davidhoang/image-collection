//
//  ContactSheetStorage.swift
//  Microfiche
//
//  Created by Claude on 12/28/25.
//

import Foundation
import Combine

class ContactSheetStorage: ObservableObject {
    static let shared = ContactSheetStorage()

    @Published private(set) var contactSheets: [ContactSheet] = []
    private var imageMap: [UUID: ContactSheetImage] = [:]

    private let fileManager = FileManager.default
    private let baseDirectory: URL
    private let imagesDirectory: URL
    private let metadataURL: URL
    private let imageMapURL: URL

    private init() {
        // Set up directories in Application Support
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        baseDirectory = appSupport.appendingPathComponent("Microfiche/ContactSheets")
        imagesDirectory = baseDirectory.appendingPathComponent("Images")
        metadataURL = baseDirectory.appendingPathComponent("metadata.json")
        imageMapURL = baseDirectory.appendingPathComponent("images.json")

        // Create directories if they don't exist
        try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)

        // Load persisted data
        load()
    }

    // MARK: - Contact Sheet Operations

    func createContactSheet(name: String? = nil) -> ContactSheet {
        let generatedName = name ?? generateNextName()
        let contactSheet = ContactSheet(name: generatedName)
        contactSheets.append(contactSheet)
        save()
        return contactSheet
    }

    func deleteContactSheet(id: UUID) {
        guard let index = contactSheets.firstIndex(where: { $0.id == id }) else { return }
        let contactSheet = contactSheets[index]

        // Remove contact sheet
        contactSheets.remove(at: index)

        // Clean up orphaned images
        cleanupOrphanedImages(excludingIDs: contactSheet.imageIDs)

        save()
    }

    func renameContactSheet(id: UUID, newName: String) {
        guard let index = contactSheets.firstIndex(where: { $0.id == id }) else { return }
        contactSheets[index].name = newName
        contactSheets[index].modifiedAt = Date()
        save()
    }

    // MARK: - Image Operations

    func addImage(from sourceURL: URL, to contactSheetID: UUID) -> UUID? {
        guard let index = contactSheets.firstIndex(where: { $0.id == contactSheetID }) else {
            return nil
        }

        // Copy image to permanent storage
        guard let contactSheetImage = copyImageToPermanentStorage(from: sourceURL) else {
            return nil
        }

        // Add to contact sheet
        contactSheets[index].addImage(contactSheetImage.id)

        // Update image map
        imageMap[contactSheetImage.id] = contactSheetImage

        save()
        return contactSheetImage.id
    }

    func removeImage(imageID: UUID, from contactSheetID: UUID) {
        guard let index = contactSheets.firstIndex(where: { $0.id == contactSheetID }) else {
            return
        }

        contactSheets[index].removeImage(imageID)

        // Clean up if image is now orphaned
        cleanupOrphanedImages(excludingIDs: [imageID])

        save()
    }

    func getImage(byID id: UUID) -> ContactSheetImage? {
        return imageMap[id]
    }

    func getImages(for contactSheetID: UUID) -> [ImageFile] {
        guard let contactSheet = contactSheets.first(where: { $0.id == contactSheetID }) else {
            return []
        }

        return contactSheet.imageIDs.compactMap { imageID in
            imageMap[imageID]?.asImageFile
        }
    }

    // MARK: - Private Helpers

    private func copyImageToPermanentStorage(from sourceURL: URL) -> ContactSheetImage? {
        let imageID = UUID()
        let fileExtension = sourceURL.pathExtension
        let destinationURL = imagesDirectory.appendingPathComponent("\(imageID.uuidString).\(fileExtension)")

        do {
            // Copy file to permanent storage
            try fileManager.copyItem(at: sourceURL, to: destinationURL)

            // Create metadata
            let image = ContactSheetImage(
                id: imageID,
                originalURL: sourceURL,
                storedURL: destinationURL
            )

            return image

        } catch {
            print("Error copying image to permanent storage: \(error)")
            return nil
        }
    }

    private func cleanupOrphanedImages(excludingIDs: [UUID]) {
        // Find all image IDs that are referenced by any contact sheet
        var referencedIDs = Set<UUID>()
        for contactSheet in contactSheets {
            referencedIDs.formUnion(contactSheet.imageIDs)
        }

        // Find orphaned images
        let orphanedIDs = Set(imageMap.keys).subtracting(referencedIDs)

        // Delete orphaned image files
        for imageID in orphanedIDs {
            if let image = imageMap[imageID] {
                try? fileManager.removeItem(at: image.storedURL)
                imageMap.removeValue(forKey: imageID)
            }
        }
    }

    private func generateNextName() -> String {
        let existingNumbers = contactSheets.compactMap { sheet -> Int? in
            let name = sheet.name
            if name.hasPrefix("Contact Sheet "),
               let numberString = name.components(separatedBy: "Contact Sheet ").last,
               let number = Int(numberString) {
                return number
            }
            return nil
        }

        let nextNumber = (existingNumbers.max() ?? 0) + 1
        return "Contact Sheet \(nextNumber)"
    }

    // MARK: - Persistence

    func save() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            do {
                // Save contact sheets metadata
                let metadataData = try JSONEncoder().encode(self.contactSheets)
                try metadataData.write(to: self.metadataURL, options: .atomic)

                // Save image map
                let imageMapData = try JSONEncoder().encode(Array(self.imageMap.values))
                try imageMapData.write(to: self.imageMapURL, options: .atomic)

            } catch {
                print("Error saving contact sheet data: \(error)")
            }
        }
    }

    private func load() {
        do {
            // Load contact sheets metadata
            if fileManager.fileExists(atPath: metadataURL.path) {
                let metadataData = try Data(contentsOf: metadataURL)
                contactSheets = try JSONDecoder().decode([ContactSheet].self, from: metadataData)
            }

            // Load image map
            if fileManager.fileExists(atPath: imageMapURL.path) {
                let imageMapData = try Data(contentsOf: imageMapURL)
                let images = try JSONDecoder().decode([ContactSheetImage].self, from: imageMapData)
                imageMap = Dictionary(uniqueKeysWithValues: images.map { ($0.id, $0) })
            }

        } catch {
            print("Error loading contact sheet data: \(error)")
            // Start fresh if loading fails
            contactSheets = []
            imageMap = [:]
        }
    }
}
