import AppKit

extension NSImage {
    /// Returns the dominant color of the image by sampling the center pixel.
    var dominantColor: NSColor? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        
        let x = bitmap.pixelsWide / 2
        let y = bitmap.pixelsHigh / 2
        
        return bitmap.colorAt(x: x, y: y)
    }
    
    /// Resizes the image to the specified size.
    func resized(to newSize: NSSize) -> NSImage {
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1.0
        )
        
        newImage.unlockFocus()
        return newImage
    }
}
