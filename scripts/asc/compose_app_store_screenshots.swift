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
    Screen(slug: "support", line1: "Keep Flipabulary", line2: "free",
           subhead: "Six optional one-time tips. No features locked."),
]

struct Device {
    let folder: String
    let width: Int
    let height: Int
    let deviceWidth: CGFloat
    let deviceHeight: CGFloat
    let frameRadius: CGFloat
    let screenRadius: CGFloat
    let headlineSize: CGFloat
    let subheadSize: CGFloat
    let labelSize: CGFloat
    let topMargin: CGFloat
}

let iphone = Device(
    folder: "iphone-raw", width: 1320, height: 2868,
    deviceWidth: 1010, deviceHeight: 2196, frameRadius: 100, screenRadius: 82,
    headlineSize: 78, subheadSize: 32, labelSize: 24, topMargin: 410
)
let ipad = Device(
    folder: "ipad-raw", width: 2064, height: 2752,
    deviceWidth: 1498, deviceHeight: 2000, frameRadius: 78, screenRadius: 58,
    headlineSize: 100, subheadSize: 40, labelSize: 30, topMargin: 420
)

let cream = NSColor(srgbRed: 0.984, green: 0.969, blue: 0.933, alpha: 1)
let soft = NSColor(srgbRed: 0.965, green: 0.933, blue: 0.878, alpha: 1)
let charcoal = NSColor(srgbRed: 0.290, green: 0.282, blue: 0.263, alpha: 1)
let secondary = NSColor(srgbRed: 0.459, green: 0.443, blue: 0.373, alpha: 1)
let ochre = NSColor(srgbRed: 0.541, green: 0.416, blue: 0.227, alpha: 1)
let peach = NSColor(srgbRed: 0.965, green: 0.788, blue: 0.702, alpha: 1)
let lavender = NSColor(srgbRed: 0.863, green: 0.796, blue: 0.949, alpha: 1)
let mint = NSColor(srgbRed: 0.804, green: 0.914, blue: 0.839, alpha: 1)
let blue = NSColor(srgbRed: 0.663, green: 0.835, blue: 0.941, alpha: 1)
let sand = NSColor(srgbRed: 0.945, green: 0.886, blue: 0.737, alpha: 1)

func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    NSFont.systemFont(ofSize: size, weight: weight)
}

func drawText(_ text: String, x: CGFloat, top: CGFloat, width: CGFloat, font: NSFont,
              color: NSColor, tracking: CGFloat = 0, alignment: NSTextAlignment = .left) -> CGFloat {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byWordWrapping
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .kern: tracking,
        .paragraphStyle: paragraph,
    ]
    let attributed = NSAttributedString(string: text, attributes: attributes)
    let height = attributed.boundingRect(
        with: NSSize(width: width, height: 1000),
        options: [.usesLineFragmentOrigin, .usesFontLeading]
    ).height
    let y = CGFloat(deviceHeightForTop(top)) - height
    attributed.draw(with: NSRect(x: x, y: y, width: width, height: height),
                    options: [.usesLineFragmentOrigin, .usesFontLeading])
    return height
}

var activeHeight: CGFloat = 0
var activeWidth: CGFloat = 0

func deviceHeightForTop(_ top: CGFloat) -> CGFloat {
    activeHeight - top
}

func render(_ screen: Screen, device: Device) -> String {
    activeWidth = CGFloat(device.width)
    activeHeight = CGFloat(device.height)

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

    let canvas = NSRect(x: 0, y: 0, width: activeWidth, height: activeHeight)
    cream.setFill()
    canvas.fill()

    let gradient = NSGradient(colors: [cream, soft])
    gradient?.draw(in: canvas, angle: -90)

    // Soft paper circles.
    let circle1 = NSBezierPath(ovalIn: NSRect(
        x: activeWidth * 0.55, y: activeHeight - 640,
        width: 900, height: 900
    ))
    ochre.withAlphaComponent(0.05).setFill()
    circle1.fill()

    let dots: [(NSColor, CGFloat, CGFloat, CGFloat)] = [
        (peach, 0.08, 0.16, 90), (lavender, 0.08, 0.28, 60),
        (mint, 0.08, 0.38, 48), (blue, 0.08, 0.47, 36),
    ]
    for (color, xf, yf, size) in dots {
        color.withAlphaComponent(0.55).setFill()
        NSBezierPath(ovalIn: NSRect(
            x: activeWidth * xf, y: activeHeight * yf, width: size, height: size
        )).fill()
    }

    let margin: CGFloat = device.width == 1320 ? 84 : 112
    let textWidth = activeWidth - margin * 2

    _ = drawText("FLIPABULARY", x: margin, top: device.topMargin - 64,
                 width: textWidth, font: roundedFont(device.labelSize, .semibold),
                 color: ochre, tracking: 8)

    _ = drawText(screen.line1, x: margin, top: device.topMargin,
                 width: textWidth, font: roundedFont(device.headlineSize, .bold),
                 color: charcoal)
    _ = drawText(screen.line2, x: margin, top: device.topMargin + device.headlineSize * 0.98,
                 width: textWidth, font: roundedFont(device.headlineSize, .bold),
                 color: ochre)
    _ = drawText(screen.subhead, x: margin,
                 top: device.topMargin + device.headlineSize * 1.98 + 18,
                 width: textWidth, font: roundedFont(device.subheadSize, .regular),
                 color: secondary)

    let frameX = (activeWidth - device.deviceWidth) / 2
    let frameY: CGFloat = 36
    let frameRect = NSRect(x: frameX, y: frameY, width: device.deviceWidth, height: device.deviceHeight)
    let frame = NSBezierPath(roundedRect: frameRect, xRadius: device.frameRadius, yRadius: device.frameRadius)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor(srgbRed: 0.54, green: 0.42, blue: 0.23, alpha: 0.3)
    shadow.shadowBlurRadius = 48
    shadow.shadowOffset = NSSize(width: 0, height: -16)
    shadow.set()
    NSColor(srgbRed: 0.10, green: 0.09, blue: 0.08, alpha: 1).setFill()
    frame.fill()
    NSGraphicsContext.saveGraphicsState()
    NSShadow().set()
    NSColor(srgbRed: 0.10, green: 0.09, blue: 0.08, alpha: 1).setFill()
    frame.fill()
    NSGraphicsContext.restoreGraphicsState()

    let inset: CGFloat = 12
    let screenRect = frameRect.insetBy(dx: inset, dy: inset)
    let screenshotPath = "docs/app-store/\(device.folder)/\(screen.slug).png"
    guard let screenshot = NSImage(contentsOfFile: screenshotPath) else {
        fatalError("missing screenshot \(screenshotPath)")
    }

    NSGraphicsContext.saveGraphicsState()
    let clip = NSBezierPath(roundedRect: screenRect, xRadius: device.screenRadius, yRadius: device.screenRadius)
    clip.addClip()
    screenshot.draw(in: screenRect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    // Dynamic Island for the phone frame.
    if device.width == 1320 {
        let islandWidth: CGFloat = 246
        let islandHeight: CGFloat = 58
        let island = NSRect(
            x: (activeWidth - islandWidth) / 2,
            y: frameY + device.deviceHeight - 82,
            width: islandWidth,
            height: islandHeight
        )
        NSColor.black.setFill()
        NSBezierPath(roundedRect: island, xRadius: islandHeight / 2, yRadius: islandHeight / 2).fill()
    }

    // Thin warm rim.
    let rim = NSBezierPath(roundedRect: frameRect.insetBy(dx: 1, dy: 1),
                           xRadius: device.frameRadius - 1, yRadius: device.frameRadius - 1)
    ochre.withAlphaComponent(0.22).setStroke()
    rim.lineWidth = 2
    rim.stroke()

    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.95]) else {
        fatalError("jpeg")
    }
    let outputDir = URL(fileURLWithPath: "docs/app-store/\(device.folder == "iphone-raw" ? "iphone" : "ipad")", isDirectory: true)
    try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    let url = outputDir.appendingPathComponent("\(screen.slug).jpg")
    try? data.write(to: url)
    return url.path
}

for device in [iphone, ipad] {
    for screen in screens {
        print(render(screen, device: device))
    }
}
