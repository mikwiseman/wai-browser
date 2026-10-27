import AppKit
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 4096, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
NSColor(calibratedRed: 0.94, green: 0.94, blue: 0.90, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill()
("w" as NSString).draw(at: NSPoint(x: 120, y: 120), withAttributes: [.font: NSFont.systemFont(ofSize: 690, weight: .bold), .foregroundColor: NSColor(calibratedRed: 0.14, green: 0.15, blue: 0.12, alpha: 1)])
NSColor(calibratedRed: 0.53, green: 0.58, blue: 0.27, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 729, y: 238, width: 115, height: 115)).fill()
NSGraphicsContext.restoreGraphicsState()
let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
try bitmap.representation(using: .png, properties: [:])!.write(to: output)
