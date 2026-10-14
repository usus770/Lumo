import AppKit
import CoreImage
import Accelerate

public enum PaletteExtractor {
    
    /// Extracts the dominant and secondary colors from an image.
    public static func extractColors(from data: Data?) -> (primary: NSColor, secondary: NSColor) {
        guard let data = data, let image = NSImage(data: data) else {
            return (.systemBlue, .systemPurple)
        }
        
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let ciImage = CIImage(bitmapImageRep: bitmap) else {
            return (.systemBlue, .systemPurple)
        }
        
        // 1. Resize the image down to 1x1 to get the absolute average color
        let filter = CIFilter(name: "CIAreaAverage")!
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: ciImage.extent), forKey: kCIInputExtentKey)
        
        var primary = NSColor.systemBlue
        if let outputImage = filter.outputImage {
            let context = CIContext(options: [.workingColorSpace: NSNull()])
            var bitmap = [UInt8](repeating: 0, count: 4)
            context.render(outputImage,
                           toBitmap: &bitmap,
                           rowBytes: 4,
                           bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                           format: .RGBA8,
                           colorSpace: nil)
            
            primary = NSColor(red: CGFloat(bitmap[0]) / 255.0,
                              green: CGFloat(bitmap[1]) / 255.0,
                              blue: CGFloat(bitmap[2]) / 255.0,
                              alpha: 1.0)
        }
        
        // Ensure primary has enough saturation
        let hsba = primary.hsba
        let safePrimary = NSColor(calibratedHue: hsba.h,
                                  saturation: max(0.4, hsba.s),
                                  brightness: max(0.4, hsba.b),
                                  alpha: 1.0)
        
        // Create a complementary/analogous secondary color
        let secondary = NSColor(calibratedHue: fmod(hsba.h + 0.15, 1.0),
                                saturation: max(0.5, hsba.s),
                                brightness: max(0.3, hsba.b - 0.2),
                                alpha: 1.0)
        
        return (safePrimary, secondary)
    }
}

extension NSColor {
    var hsba: (h: CGFloat, s: CGFloat, b: CGFloat, a: CGFloat) {
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        
        if let rgb = self.usingColorSpace(.deviceRGB) {
            rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        }
        
        return (h, s, b, a)
    }
}
