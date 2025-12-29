//
//  ContactSheetImage.swift
//  Microfiche
//
//  Created by Claude on 12/28/25.
//

import Foundation

struct ContactSheetImage: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let originalURL: URL      // Reference to original file (may not exist)
    let storedURL: URL        // Permanent location in Application Support
    let fileName: String
    let fileExtension: String
    var addedAt: Date

    init(id: UUID = UUID(), originalURL: URL, storedURL: URL) {
        self.id = id
        self.originalURL = originalURL
        self.storedURL = storedURL
        self.fileName = originalURL.lastPathComponent
        self.fileExtension = originalURL.pathExtension
        self.addedAt = Date()
    }

    // Convert to ImageFile for display in existing views
    var asImageFile: ImageFile {
        ImageFile(url: storedURL)
    }
}
