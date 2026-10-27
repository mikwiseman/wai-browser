import AppKit
import Foundation
let root=URL(fileURLWithPath:CommandLine.arguments[1])
let iconset=root.appendingPathComponent("work/AppIcon.iconset")
try FileManager.default.createDirectory(at:iconset,withIntermediateDirectories:true)
for size in [16,32,128,256,512] {
 for scale in [1,2] {
  let pixels=size*scale
  let image=NSImage(size:NSSize(width:pixels,height:pixels))
  image.lockFocus()
  let context=NSGraphicsContext.current!.cgContext
  context.scaleBy(x:CGFloat(pixels)/1024,y:CGFloat(pixels)/1024)
  NSColor(calibratedRed:0.94,green:0.94,blue:0.90,alpha:1).setFill()
  NSBezierPath(roundedRect:NSRect(x:32,y:32,width:960,height:960),xRadius:210,yRadius:210).fill()
  let text="w" as NSString
  let attributes:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:690,weight:.bold),.foregroundColor:NSColor(calibratedRed:0.14,green:0.15,blue:0.12,alpha:1)]
  text.draw(at:NSPoint(x:120,y:120),withAttributes:attributes)
  NSColor(calibratedRed:0.53,green:0.58,blue:0.27,alpha:1).setFill()
  NSBezierPath(ovalIn:NSRect(x:729,y:238,width:115,height:115)).fill()
  image.unlockFocus()
  let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!
  let file="icon_\(size)x\(size)\(scale==2 ? "@2x" : "").png"
  try bitmap.representation(using:.png,properties:[:])!.write(to:iconset.appendingPathComponent(file))
 }
}
