# Navigation Requirements

- **Left:** Sidebar must be collapsible and expandable (standard macOS sidebar behavior).
- **Middle:** Main area should support both Grid and List views.
- **Grid Settings:** When in Grid view, the Small/Medium/Large size options must be available and functional.

---

# App Icon Asset Requirements

## macOS App Icon Sizes

The app icon for macOS requires the following sizes:

### Required Sizes:
- **16x16** (1x) - `icon_16x16.png`
- **16x16** (2x) - `icon_16x16@2x.png` (32x32 pixels)
- **32x32** (1x) - `icon_32x32.png`
- **32x32** (2x) - `icon_32x32@2x.png` (64x64 pixels)
- **128x128** (1x) - `icon_128x128.png`
- **128x128** (2x) - `icon_128x128@2x.png` (256x256 pixels)
- **256x256** (1x) - `icon_256x256.png`
- **256x256** (2x) - `icon_256x256@2x.png` (512x512 pixels)
- **512x512** (1x) - `icon_512x512.png`
- **512x512** (2x) - `icon_512x512@2x.png` (1024x1024 pixels)

### File Format:
- All icons should be in PNG format
- Use 8-bit color depth
- Include alpha channel for transparency if needed

### Design Guidelines:
- Icons should be simple and recognizable at small sizes
- Use consistent design language with macOS
- Ensure good contrast and visibility
- Test at all sizes to ensure clarity

### Current Placeholder:
The current placeholder icon features:
- Blue to purple gradient background
- Photo stack icon (SF Symbol: "photo.stack")
- "MF" text (for Microfiche)
- Rounded corners
- White foreground elements

### To Replace:
1. Create your icon design at 1024x1024 pixels
2. Generate all required sizes using an image editor or icon generator
3. Replace the files in `Microfiche/Assets.xcassets/AppIcon.appiconset/`
4. Update the `Contents.json` file if you change the filenames

### Tools for Icon Generation:
- Sketch, Figma, or Adobe Illustrator for design
- Icon generators like IconKitchen or Icon Composer
- Online tools like App Icon Generator
- Command line tools like ImageMagick for batch resizing 