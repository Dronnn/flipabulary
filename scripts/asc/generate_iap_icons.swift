import AppKit
import Foundation

let size = 1024
let output = URL(fileURLWithPath: "docs/app-store/iap-icons", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

struct Tier {
    let slug: String
    let symbol: String
    let background: NSColor
    let card: NSColor
    let accent: NSColor
    let badge: NSColor
}

let cream = NSColor(srgbRed: 0.984, green: 0.969, blue: 0.933, alpha: 1)
let charcoal = NSColor(srgbRed: 0.290, green: 0.282, blue: 0.263, alpha: 1)
let ochre = NSColor(srgbRed: 0.541, green: 0.416, blue: 0.227, alpha: 1)

let tiers: [Tier] = [
    Tier(slug: "coffee", symbol: "cup.and.saucer.fill", background: cream,
         card: .white, accent: ochre, badge: NSColor(srgbRed: 0.965, green: 0.929, blue: 0.878, alpha: 1)),
    Tier(slug: "lunch", symbol: "fork.knife", background: cream,
         card: .white, accent: NSColor(srgbRed: 0.235, green: 0.400, blue: 0.310, alpha: 1),
         badge: NSColor(srgbRed: 0.804, green: 0.914, blue: 0.839, alpha: 1)),
    Tier(slug: "bigfan", symbol: "heart.fill", background: cream,
         card: .white, accent: NSColor(srgbRed: 0.647, green: 0.345, blue: 0.255, alpha: 1),
         badge: NSColor(srgbRed: 0.965, green: 0.788, blue: 0.702, alpha: 1)),
    Tier(slug: "patron", symbol: "star.fill", background: cream,
         card: .white, accent: NSColor(srgbRed: 0.400, green: 0.318, blue: 0.541, alpha: 1),
         badge: NSColor(srgbRed: 0.863, green: 0.796, blue: 0.949, alpha: 1)),
    Tier(slug: "champion", symbol: "trophy.fill", background: cream,
         card: .white, accent: NSColor(srgbRed: 0.235, green: 0.400, blue: 0.510, alpha: 1),
         badge: NSColor(srgbRed: 0.663, green: 0.835, blue: 0.941, alpha: 1)),
    Tier(slug: "legend", symbol: "crown.fill", background: cream,
         card: .white, accent: ochre, badge: NSColor(srgbRed: 0.945, green: 0.886, blue: 0.737, alpha: 1))
]

for tier in tiers {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { fatalError("bitmap") }

    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { fatalError("context") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    tier.background.setFill()
    rect.fill()

    let glow = NSBezierPath(ovalIn: NSRect(x: 110, y: 110, width: 804, height: 804))
    tier.badge.withAlphaComponent(0.35).setFill()
    glow.fill()

    let cardRect = NSRect(x: 202, y: 202, width: 620, height: 620)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(srgbRed: 0.54, green: 0.42, blue: 0.23, alpha: 0.22)
    shadow.shadowBlurRadius = 60
    shadow.shadowOffset = NSSize(width: 0, height: -28)
    shadow.set()
    tier.card.setFill()
    NSBezierPath(roundedRect: cardRect, xRadius: 128, yRadius: 128).fill()

    let badgeRect = NSRect(x: 322, y: 322, width: 380, height: 380)
    tier.badge.setFill()
    NSBezierPath(ovalIn: badgeRect).fill()

    let sizeConfig = NSImage.SymbolConfiguration(pointSize: 300, weight: .semibold)
    let colorConfig = NSImage.SymbolConfiguration(paletteColors: [tier.accent])
    let config = sizeConfig.applying(colorConfig)
    if let symbol = NSImage(systemSymbolName: tier.symbol, accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let symbolSize = symbol.size
        let target = NSRect(
            x: (CGFloat(size) - symbolSize.width) / 2,
            y: (CGFloat(size) - symbolSize.height) / 2,
            width: symbolSize.width,
            height: symbolSize.height
        )
        tier.accent.set()
        symbol.isTemplate = true
        symbol.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
    }

    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.96]) else { fatalError("png") }
    let url = output.appendingPathComponent("\(tier.slug).jpg")
    try data.write(to: url)
    print(url.path)
}
