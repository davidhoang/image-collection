//
//  URL+ExtendedAttributes.swift
//  Microfiche
//
//  Created by David Hoang on 6/8/25.
//

import Foundation

extension URL {
    func extendedAttribute(forName name: String) throws -> Data {
        let data = try withUnsafeFileSystemRepresentation { fileSystemPath in
            var size = getxattr(fileSystemPath, name, nil, 0, 0, 0)
            guard size >= 0 else {
                throw POSIXError(.init(rawValue: errno)!)
            }
            
            var data = Data(count: size)
            let result = data.withUnsafeMutableBytes { buffer in
                getxattr(fileSystemPath, name, buffer.baseAddress, size, 0, 0)
            }
            
            guard result >= 0 else {
                throw POSIXError(.init(rawValue: errno)!)
            }
            
            return data
        }
        return data
    }
    
    func setExtendedAttribute(_ data: Data, forName name: String) throws {
        try withUnsafeFileSystemRepresentation { fileSystemPath in
            let result = data.withUnsafeBytes { buffer in
                setxattr(fileSystemPath, name, buffer.baseAddress, data.count, 0, 0)
            }
            
            guard result >= 0 else {
                throw POSIXError(.init(rawValue: errno)!)
            }
        }
    }
    
    func removeExtendedAttribute(forName name: String) throws {
        try withUnsafeFileSystemRepresentation { fileSystemPath in
            let result = removexattr(fileSystemPath, name, 0)
            guard result >= 0 else {
                throw POSIXError(.init(rawValue: errno)!)
            }
        }
    }
    
    func listExtendedAttributes() throws -> [String] {
        try withUnsafeFileSystemRepresentation { fileSystemPath in
            var size = listxattr(fileSystemPath, nil, 0, 0)
            guard size >= 0 else {
                throw POSIXError(.init(rawValue: errno)!)
            }
            
            var buffer = [CChar](repeating: 0, count: size)
            let result = listxattr(fileSystemPath, &buffer, size, 0)
            
            guard result >= 0 else {
                throw POSIXError(.init(rawValue: errno)!)
            }
            
            let attributeNames = buffer.split(separator: 0).compactMap { chars in
                String(cString: Array(chars) + [0])
            }
            
            return attributeNames
        }
    }
}

extension URL {
    func setFinderComment(_ comment: String) throws {
        let key = "com.apple.metadata:kMDItemFinderComment"
        let plist = try PropertyListSerialization.data(fromPropertyList: comment, format: .binary, options: 0)
        try self.setExtendedAttribute(plist, forName: key)
    }
    
    func setFinderTagsAndLabels(tags: [String], labels: [String]) throws {
        let key = "com.apple.metadata:_kMDItemUserTags"
        // Finder color tags are just special strings (e.g., 'Red', 'Orange', etc.)
        // We'll append them to the tags array
        let allTags = tags + labels
        let plist = try PropertyListSerialization.data(fromPropertyList: allTags, format: .binary, options: 0)
        try self.setExtendedAttribute(plist, forName: key)
    }
}