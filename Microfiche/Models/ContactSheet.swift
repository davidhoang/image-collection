//
//  ContactSheet.swift
//  Microfiche
//
//  Created by Claude on 12/28/25.
//

import Foundation

struct ContactSheet: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var imageIDs: [UUID]
    var createdAt: Date
    var modifiedAt: Date

    init(id: UUID = UUID(), name: String, imageIDs: [UUID] = []) {
        self.id = id
        self.name = name
        self.imageIDs = imageIDs
        self.createdAt = Date()
        self.modifiedAt = Date()
    }

    mutating func addImage(_ imageID: UUID) {
        if !imageIDs.contains(imageID) {
            imageIDs.append(imageID)
            modifiedAt = Date()
        }
    }

    mutating func removeImage(_ imageID: UUID) {
        if let index = imageIDs.firstIndex(of: imageID) {
            imageIDs.remove(at: index)
            modifiedAt = Date()
        }
    }
}
