// Genera el icono de la app (1024x1024 PNG) con CoreGraphics.
// uso: swift tool/make_icon.swift <salida.png> [tamaño]
import AppKit

let args = CommandLine.arguments
let outPath = args.count > 1 ? args[1] : "icon.png"
let size = args.count > 2 ? Int(args[2]) ?? 1024 : 1024
let S = CGFloat(size)

let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
  fatalError("ctx")
}

// Fondo: gradiente azul con esquinas redondeadas (estilo squircle simple).
let bg = CGMutablePath()
let r: CGFloat = S * 0.22
bg.addRoundedRect(in: CGRect(x: 0, y: 0, width: S, height: S),
                  cornerWidth: r, cornerHeight: r)
ctx.addPath(bg); ctx.clip()

let grad = CGGradient(colorsSpace: cs,
  colors: [CGColor(red: 0.12, green: 0.40, blue: 0.78, alpha: 1),
           CGColor(red: 0.08, green: 0.23, blue: 0.55, alpha: 1)] as CFArray,
  locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: S),
                       end: CGPoint(x: S, y: 0), options: [])

// Hexágono (anillo bencénico) centrado.
let cx = S/2, cy = S * 0.56, rad = S * 0.26
let hex = CGMutablePath()
for i in 0..<6 {
  let a = CGFloat.pi/2 + CGFloat(i) * CGFloat.pi/3
  let p = CGPoint(x: cx + rad * cos(a), y: cy + rad * sin(a))
  if i == 0 { hex.move(to: p) } else { hex.addLine(to: p) }
}
hex.closeSubpath()
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
ctx.setLineWidth(S * 0.045)
ctx.setLineJoin(.round)
ctx.addPath(hex); ctx.strokePath()

// Círculo interior (aromaticidad).
ctx.setLineWidth(S * 0.03)
ctx.addEllipse(in: CGRect(x: cx - rad*0.52, y: cy - rad*0.52,
                          width: rad*1.04, height: rad*1.04))
ctx.strokePath()

// Texto "CAS".
let nsctx = NSGraphicsContext(cgContext: ctx, flipped: false)
NSGraphicsContext.current = nsctx
let text = "CAS"
let font = NSFont.systemFont(ofSize: S * 0.20, weight: .heavy)
let attrs: [NSAttributedString.Key: Any] = [
  .font: font,
  .foregroundColor: NSColor.white,
]
let str = NSAttributedString(string: text, attributes: attrs)
let tsize = str.size()
str.draw(at: NSPoint(x: cx - tsize.width/2, y: S * 0.13))

guard let img = ctx.makeImage() else { fatalError("img") }
let rep = NSBitmapImageRep(cgImage: img)
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath) (\(size)px)")
