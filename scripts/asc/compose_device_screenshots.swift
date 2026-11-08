import AppKit
import Foundation

struct Screen {
    let slug: String
    let line1: String
    let line2: String
    let subhead: String
}

let screens: [Screen] = [
    Screen(slug: "words", line1: "Every word,", line2: "in its place",
           subhead: "Stacks, tags, search, and clear progress."),
    Screen(slug: "review", line1: "Remember more", line2: "with short reviews",
           subhead: "Self-paced reviews that fit your day."),
    Screen(slug: "editor", line1: "Add words", line2: "with context",
           subhead: "Examples, phonetics, tags, and stacks."),
    Screen(slug: "widgets", line1: "Your words on", line2: "the Home Screen",
           subhead: "Summary and list widgets in four sizes."),
    Screen(slug: "rules", line1: "A learning rhythm", line2: "that adapts",
           subhead: "Tune steps, thresholds, and decay."),
    Screen(slug: "stackSettings", line1: "Tune every stack", line2: "to your pace",
           subhead: "Session limits, card direction, and learning steps."),
]

let ipadScreens: [Screen] = [
    Screen(slug: "words", line1: "Every word,", line2: "in its place",
           subhead: "Stacks, tags, search, and clear progress."),
    Screen(slug: "review", line1: "Remember more", line2: "with short reviews",
           subhead: "Self-paced reviews that fit your day."),
    Screen(slug: "editor", line1: "Add words", line2: "with context",
           subhead: "Examples, phonetics, tags, and stacks."),
    Screen(slug: "widgets", line1: "Your words on", line2: "the Home Screen",
           subhead: "Summary and list widgets in four sizes."),
    Screen(slug: "statistics", line1: "See what", line2: "is working",
           subhead: "Time, reviews, accuracy, and progress."),
    Screen(slug: "stacks", line1: "Every language", line2: "in its own stack",
           subhead: "Separate notebooks, one clear library."),
]

struct Device {
    let key: String
    let source: String
    let width: Int
    let height: Int
    let isPad: Bool
    let hasIsland: Bool
    let frameFraction: CGFloat
}

let devices: [Device] = [
    Device(key: "iphone-69", source: "iphone-raw-new", width: 1320, height: 2868,
           isPad: false, hasIsland: true, frameFraction: 0.765),
    Device(key: "iphone-65", source: "iphone-raw-new", width: 1284, height: 2778,
           isPad: false, hasIsland: true, frameFraction: 0.765),
    Device(key: "iphone-63", source: "iphone-63-raw-native", width: 1206, height: 2622,
           isPad: false, hasIsland: true, frameFraction: 0.765),
    Device(key: "iphone-61", source: "iphone-raw-new", width: 1170, height: 2532,
           isPad: false, hasIsland: true, frameFraction: 0.765),
    Device(key: "iphone-55", source: "iphone-raw-new", width: 1242, height: 2208,
           isPad: false, hasIsland: false, frameFraction: 0.765),
    Device(key: "iphone-47", source: "iphone-raw-new", width: 750, height: 1334,
           isPad: false, hasIsland: false, frameFraction: 0.765),
    Device(key: "iphone-40", source: "iphone-raw-new", width: 640, height: 1136,
           isPad: false, hasIsland: false, frameFraction: 0.72),
    Device(key: "iphone-35", source: "iphone-raw-new", width: 640, height: 960,
           isPad: false, hasIsland: false, frameFraction: 0.70),
    Device(key: "ipad-13", source: "ipad-raw-native", width: 2064, height: 2752,
           isPad: true, hasIsland: false, frameFraction: 0.73),
    Device(key: "ipad-129", source: "ipad-raw-new", width: 2048, height: 2732,
           isPad: true, hasIsland: false, frameFraction: 0.73),
    Device(key: "ipad-11", source: "ipad-raw-new", width: 1668, height: 2388,
           isPad: true, hasIsland: false, frameFraction: 0.73),
    Device(key: "ipad-105", source: "ipad-raw-new", width: 1668, height: 2224,
           isPad: true, hasIsland: false, frameFraction: 0.73),
    Device(key: "ipad-97", source: "ipad-raw-new", width: 1536, height: 2048,
           isPad: true, hasIsland: false, frameFraction: 0.73),
]

let cream = NSColor(srgbRed: 0.984, green: 0.969, blue: 0.933, alpha: 1)
let soft = NSColor(srgbRed: 0.965, green: 0.933, blue: 0.878, alpha: 1)
let charcoal = NSColor(srgbRed: 0.290, green: 0.282, blue: 0.263, alpha: 1)
let secondary = NSColor(srgbRed: 0.459, green: 0.443, blue: 0.373, alpha: 1)
let ochre = NSColor(srgbRed: 0.541, green: 0.416, blue: 0.227, alpha: 1)
let peach = NSColor(srgbRed: 0.965, green: 0.788, blue: 0.702, alpha: 1)
let lavender = NSColor(srgbRed: 0.863, green: 0.796, blue: 0.949, alpha: 1)
let mint = NSColor(srgbRed: 0.804, green: 0.914, blue: 0.839, alpha: 1)
let blue = NSColor(srgbRed: 0.663, green: 0.835, blue: 0.941, alpha: 1)

var activeWidth: CGFloat = 0
var activeHeight: CGFloat = 0

func drawText(_ text: String, x: CGFloat, top: CGFloat, width: CGFloat, font: NSFont,
              color: NSColor, tracking: CGFloat = 0) -> CGFloat {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byWordWrapping
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .kern: tracking,
        .paragraphStyle: paragraph,
    ]
    let attributed = NSAttributedString(string: text, attributes: attributes)
    let height = attributed.boundingRect(
        with: NSSize(width: width, height: 2000),
        options: [.usesLineFragmentOrigin, .usesFontLeading]
    ).height
    let y = activeHeight - top - height
    attributed.draw(with: NSRect(x: x, y: y, width: width, height: height),
                    options: [.usesLineFragmentOrigin, .usesFontLeading])
    return height
}

func render(_ screen: Screen, device: Device) -> String {
    activeWidth = CGFloat(device.width)
    activeHeight = CGFloat(device.height)
    let width = activeWidth
    let height = activeHeight

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: device.width,
        pixelsHigh: device.height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("bitmap")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    let canvas = NSRect(x: 0, y: 0, width: width, height: height)
    cream.setFill()
    canvas.fill()
    NSGradient(colors: [cream, soft])?.draw(in: canvas, angle: -90)

    let glow = NSBezierPath(ovalIn: NSRect(
        x: width * 0.55, y: height - height * 0.22,
        width: width * 0.7, height: width * 0.7
    ))
    ochre.withAlphaComponent(0.05).setFill()
    glow.fill()

    let dots: [(NSColor, CGFloat, CGFloat, CGFloat)] = [
        (peach, 0.08, 0.16, 0.07), (lavender, 0.08, 0.28, 0.05),
        (mint, 0.08, 0.38, 0.04), (blue, 0.08, 0.47, 0.03),
    ]
    for (color, xf, yf, size) in dots {
        color.withAlphaComponent(0.55).setFill()
        let diameter = width * size
        NSBezierPath(ovalIn: NSRect(
            x: width * xf, y: height * yf, width: diameter, height: diameter
        )).fill()
    }

    let scale = width / (device.isPad ? 2064.0 : 1320.0)
    let headlineSize = (device.isPad ? 100.0 : 78.0) * scale
    let subheadSize = (device.isPad ? 40.0 : 32.0) * scale
    let labelSize = (device.isPad ? 30.0 : 24.0) * scale
    let margin = width * (device.isPad ? 0.054 : 0.064)
    let textWidth = width - margin * 2

    let frameWidth = width * device.frameFraction
    let frameHeight = height * device.frameFraction
    let frameX = (width - frameWidth) / 2
    let frameY = height * 0.018
    let frameRect = NSRect(x: frameX, y: frameY, width: frameWidth, height: frameHeight)
    let frameTop = frameY + frameHeight
    let frameTopInset = height - frameTop

    let subheadHeight = subheadSize * 1.35
    let subTop = frameTopInset - subheadHeight - height * 0.012
    let line2Top = subTop - subheadSize * 0.35 - headlineSize * 1.05
    let line1Top = line2Top - headlineSize * 0.98
    let labelTop = line1Top - labelSize * 1.6

    _ = drawText("FLIPABULARY", x: margin, top: labelTop,
                 width: textWidth, font: NSFont.systemFont(ofSize: labelSize, weight: .semibold),
                 color: ochre, tracking: labelSize * 0.33)
    _ = drawText(screen.line1, x: margin, top: line1Top,
                 width: textWidth, font: NSFont.systemFont(ofSize: headlineSize, weight: .bold),
                 color: charcoal)
    _ = drawText(screen.line2, x: margin, top: line2Top,
                 width: textWidth, font: NSFont.systemFont(ofSize: headlineSize, weight: .bold),
                 color: ochre)
    _ = drawText(screen.subhead, x: margin, top: subTop,
                 width: textWidth, font: NSFont.systemFont(ofSize: subheadSize, weight: .regular),
                 color: secondary)

    let frameRadius = frameWidth * (device.isPad ? 0.052 : 0.098)
    let screenRadius = frameRadius * 0.82
    let frame = NSBezierPath(roundedRect: frameRect, xRadius: frameRadius, yRadius: frameRadius)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor(srgbRed: 0.54, green: 0.42, blue: 0.23, alpha: 0.3)
    shadow.shadowBlurRadius = 48 * scale
    shadow.shadowOffset = NSSize(width: 0, height: -16 * scale)
    shadow.set()
    NSColor(srgbRed: 0.10, green: 0.09, blue: 0.08, alpha: 1).setFill()
    frame.fill()
    NSGraphicsContext.saveGraphicsState()
    NSShadow().set()
    NSColor(srgbRed: 0.10, green: 0.09, blue: 0.08, alpha: 1).setFill()
    frame.fill()
    NSGraphicsContext.restoreGraphicsState()

    let inset = max(5, frameWidth * 0.011)
    let screenRect = frameRect.insetBy(dx: inset, dy: inset)
    let screenshotPath = "docs/app-store/\(device.source)/\(screen.slug).png"
    guard let screenshot = NSImage(contentsOfFile: screenshotPath) else {
        fatalError("missing screenshot \(screenshotPath)")
    }

    NSGraphicsContext.saveGraphicsState()
    let clip = NSBezierPath(roundedRect: screenRect, xRadius: screenRadius, yRadius: screenRadius)
    clip.addClip()
    let sourceSize = screenshot.size
    let sourceAspect = sourceSize.width / sourceSize.height
    let targetAspect = screenRect.width / screenRect.height
    let drawRect: NSRect
    if sourceAspect > targetAspect {
        let drawHeight = screenRect.height
        let drawWidth = drawHeight * sourceAspect
        drawRect = NSRect(x: screenRect.midX - drawWidth / 2, y: screenRect.minY,
                          width: drawWidth, height: drawHeight)
    } else {
        let drawWidth = screenRect.width
        let drawHeight = drawWidth / sourceAspect
        drawRect = NSRect(x: screenRect.minX, y: screenRect.maxY - drawHeight,
                          width: drawWidth, height: drawHeight)
    }
    screenshot.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    if device.hasIsland {
        let islandWidth = frameWidth * 0.225
        let islandHeight = frameWidth * 0.053
        let island = NSRect(
            x: frameRect.midX - islandWidth / 2,
            y: frameTop - inset - islandHeight - frameWidth * 0.017,
            width: islandWidth,
            height: islandHeight
        )
        NSColor.black.setFill()
        NSBezierPath(roundedRect: island, xRadius: islandHeight / 2,
                     yRadius: islandHeight / 2).fill()
    }

    let rim = NSBezierPath(roundedRect: frameRect.insetBy(dx: 1, dy: 1),
                           xRadius: frameRadius - 1, yRadius: frameRadius - 1)
    ochre.withAlphaComponent(0.22).setStroke()
    rim.lineWidth = 2
    rim.stroke()

    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.95]) else {
        fatalError("jpeg")
    }
    let outputDir = URL(fileURLWithPath: "docs/app-store/device-new/\(device.key)", isDirectory: true)
    try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    let url = outputDir.appendingPathComponent("\(screen.slug).jpg")
    try? data.write(to: url)
    return url.path
}

for device in devices {
    let list = device.key == "ipad-13" ? ipadScreens : screens
    for screen in list {
        print(render(screen, device: device))
    }
}
