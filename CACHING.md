# Caching Architecture

## Overview

Microfiche uses a multi-tier caching strategy to deliver instant image previews and smooth scrolling performance. The architecture is designed to preload images **before** the user clicks, eliminating delays when opening previews.

## Cache Layers

### 1. PreviewImageCache (Full-Size Preview Images)

**Purpose:** Cache optimized full-resolution images for instant preview display

**Location:** `Services/PreviewImageCache.swift`

**Implementation:**
- Uses `NSCache<NSURL, NSImage>` for automatic memory management
- Background processing queue with `.userInitiated` QoS for fast decoding
- Smart image optimization using `CGImageSource`

**Cache Limits:**
- **Count Limit:** 100 images maximum
- **Memory Limit:** 5 GB total
- NSCache automatically evicts least-recently-used images when limits exceeded

**Optimization Strategy:**
```swift
// Images resized to max 2000px on longest dimension
// Example: 6000x4000 image → 2000x1333 image
// Result: 5-10x smaller memory footprint, instant decoding
```

**Key Methods:**
- `getImage(for: URL)` - Instant cache lookup (synchronous)
- `preloadImage(for: URL, completion:)` - Background loading and optimization

**Performance:**
- Cache hit: <1ms (instant display)
- Cache miss: 100-300ms (background loading with progress indicator)

---

### 2. ImageCache (Thumbnail Images)

**Purpose:** Cache smaller thumbnails for grid/list view display

**Location:** `Services/ImageCache.swift`

**Implementation:**
- Similar NSCache-based architecture
- Generates size-specific thumbnails (e.g., 200px for grid, 40px for list)
- Separate cache entries for different sizes

**Cache Limits:**
- Automatically managed by NSCache based on available memory
- Smaller memory footprint than PreviewImageCache (thumbnails only)

---

## Aggressive Preloading Strategy

### The Problem (Before)
1. User selects folder or contact sheet
2. User scrolls to image in grid/list
3. User clicks or presses spacebar
4. **1+ second delay** while image loads and decodes
5. Preview displays

### The Solution (After)
1. User selects folder or contact sheet
2. **Entire library starts preloading immediately** (all images in background)
3. User scrolls/browses grid/list (preloading continues)
4. User clicks or presses spacebar
5. **Instant preview** (already cached and decoded)

### Implementation Details

**Whole-Library Preloading** (`PreviewImageCache.preloadLibrary`)
```swift
// Triggered when folder/contact sheet selected
// Preloads ALL images in the library immediately
// Uses .userInitiated priority for fast initial loading
// Skips PDFs and SVGs (rendered on-demand)
// ContentView.swift:760 - Contact Sheet selection
// ContentView.swift:921 - Folder selection
```

**Viewport-Based Preloading** (Secondary layer)
```swift
// Grid View - Preloads current + next 5 images as they appear
// List View - Preloads current + next 5 images as they appear
// Provides additional prioritization for immediately visible images
```

**Key Insight:**
The entire library preloads as soon as you select a folder or contact sheet. With the 100-image cache and 5GB limit, most libraries fit entirely in memory. Even for large libraries (1000+ images), the first 100 images preload immediately, and clicking any of them is instant.

---

## Storage Locations

### Temporary Cache (In-Memory Only)
- **PreviewImageCache:** NSCache in RAM (not persisted to disk)
- **ImageCache:** NSCache in RAM (not persisted to disk)
- **Benefit:** Automatic cleanup when app quits, no disk space consumed

### Permanent Storage (Contact Sheets)
- **Location:** `~/Library/Application Support/Microfiche/ContactSheets/`
- **Structure:**
  ```
  ContactSheets/
  ├── metadata.json          # Contact Sheet definitions
  ├── images.json            # Image UUID → file path mapping
  └── Images/
      ├── {uuid-1}.jpg       # Permanently copied image files
      ├── {uuid-2}.png
      └── ...
  ```
- **Purpose:** Images added to Contact Sheets are permanently cached to survive source file removal (e.g., external drive ejection)
- **Benefit:** Contact Sheets remain viewable even if original files are deleted or unavailable

---

## Performance Characteristics

### Grid View Scrolling
- **Thumbnail Cache:** Preloads next 5 thumbnails as you scroll
- **Preview Cache:** Preloads next 5 full images as you scroll
- **Result:** Smooth scrolling + instant previews

### List View Scrolling
- **Thumbnail Cache:** Preloads next 10 thumbnails (list shows more items)
- **Preview Cache:** Preloads next 5 full images
- **Result:** Smooth scrolling + instant previews

### Memory Usage
- **PreviewImageCache:** ~20-50 MB per image (after optimization)
- **Total Preview Cache:** Up to ~5 GB (100 images max)
- **ImageCache:** ~0.1-2 MB per thumbnail
- **Total Thumbnail Cache:** Dynamically managed by system
- **Typical Library (50 images):** ~1-2.5 GB RAM
- **Large Library (100+ images):** ~2-5 GB RAM (first 100 cached)

### File Type Handling
- **Standard Images (JPG, PNG):** Full caching and preloading
- **PDF Files:** No preloading (rendered on-demand via PDFKit)
- **SVG Files:** No preloading (rendered on-demand via WebKit)

---

## Code References

### Preview Cache
- Service: `Microfiche/Services/PreviewImageCache.swift`
- Usage: `ContentView.swift:1460` (ImageGridView.prefetchNearbyImages)
- Usage: `ContentView.swift:1656` (ImageListView.prefetchNearbyImages)
- Usage: `ContentView.swift:1724` (PreviewView.loadPreviewImage)

### Thumbnail Cache
- Service: `Microfiche/Services/ImageCache.swift`
- Usage: Throughout grid/list views for thumbnail display

### Contact Sheets Storage
- Service: `Microfiche/Services/ContactSheetStorage.swift`
- Models: `Microfiche/Models/ContactSheet.swift`, `ContactSheetImage.swift`

---

## Configuration

### Adjusting Cache Limits

**PreviewImageCache.swift:**
```swift
// Current settings (aggressive caching)
cache.countLimit = 100
cache.totalCostLimit = 5 * 1024 * 1024 * 1024  // 5GB

// For systems with less RAM, reduce limits:
cache.countLimit = 50
cache.totalCostLimit = 2 * 1024 * 1024 * 1024  // 2GB

// For systems with more RAM, increase limits:
cache.countLimit = 200
cache.totalCostLimit = 10 * 1024 * 1024 * 1024  // 10GB
```

**Preloading Priority:**
```swift
// ContentView.swift - Adjust priority for whole-library preloading
PreviewImageCache.shared.preloadLibrary(urls: urls, priority: .userInitiated)
// Options: .background (slower, less CPU), .userInitiated (faster, default), .userInteractive (highest priority)
```

---

## Trade-offs

### Whole-Library Preloading
**Pros:**
- **Zero latency** for all previews once loaded
- Click any image → instant preview
- No waiting, no progress bars
- Best possible user experience

**Cons:**
- High memory usage (2-5 GB for typical libraries)
- Initial CPU burst when selecting folder
- Preloads images user may never view
- Not suitable for extremely large libraries (1000+ images)

**Decision:** User experience prioritized - instant previews worth the RAM. Modern Macs have 16-64GB RAM, using 5GB for instant previews is acceptable.

### Permanent Contact Sheets Storage
**Pros:**
- Collections survive source file removal
- No dependency on external drives
- Self-contained backups

**Cons:**
- Duplicates consume disk space
- Must manage orphaned images

**Decision:** Reliability prioritized - disk space is cheap, data loss is not

---

## Future Optimizations

1. **Adaptive Preloading:** Adjust preload count based on available memory
2. **Directional Preloading:** Preload ahead based on scroll direction
3. **Lazy Eviction:** Keep more images in cache if memory available
4. **Predictive Loading:** Use ML to predict which images user will view next
