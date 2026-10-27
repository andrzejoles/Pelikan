// Ikona Pelikana (PL-INFRA-012, D172): rysunek wektorowy w CoreGraphics — pelikan z dziobem i workiem na tle
// w kształcie ikony macOS, nad nim stos dysków bazy danych. Generuje PNG wszystkich rozmiarów do katalogu zasobów.
//
// Użycie: swift scripts/icon/make-icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset [podgląd.png]
import AppKit

let canvas: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Rysunek w układzie 1024×1024 z osią Y w dół (jak w edytorach grafiki).
func draw(_ ctx: CGContext) {
    ctx.translateBy(x: 0, y: canvas)
    ctx.scaleBy(x: 1, y: -1)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!

    // Tło: zaokrąglony kwadrat siatki ikon macOS (824 pt w polu 1024) z cieniem.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(squircle)
    ctx.setFillColor(color(0x0F3B6E))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let sky = CGGradient(colorsSpace: space, colors: [color(0x2E7BD1), color(0x123F78)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sky, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])

    // Woda: dwie fale w dolnej części.
    for (y, hex, a) in [(760.0, 0x5FB4F0, 0.35), (820.0, 0x8FD0FA, 0.30)] as [(CGFloat, UInt32, CGFloat)] {
        let wave = CGMutablePath()
        wave.move(to: CGPoint(x: 80, y: y))
        var x: CGFloat = 80
        while x < 960 {
            wave.addQuadCurve(to: CGPoint(x: x + 80, y: y), control: CGPoint(x: x + 40, y: y - 26))
            wave.addQuadCurve(to: CGPoint(x: x + 160, y: y), control: CGPoint(x: x + 120, y: y + 26))
            x += 160
        }
        wave.addLine(to: CGPoint(x: 960, y: 960))
        wave.addLine(to: CGPoint(x: 80, y: 960))
        wave.closeSubpath()
        ctx.addPath(wave)
        ctx.setFillColor(color(hex, a))
        ctx.fillPath()
    }

    // Stos dysków bazy danych (prawy dół) — Pelikan to narzędzie do Oracle.
    let db = CGRect(x: 655, y: 560, width: 180, height: 190), ry: CGFloat = 30
    let cylinder = CGMutablePath()
    cylinder.addRect(CGRect(x: db.minX, y: db.minY, width: db.width, height: db.height))
    cylinder.addEllipse(in: CGRect(x: db.minX, y: db.maxY - ry, width: db.width, height: 2 * ry))
    ctx.addPath(cylinder)
    let metal = CGGradient(colorsSpace: space, colors: [color(0xD5DFEC), color(0xFFFFFF), color(0xC3D0E2)] as CFArray, locations: [0, 0.4, 1])!
    ctx.saveGState()
    ctx.clip()
    ctx.drawLinearGradient(metal, start: CGPoint(x: db.minX, y: 0), end: CGPoint(x: db.maxX, y: 0), options: [])
    ctx.restoreGState()
    // Pasy dysków: dolne połówki elips.
    for y in [db.minY + db.height / 3, db.minY + 2 * db.height / 3] {
        let band = CGMutablePath()
        band.addArc(center: .zero, radius: 1, startAngle: 0, endAngle: .pi, clockwise: false,
                    transform: CGAffineTransform(translationX: db.midX, y: y).scaledBy(x: db.width / 2, y: ry))
        ctx.addPath(band)
        ctx.setStrokeColor(color(0x9FB2CC))
        ctx.setLineWidth(6)
        ctx.strokePath()
    }
    ctx.addEllipse(in: CGRect(x: db.minX, y: db.minY - ry, width: db.width, height: 2 * ry))
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()
    ctx.addEllipse(in: CGRect(x: db.minX + 3, y: db.minY - ry + 3, width: db.width - 6, height: 2 * ry - 6))
    ctx.setStrokeColor(color(0xB9C7DA))
    ctx.setLineWidth(5)
    ctx.strokePath()

    // Szyja: łuk od tułowia do głowy.
    let neck = CGMutablePath()
    neck.move(to: CGPoint(x: 330, y: 760))
    neck.addCurve(to: CGPoint(x: 380, y: 330), control1: CGPoint(x: 220, y: 600), control2: CGPoint(x: 280, y: 380))
    ctx.addPath(neck)
    ctx.setStrokeColor(color(0xFFFFFF))
    ctx.setLineWidth(118)
    ctx.strokePath()

    // Ciało i skrzydło pelikana (lewy dół).
    let wing = CGMutablePath()
    wing.move(to: CGPoint(x: 150, y: 960))
    wing.addCurve(to: CGPoint(x: 330, y: 610), control1: CGPoint(x: 140, y: 800), control2: CGPoint(x: 220, y: 640))
    wing.addCurve(to: CGPoint(x: 600, y: 960), control1: CGPoint(x: 470, y: 600), control2: CGPoint(x: 600, y: 760))
    wing.closeSubpath()
    ctx.addPath(wing)
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()
    let feathers = CGMutablePath()
    feathers.move(to: CGPoint(x: 250, y: 900))
    feathers.addCurve(to: CGPoint(x: 520, y: 900), control1: CGPoint(x: 330, y: 760), control2: CGPoint(x: 450, y: 760))
    feathers.move(to: CGPoint(x: 300, y: 960))
    feathers.addCurve(to: CGPoint(x: 560, y: 960), control1: CGPoint(x: 370, y: 850), control2: CGPoint(x: 490, y: 850))
    ctx.addPath(feathers)
    ctx.setStrokeColor(color(0xC9D5E4))
    ctx.setLineWidth(12)
    ctx.setLineCap(.round)
    ctx.strokePath()

    // Worek pod dziobem.
    let pouch = CGMutablePath()
    pouch.move(to: CGPoint(x: 420, y: 352))
    pouch.addCurve(to: CGPoint(x: 820, y: 400), control1: CGPoint(x: 520, y: 560), control2: CGPoint(x: 720, y: 520))
    pouch.addLine(to: CGPoint(x: 470, y: 330))
    pouch.closeSubpath()
    ctx.addPath(pouch)
    ctx.setFillColor(color(0xF08A24))
    ctx.fillPath()

    // Głowa.
    ctx.addEllipse(in: CGRect(x: 300, y: 225, width: 190, height: 180))
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()

    // Górna część dzioba z haczykiem na końcu.
    let beak = CGMutablePath()
    beak.move(to: CGPoint(x: 445, y: 280))
    beak.addCurve(to: CGPoint(x: 838, y: 386), control1: CGPoint(x: 600, y: 300), control2: CGPoint(x: 760, y: 340))
    beak.addQuadCurve(to: CGPoint(x: 818, y: 414), control: CGPoint(x: 852, y: 408))
    beak.addCurve(to: CGPoint(x: 440, y: 345), control1: CGPoint(x: 700, y: 390), control2: CGPoint(x: 560, y: 360))
    beak.closeSubpath()
    ctx.addPath(beak)
    ctx.setFillColor(color(0xFFC53D))
    ctx.fillPath()

    // Oko z błyskiem.
    ctx.addEllipse(in: CGRect(x: 392, y: 274, width: 34, height: 34))
    ctx.setFillColor(color(0x13253F))
    ctx.fillPath()
    ctx.addEllipse(in: CGRect(x: 404, y: 280, width: 11, height: 11))
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()

    // Delikatna obwódka tła.
    ctx.addPath(squircle)
    ctx.setStrokeColor(color(0xFFFFFF, 0.18))
    ctx.setLineWidth(3)
    ctx.strokePath()
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    let ctx = gc.cgContext
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    draw(ctx)
    gc.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    try? FileHandle.standardError.write(contentsOf: Data("Użycie: make-icon.swift KATALOG.appiconset [podgląd.png]\n".utf8))
    exit(1)
}
let dir = URL(fileURLWithPath: args[1])
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try png(size: points * scale).write(to: dir.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: dir.appendingPathComponent("Contents.json"))
if args.count >= 3 { try png(size: 1024).write(to: URL(fileURLWithPath: args[2])) }
