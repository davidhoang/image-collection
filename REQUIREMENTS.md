# Mac Photo Manager – Requirements Document

## Overview
A macOS desktop application for photographers and hobbyists, inspired by early Adobe Lightroom, focused on non-destructive photo management. The app will reference images by their file paths (no import/copy), supporting organization, tagging, and metadata management, with a modern SwiftUI interface.

---

## Key Features

### 1. Platform & Stack
- **macOS Desktop App**
- **SwiftUI** (not AppKit, no Electron)
- **Development Tools:** Cursor, Sweetpad, Xcode ([Cursor Swift Guide](https://docs.cursor.com/guides/languages/swift))

### 2. Image Browsing
- **Grid View**
  - Adjustable thumbnail sizes (e.g., small, medium, large)
  - Responsive layout for different window sizes
- **List View**
  - Row-based display with image preview and metadata
- **Switching Views**
  - Toggle between grid and list view

### 3. File Management
- **Folder Linking**
  - Add/link multiple folders (including external drives)
  - Persist folder links across app launches
- **File Path Retention**
  - Images are referenced by their original file paths (no import/copy)
- **Archiving**
  - Move images to a user-defined archive folder
- **Deleting**
  - Permanently delete images from the file system (with confirmation)

### 4. Organization & Metadata
- **Local Tagging**
  - Add/remove tags to images (stored locally, not in image files)
  - Tag search/filter
- **Notes**
  - Text field for user notes per image (stored locally)
- **Standard Image Metadata**
  - Display EXIF/IPTC data (date, camera, lens, etc.)
  - Read-only display of metadata

---

## Non-Functional Requirements

- **Performance:** Fast browsing of large folders (thousands of images)
- **Reliability:** Handle missing/moved files gracefully
- **Usability:** Modern, clean UI with keyboard shortcuts for common actions
- **Persistence:** Use Core Data or local database for tags/notes/links

---

## Development Workflow

- **Editor:** Use Cursor for code editing, leveraging AI features and Swift Language Support extension.
- **Build/Run:** Use Sweetpad to build, run, and debug directly in Cursor, with Xcode installed for underlying build tools.
- **Hot Reloading:** Consider using Inject for real-time UI updates during development.
- **Formatting:** Use swiftformat for code consistency.

---

## Next Steps

1. **Project Setup**
   - Create a new SwiftUI macOS project.
   - Set up Sweetpad and Swift Language Support in Cursor.
2. **Core Data Model**
   - Design schema for folders, image references, tags, and notes.
3. **UI Prototyping**
   - Build basic grid and list views.
   - Implement folder linking and image browsing.
4. **Feature Iteration**
   - Add tagging, notes, archiving, and deletion.
   - Integrate metadata display.
5. **Testing & Refinement**
   - Test with large image sets and external drives.
   - Polish UI/UX and optimize performance.

--- 