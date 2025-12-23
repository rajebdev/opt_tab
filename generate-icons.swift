#!/usr/bin/env swift

import Cocoa
import Foundation

// MARK: - Menu Bar Icon (Template Icon - Like App Icon)
func generateMenuBarIcon() -> NSImage? {
    let size: CGFloat = 22
    let imageSize = NSSize(width: size, height: size)
    let image = NSImage(size: imageSize)

    image.lockFocus()

    // Draw two overlapping windows symbol (same style as app icon)
    let windowSize = size * 0.5
    let spacing: CGFloat = size * 0.15

    // Back window
    let backWindowRect = NSRect(
        x: (size - windowSize) / 2 + spacing,
        y: (size - windowSize) / 2 + spacing,
        width: windowSize,
        height: windowSize
    )

    NSColor.white.withAlphaComponent(0.8).setFill()
    let backPath = NSBezierPath(
        roundedRect: backWindowRect, xRadius: size * 0.08, yRadius: size * 0.08)
    backPath.fill()

    // Front window
    let frontWindowRect = NSRect(
        x: (size - windowSize) / 2 - spacing,
        y: (size - windowSize) / 2 - spacing,
        width: windowSize,
        height: windowSize
    )

    NSColor.white.setFill()
    let frontPath = NSBezierPath(
        roundedRect: frontWindowRect, xRadius: size * 0.08, yRadius: size * 0.08)
    frontPath.fill()

    image.unlockFocus()
    image.isTemplate = true  // Important for menu bar icons (auto adapts to light/dark mode)

    return image
}

// MARK: - App Icon (Colorful - Detailed)
func generateAppIcon(size: CGFloat) -> NSImage? {
    let imageSize = NSSize(width: size, height: size)
    let image = NSImage(size: imageSize)

    image.lockFocus()

    // Background gradient (blue to purple)
    let gradient = NSGradient(
        colors: [
            NSColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1.0),  // Light blue
            NSColor(red: 0.5, green: 0.2, blue: 0.9, alpha: 1.0),  // Purple
        ]
    )

    let rect = NSRect(origin: .zero, size: imageSize)
    let path = NSBezierPath(roundedRect: rect, xRadius: size * 0.2, yRadius: size * 0.2)
    gradient?.draw(in: path, angle: -45)

    // Draw two overlapping windows symbol
    let windowSize = size * 0.35
    let spacing: CGFloat = size * 0.12

    // Back window (lighter)
    let backWindowRect = NSRect(
        x: (size - windowSize) / 2 + spacing,
        y: (size - windowSize) / 2 + spacing,
        width: windowSize,
        height: windowSize
    )

    NSColor.white.withAlphaComponent(0.3).setFill()
    let backPath = NSBezierPath(
        roundedRect: backWindowRect, xRadius: size * 0.05, yRadius: size * 0.05)
    backPath.fill()

    NSColor.white.withAlphaComponent(0.6).setStroke()
    backPath.lineWidth = size * 0.015
    backPath.stroke()

    // Front window (brighter)
    let frontWindowRect = NSRect(
        x: (size - windowSize) / 2 - spacing,
        y: (size - windowSize) / 2 - spacing,
        width: windowSize,
        height: windowSize
    )

    NSColor.white.withAlphaComponent(0.95).setFill()
    let frontPath = NSBezierPath(
        roundedRect: frontWindowRect, xRadius: size * 0.05, yRadius: size * 0.05)
    frontPath.fill()

    NSColor.white.setStroke()
    frontPath.lineWidth = size * 0.02
    frontPath.stroke()

    // Draw "⌥⇥" text in center
    let text = "⌥⇥"
    let fontSize = size * 0.25
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
        .foregroundColor: NSColor.white,
    ]

    let textSize = text.size(withAttributes: attributes)
    let textRect = NSRect(
        x: (size - textSize.width) / 2,
        y: (size - textSize.height) / 2 - size * 0.02,
        width: textSize.width,
        height: textSize.height
    )

    // Shadow for text
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.01)
    shadow.shadowBlurRadius = size * 0.02

    var textAttrs = attributes
    textAttrs[.shadow] = shadow

    text.draw(in: textRect, withAttributes: textAttrs)

    image.unlockFocus()

    return image
}

// MARK: - Save Functions
func saveMenuBarIcon() {
    guard let icon = generateMenuBarIcon() else {
        print("❌ Failed to generate menu bar icon")
        return
    }

    guard let tiffData = icon.tiffRepresentation,
        let bitmapImage = NSBitmapImageRep(data: tiffData),
        let pngData = bitmapImage.representation(using: .png, properties: [:])
    else {
        print("❌ Failed to convert menu bar icon to PNG")
        return
    }

    let iconPath = "OptTab/Resources/MenuBarIcon.png"
    try? FileManager.default.createDirectory(
        atPath: "OptTab/Resources", withIntermediateDirectories: true)

    if FileManager.default.createFile(atPath: iconPath, contents: pngData) {
        print("✅ Menu bar icon saved: \(iconPath)")
    } else {
        print("❌ Failed to save menu bar icon")
    }
}

func saveAppIcon() {
    // Generate multiple sizes for .icns
    let sizes: [CGFloat] = [16, 32, 64, 128, 256, 512, 1024]
    var representations: [NSImageRep] = []

    for size in sizes {
        guard let icon = generateAppIcon(size: size) else { continue }

        if let tiffData = icon.tiffRepresentation,
            let bitmapImage = NSBitmapImageRep(data: tiffData)
        {
            representations.append(bitmapImage)
        }
    }

    // Save as PNG for the largest size
    if let icon1024 = generateAppIcon(size: 1024),
        let tiffData = icon1024.tiffRepresentation,
        let bitmapImage = NSBitmapImageRep(data: tiffData),
        let pngData = bitmapImage.representation(using: .png, properties: [:])
    {

        let iconPath = "OptTab/Resources/AppIcon.png"
        try? FileManager.default.createDirectory(
            atPath: "OptTab/Resources", withIntermediateDirectories: true)

        if FileManager.default.createFile(atPath: iconPath, contents: pngData) {
            print("✅ App icon saved: \(iconPath)")
        }
    }

    // Create .iconset for conversion to .icns
    let iconsetPath = "OptTab/Resources/AppIcon.iconset"
    try? FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

    let iconSizes: [(size: CGFloat, name: String)] = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png"),
    ]

    for (size, name) in iconSizes {
        guard let icon = generateAppIcon(size: size),
            let tiffData = icon.tiffRepresentation,
            let bitmapImage = NSBitmapImageRep(data: tiffData),
            let pngData = bitmapImage.representation(using: .png, properties: [:])
        else {
            continue
        }

        let path = "\(iconsetPath)/\(name)"
        FileManager.default.createFile(atPath: path, contents: pngData)
    }

    print("✅ Iconset created: \(iconsetPath)")
    print("   Run: iconutil -c icns \(iconsetPath)")
}

// MARK: - Main
print("🎨 Generating OptTab icons...")
print("")

saveMenuBarIcon()
saveAppIcon()

print("")
print("📝 Next steps:")
print("   1. Run: iconutil -c icns OptTab/Resources/AppIcon.iconset")
print("   2. Update build-app.sh to copy AppIcon.icns to Resources")
print("   3. Update Info.plist with CFBundleIconFile key")
