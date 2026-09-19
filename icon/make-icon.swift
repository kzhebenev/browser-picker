import AppKit

// Иконка: скруглённый квадрат с развилкой — одна ссылка, несколько браузеров.
// Запуск: swift icon/make-icon.swift  (создаёт icon/AppIcon.iconset)

let top = NSColor(red: 0.20, green: 0.52, blue: 0.98, alpha: 1)
let bottom = NSColor(red: 0.36, green: 0.28, blue: 0.86, alpha: 1)

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let inset = size * 0.08
    let body = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let shape = NSBezierPath(roundedRect: body, xRadius: size * 0.2, yRadius: size * 0.2)
    NSGradient(colors: [top, bottom])?.draw(in: shape, angle: -90)

    // Развилка: ствол снизу, три ветки вверх с точками-браузерами
    NSColor.white.setStroke()
    NSColor.white.setFill()
    let w = size * 0.07
    let cx = size / 2
    let fork = NSPoint(x: cx, y: size * 0.46)
    let trunk = NSBezierPath()
    trunk.move(to: NSPoint(x: cx, y: size * 0.22))
    trunk.line(to: fork)
    trunk.lineWidth = w
    trunk.lineCapStyle = .round
    trunk.stroke()
    let ends = [NSPoint(x: size * 0.28, y: size * 0.70), NSPoint(x: cx, y: size * 0.74), NSPoint(x: size * 0.72, y: size * 0.70)]
    for end in ends {
        let branch = NSBezierPath()
        branch.move(to: fork)
        branch.curve(to: end, controlPoint1: NSPoint(x: cx, y: size * 0.56), controlPoint2: NSPoint(x: end.x, y: size * 0.56))
        branch.lineWidth = w
        branch.lineCapStyle = .round
        branch.stroke()
        let r = size * 0.075
        NSBezierPath(ovalIn: NSRect(x: end.x - r, y: end.y - r, width: r * 2, height: r * 2)).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let iconset = "icon/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
let variants: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, size) in variants {
    let rep = drawIcon(size: size)
    guard let data = rep.representation(using: .png, properties: [:]) else { continue }
    try? data.write(to: URL(fileURLWithPath: "\(iconset)/\(name).png"))
}
print("iconset готов: \(iconset)")
