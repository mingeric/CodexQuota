import AppKit
import CoreGraphics
import Foundation

let side = 1024
guard CommandLine.arguments.count == 2,
      let context = CGContext(
        data: nil,
        width: side,
        height: side,
        bitsPerComponent: 8,
        bytesPerRow: side * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ) else {
    fatalError("Unable to create icon bitmap")
}

let bounds = CGRect(x: 0, y: 0, width: side, height: side)
let iconRect = bounds.insetBy(dx: 42, dy: 42)
let iconPath = CGPath(roundedRect: iconRect, cornerWidth: 220, cornerHeight: 220, transform: nil)
context.addPath(iconPath)
context.clip()

let colors = [
    CGColor(red: 0.035, green: 0.09, blue: 0.19, alpha: 1),
    CGColor(red: 0.08, green: 0.31, blue: 0.62, alpha: 1),
    CGColor(red: 0.10, green: 0.57, blue: 0.85, alpha: 1)
] as CFArray
let locations: [CGFloat] = [0, 0.58, 1]
if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) {
    context.drawLinearGradient(gradient, start: CGPoint(x: 150, y: 100), end: CGPoint(x: 900, y: 960), options: [])
}

context.setFillColor(CGColor(red: 0.35, green: 0.78, blue: 1, alpha: 0.22))
context.fillEllipse(in: CGRect(x: 575, y: 590, width: 500, height: 500))

let center = CGPoint(x: 512, y: 520)
let radius: CGFloat = 285
context.setStrokeColor(CGColor(red: 0.92, green: 0.97, blue: 1, alpha: 0.94))
context.setLineWidth(58)
context.setLineCap(CGLineCap.round)
context.addArc(center: center, radius: radius, startAngle: -38 * .pi / 180, endAngle: 218 * .pi / 180, clockwise: false)
context.strokePath()

context.setStrokeColor(CGColor(red: 0.55, green: 0.85, blue: 1, alpha: 0.9))
context.setLineWidth(17)
for degrees in [-38.0, 5.0, 48.0, 91.0, 134.0, 177.0, 218.0] {
    let angle = CGFloat(degrees) * .pi / 180
    let start = CGPoint(x: center.x + cos(angle) * 225, y: center.y + sin(angle) * 225)
    let end = CGPoint(x: center.x + cos(angle) * 250, y: center.y + sin(angle) * 250)
    context.move(to: start)
    context.addLine(to: end)
}
context.strokePath()

let needleAngle = CGFloat(48.0) * .pi / 180
context.setStrokeColor(CGColor(red: 0.23, green: 0.72, blue: 1, alpha: 1))
context.setLineWidth(42)
context.setLineCap(CGLineCap.round)
context.move(to: center)
context.addLine(to: CGPoint(x: center.x + cos(needleAngle) * 210, y: center.y + sin(needleAngle) * 210))
context.strokePath()
context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
context.fillEllipse(in: CGRect(x: center.x - 35, y: center.y - 35, width: 70, height: 70))

guard let image = context.makeImage(), let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode icon")
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
