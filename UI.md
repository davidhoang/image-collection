# Microfiche UI Architecture

## Overview

Microfiche uses a modern, elevated design with clear visual hierarchy inspired by Arc browser and contemporary macOS applications.

## Main UI Components

### 1. Sidebar
**Location:** Left side of window
**Purpose:** Navigation and library organization
**Background:** `NSColor.windowBackgroundColor` (darker grey)

**Sections:**
- **Folders Section**
  - "All" - Shows all images from linked folders
  - Individual folder items
  - Add Folder button (+)

- **Contact Sheets Section**
  - Contact Sheet items (user-created collections)
  - New Contact Sheet button (+)

**Styling:**
- No divider lines between sections
- `.listStyle(PlainListStyle())` for clean, fluid appearance
- `.listRowSeparator(.hidden)` to remove row separators
- 24pt spacer between Folders and Contact Sheets sections

---

### 2. Unified Toolbar
**Location:** Top of Content Area
**Purpose:** View mode and size controls
**Background:** `NSColor.textBackgroundColor` (very light grey, almost white)

**Controls:**
- **View Mode Picker:** Grid / List toggle (center)
- **Size Picker:** Small / Medium / Large (right side, Grid view only)

**Styling:**
- `.toolbarBackground(Color(NSColor.textBackgroundColor), for: .windowToolbar)`
- Subtle, light color to draw attention to the Content Area below
- Seamlessly integrated with Content Area (shares rounded corners and shadow)

**Design Philosophy:**
- Inspired by Arc browser's subtle toolbar design
- Light background recedes visually, emphasizing content
- Still part of the elevated Content Area card

---

### 3. Content Area Elevation
**Location:** Right side of window (main area)
**Purpose:** Display image grid/list and provide visual hierarchy
**Background:** `NSColor.controlBackgroundColor` (medium grey)

**Components:**
- Unified Toolbar (top)
- Image Grid or Image List (scrollable content)

**Elevation Styling:**
- **Border Radius:** 12pt rounded corners
- **Shadow:** 8pt blur, 15% black opacity, -2pt x-offset
- **Padding:** 2pt inset from window edges
- **Visual Effect:** Appears as elevated card floating above sidebar

**Design Rationale:**
- Creates clear separation from sidebar
- Provides focus on main content
- Modern, card-based design language
- Minimal inset (2pt) maintains screen real estate while showing shadow

---

## Color Hierarchy

**From darkest to lightest:**

1. **Sidebar Background** - `NSColor.windowBackgroundColor`
   Dark grey base layer

2. **Content Area Background** - `NSColor.controlBackgroundColor`
   Medium grey elevated surface

3. **Unified Toolbar Background** - `NSColor.textBackgroundColor`
   Very light grey, almost white - most subtle

This three-tier color system creates natural visual hierarchy:
- Sidebar = foundation layer
- Content Area = elevated workspace
- Toolbar = subtle header receding to emphasize content

---

## Layout Structure

```
┌─────────────────────────────────────────────────────┐
│                    Window                           │
│  ┌──────────┬───────────────────────────────────┐  │
│  │          │  ┌─────────────────────────────┐  │  │
│  │          │  │   Unified Toolbar           │  │  │
│  │          │  │  (Light Grey)               │  │  │
│  │ Sidebar  │  ├─────────────────────────────┤  │  │
│  │ (Dark)   │  │                             │  │  │
│  │          │  │   Image Grid/List           │  │  │
│  │          │  │   (Content Area)            │  │  │
│  │          │  │   (Medium Grey)             │  │  │
│  │          │  │                             │  │  │
│  │          │  └─────────────────────────────┘  │  │
│  │          │        Content Area Elevation      │  │
│  │          │      (12pt radius, 8pt shadow)     │  │
│  └──────────┴───────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

---

## Code References

### Sidebar
- **File:** `ContentView.swift:1278-1378`
- **Struct:** `SidebarView`
- **Key Modifiers:**
  - `.listStyle(PlainListStyle())`
  - `.scrollContentBackground(.hidden)`
  - `.listRowSeparator(.hidden)`

### Unified Toolbar
- **File:** `ContentView.swift:1431-1460`
- **Location:** Inside `MainContentView.toolbar`
- **Key Modifiers:**
  - `.toolbarBackground(Color(NSColor.textBackgroundColor), for: .windowToolbar)`
  - `.toolbarBackground(.visible, for: .windowToolbar)`

### Content Area Elevation
- **File:** `ContentView.swift:1377-1467`
- **Struct:** `MainContentView`
- **Key Modifiers:**
  - `.background(Color(NSColor.controlBackgroundColor))`
  - `.cornerRadius(12)`
  - `.shadow(color: Color.black.opacity(0.15), radius: 8, x: -2, y: 0)`
  - `.padding(.leading, 2)` / `.padding(.trailing, 2)` / `.padding(.vertical, 2)`

---

## Design Principles

1. **Visual Hierarchy Through Color**
   Three-tier color system (dark → medium → light) guides user attention

2. **Elevation Through Shadow**
   Content Area appears to float above Sidebar, creating depth

3. **Subtle Toolbar**
   Light toolbar recedes visually, keeping focus on content

4. **Minimal Insets**
   2pt padding maintains screen space while showing elevation

5. **Fluid Sidebar**
   No dividers or lines - smooth, uninterrupted navigation

6. **Arc-Inspired Design**
   Clean, modern aesthetic with subtle color transitions

---

## Future Enhancements

Potential improvements to consider:

- **Adaptive Elevation:** Adjust shadow based on light/dark mode
- **Material Effects:** Use `.ultraThickMaterial` for glassmorphic toolbar
- **Hover States:** Subtle highlights on sidebar items
- **Animated Transitions:** Smooth elevation changes when switching views
- **Custom Accent Colors:** User-selectable theme colors
