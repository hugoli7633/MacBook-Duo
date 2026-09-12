import AppKit
import MetalKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

@main
struct ExportPreview {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let photo = NSImage(contentsOf: root.appendingPathComponent("Assets/MacBookPro14.png"))!
        var bounds = CGRect(origin: .zero, size: photo.size)
        let source = photo.cgImage(forProposedRect: &bounds, context: nil, hints: nil)!
        let lid = source.cropping(to: CGRect(x:460,y:274,width:280,height:190))!
        let base = source.cropping(to: CGRect(x:428,y:464,width:342,height:16))!
        let wallpaper = source.cropping(to: CGRect(x:466,y:284,width:268,height:174))!
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        let library = try device.makeLibrary(source: GlassMetalView.shader, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name:"vertexMain")
        descriptor.fragmentFunction = library.makeFunction(name:"glassMain")
        descriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
        let pipeline = try device.makeRenderPipelineState(descriptor:descriptor)
        let texture = try MTKTextureLoader(device:device).newTexture(cgImage:wallpaper,options:[.SRGB:false,.generateMipmaps:true])
        let targetDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:680,height:440,mipmapped:false)
        targetDescriptor.usage = [.renderTarget]
        targetDescriptor.storageMode = .shared
        let target = device.makeTexture(descriptor:targetDescriptor)!
        let ci = CIContext(mtlDevice:device)
        let output = root.appendingPathComponent("docs/images/settings-preview.gif")
        try FileManager.default.createDirectory(at:output.deletingLastPathComponent(),withIntermediateDirectories:true)
        let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString,150,nil)!
        CGImageDestinationSetProperties(destination,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        func context(_ w:Int,_ h:Int)->CGContext {
            CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:colorSpace,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        }
        func text(_ value:String,_ x:CGFloat,_ y:CGFloat,_ size:CGFloat,_ color:NSColor,_ bold:Bool=false) {
            (value as NSString).draw(at:NSPoint(x:x,y:y),withAttributes:[.font:bold ? NSFont.boldSystemFont(ofSize:size):NSFont.systemFont(ofSize:size),.foregroundColor:color])
        }
        for frame in 0..<150 {
            autoreleasepool {
                let angle=HingeDemoMotion.angle(time:Double(frame)/15,onset:90)
                let progress=EffectAngle.progress(angle:angle,onset:90)
                let pass=MTLRenderPassDescriptor()
                pass.colorAttachments[0].texture=target
                pass.colorAttachments[0].loadAction = .clear
                pass.colorAttachments[0].storeAction = .store
                let command=queue.makeCommandBuffer()!
                let encoder=command.makeRenderCommandEncoder(descriptor:pass)!
                var parameters:[Float]=[680,440,Float(80*progress),0.09,2.4,Float(texture.width)/Float(texture.height),0,0]
                encoder.setRenderPipelineState(pipeline)
                encoder.setFragmentTexture(texture,index:0)
                encoder.setFragmentBytes(&parameters,length:parameters.count*4,index:0)
                encoder.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3)
                encoder.endEncoding()
                command.commit()
                command.waitUntilCompleted()
                var bytes=[UInt8](repeating:0,count:680*440*4)
                target.getBytes(&bytes,bytesPerRow:680*4,from:MTLRegionMake2D(0,0,680,440),mipmapLevel:0)
                let provider=CGDataProvider(data:Data(bytes) as CFData)!
                let rendered=CGImage(width:680,height:440,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:680*4,space:colorSpace,bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent)!
                let screen=context(700,475)
                screen.draw(lid,in:CGRect(x:0,y:0,width:700,height:475))
                screen.saveGState()
                screen.addPath(CGPath(roundedRect:CGRect(x:10,y:17.5,width:680,height:440),cornerWidth:10,cornerHeight:10,transform:nil))
                screen.clip()
                screen.draw(rendered,in:CGRect(x:10,y:17.5,width:680,height:440))
                screen.restoreGState()
                screen.setFillColor(NSColor.black.cgColor)
                screen.fill(CGRect(x:310,y:447,width:80,height:16))
                let rotation=(angle-100)*0.5 * Double.pi/180
                let h=237.5*cos(rotation)
                let scale=1/(1 + sin(rotation)*0.12)
                let half=175*scale
                let transformed=CIImage(cgImage:screen.makeImage()!).applyingFilter("CIPerspectiveTransform",parameters:[
                    "inputTopLeft":CIVector(x:340-half,y:108+h),"inputTopRight":CIVector(x:340+half,y:108+h),
                    "inputBottomLeft":CIVector(x:165,y:108),"inputBottomRight":CIVector(x:515,y:108)])
                let canvas=context(680,430)
                canvas.setFillColor(NSColor(calibratedWhite:0.10,alpha:1).cgColor)
                canvas.fill(CGRect(x:0,y:0,width:680,height:430))
                canvas.setFillColor(NSColor(calibratedWhite:0.13,alpha:1).cgColor)
                canvas.addPath(CGPath(roundedRect:CGRect(x:18,y:18,width:644,height:394),cornerWidth:18,cornerHeight:18,transform:nil))
                canvas.fillPath()
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current=NSGraphicsContext(cgContext:canvas,flipped:false)
                text("MacBook Duo",40,374,18,.white,true)
                text("效果预览",40,349,12,.secondaryLabelColor)
                let status=progress>0 ? "逐渐模糊":"保持清晰"
                text(status,560,377,12,progress>0 ? .systemBlue:.lightGray)
                if let image=ci.createCGImage(transformed,from:CGRect(x:0,y:0,width:680,height:430)) { canvas.draw(image,in:CGRect(x:0,y:0,width:680,height:430)) }
                canvas.draw(base,in:CGRect(x:126.25,y:93,width:427.5,height:20))
                text("开合演示 · 低于 90° 开始模糊",40,58,13,.lightGray)
                text("示例壁纸 · 与应用共用 Metal 渲染及动画曲线",40,35,11,.gray)
                NSGraphicsContext.restoreGraphicsState()
                let image=canvas.makeImage()!
                CGImageDestinationAddImage(destination,image,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:1.0/15]] as CFDictionary)
                if frame == 0 || frame == 75 {
                    let png=CGImageDestinationCreateWithURL(FileManager.default.temporaryDirectory.appendingPathComponent("duo-preview-\(frame).png") as CFURL,UTType.png.identifier as CFString,1,nil)!
                    CGImageDestinationAddImage(png,image,nil)
                    CGImageDestinationFinalize(png)
                }
            }
        }
        guard CGImageDestinationFinalize(destination) else { fatalError("GIF export failed") }
        print("Exported 150 frames / 10 seconds: \(output.path)")
    }
}
