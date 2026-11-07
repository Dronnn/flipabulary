import AppKit
import ImageIO
import UniformTypeIdentifiers

let width = 5244
let height = 2950
let colorSpace = CGColorSpaceCreateDeviceRGB()
let context = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!

let graphics = NSGraphicsContext(cgContext: context, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
graphics.imageInterpolation = .high

let canvas = NSRect(x: 0, y: 0, width: width, height: height)
let cream = NSColor(srgbRed: 0.984, green: 0.969, blue: 0.933, alpha: 1)
let soft = NSColor(srgbRed: 0.965, green: 0.933, blue: 0.878, alpha: 1)
let ochre = NSColor(srgbRed: 0.541, green: 0.416, blue: 0.227, alpha: 1)
let peach = NSColor(srgbRed: 0.965, green: 0.788, blue: 0.702, alpha: 1)
let lavender = NSColor(srgbRed: 0.863, green: 0.796, blue: 0.949, alpha: 1)
let mint = NSColor(srgbRed: 0.804, green: 0.914, blue: 0.839, alpha: 1)

cream.setFill()
canvas.fill()
NSGradient(colors: [cream, soft])?.draw(in: canvas, angle: -90)

// Large warm glow behind the card stack.
let glow = NSBezierPath(ovalIn: NSRect(x: 3000, y: 1250, width: 2700, height: 2700))
ochre.withAlphaComponent(0.07).setFill()
glow.fill()

let bottomGlow = NSBezierPath(ovalIn: NSRect(x: -700, y: -900, width: 2500, height: 2500))
peach.withAlphaComponent(0.35).setFill()
bottomGlow.fill()

// Thin ochre arc.
let arc = NSBezierPath()
arc.appendArc(withCenter: NSPoint(x: 4400, y: 1500), radius: 1550,
              startAngle: 120, endAngle: 330, clockwise: false)
ochre.withAlphaComponent(0.18).setStroke()
arc.lineWidth = 10
arc.stroke()

// A quiet field of pastel tiles on the left edge.
let tiles: [(NSColor, NSRect)] = [
    (peach, NSRect(x: 250, y: 430, width: 170, height: 170)),
    (lavender, NSRect(x: 530, y: 280, width: 120, height: 120)),
    (mint, NSRect(x: 760, y: 520, width: 90, height: 90)),
]
for (color, rect) in tiles {
    color.withAlphaComponent(0.62).setFill()
    NSBezierPath(roundedRect: rect, xRadius: 34, yRadius: 34).fill()
}

// Card stack on the right. The center-left stays quiet for the App Store overlay.
func card(rect: NSRect, fill: NSColor, accent: NSColor, corner: CGFloat, shadow: Bool) {
    let path = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
    if shadow {
        let s = NSShadow()
        s.shadowColor = NSColor(srgbRed: 0.54, green: 0.42, blue: 0.23, alpha: 0.22)
        s.shadowBlurRadius = 60
        s.shadowOffset = NSSize(width: 0, height: -24)
        s.set()
    }
    fill.setFill()
    path.fill()
    NSShadow().set()
    accent.withAlphaComponent(0.20).setStroke()
    path.lineWidth = 8
    path.stroke()
}

context.saveGState()
context.translateBy(x: 4100, y: 1350)
context.rotate(by: -8 * .pi / 180)
card(rect: NSRect(x: -850, y: -1050, width: 1700, height: 2100),
     fill: NSColor.white, accent: ochre, corner: 150, shadow: true)
context.restoreGState()

context.saveGState()
context.translateBy(x: 4380, y: 1420)
context.rotate(by: 6 * .pi / 180)
card(rect: NSRect(x: -760, y: -970, width: 1520, height: 1940),
     fill: NSColor(srgbRed: 0.996, green: 0.984, blue: 0.957, alpha: 1),
     accent: peach, corner: 140, shadow: true)
context.restoreGState()

context.saveGState()
context.translateBy(x: 4620, y: 1510)
context.rotate(by: 17 * .pi / 180)
card(rect: NSRect(x: -620, y: -820, width: 1240, height: 1640),
     fill: NSColor(srgbRed: 0.972, green: 0.949, blue: 0.894, alpha: 1),
     accent: lavender, corner: 120, shadow: true)
context.restoreGState()

// A small ochre progress ring on the top card.
let ringRect = NSRect(x: 4455, y: 1760, width: 250, height: 250)
let ring = NSBezierPath(ovalIn: ringRect)
ochre.withAlphaComponent(0.35).setStroke()
ring.lineWidth = 22
ring.stroke()
let ringProgress = NSBezierPath()
ringProgress.appendArc(withCenter: NSPoint(x: ringRect.midX, y: ringRect.midY),
                       radius: 114, startAngle: 90, endAngle: 245, clockwise: false)
ochre.setStroke()
ringProgress.lineWidth = 22
ringProgress.stroke()

NSGraphicsContext.restoreGraphicsState()

let image = context.makeImage()!
let url = URL(fileURLWithPath: "docs/app-store/product-page-header.png") as CFURL
let destination = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("png") }
print("docs/app-store/product-page-header.png")
