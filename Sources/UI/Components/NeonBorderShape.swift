import SwiftUI

/// Neon border shape that precisely traces the display perimeter,
/// including an optional top notch cutout matching MacBook displays.
struct NeonBorderShape: Shape {
    var notchCompatible: Bool = true
    var cornerRadius: CGFloat = 16
    var notchWidth: CGFloat = 200
    var notchHeight: CGFloat = 34
    var notchCornerRadius: CGFloat = 8
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard rect.width > 0 && rect.height > 0 else { return path }
        
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY
        let midX = rect.midX
        
        if !notchCompatible {
            // Standard rounded rectangle perimeter
            path.addRoundedRect(
                in: rect,
                cornerSize: CGSize(width: cornerRadius, height: cornerRadius)
            )
            return path
        }
        
        // Detailed perimeter path with MacBook notch cutout
        let cr = min(cornerRadius, 24)
        let ncr = min(notchCornerRadius, 10)
        let halfNotch = notchWidth / 2.0
        
        // 1. Start after top-left corner
        path.move(to: CGPoint(x: minX + cr, y: minY))
        
        // 2. Top edge left of notch
        let notchLeft = midX - halfNotch
        path.addLine(to: CGPoint(x: notchLeft - ncr, y: minY))
        
        // Curve down into left side of notch
        path.addQuadCurve(
            to: CGPoint(x: notchLeft, y: minY + ncr),
            control: CGPoint(x: notchLeft, y: minY)
        )
        
        // Down left side of notch
        path.addLine(to: CGPoint(x: notchLeft, y: minY + notchHeight - ncr))
        
        // Curve to bottom of notch
        path.addQuadCurve(
            to: CGPoint(x: notchLeft + ncr, y: minY + notchHeight),
            control: CGPoint(x: notchLeft, y: minY + notchHeight)
        )
        
        // Across bottom of notch
        let notchRight = midX + halfNotch
        path.addLine(to: CGPoint(x: notchRight - ncr, y: minY + notchHeight))
        
        // Curve up right side of notch
        path.addQuadCurve(
            to: CGPoint(x: notchRight, y: minY + notchHeight - ncr),
            control: CGPoint(x: notchRight, y: minY + notchHeight)
        )
        
        // Up right side of notch
        path.addLine(to: CGPoint(x: notchRight, y: minY + ncr))
        
        // Curve to top edge right of notch
        path.addQuadCurve(
            to: CGPoint(x: notchRight + ncr, y: minY),
            control: CGPoint(x: notchRight, y: minY)
        )
        
        // Top edge right of notch to top-right corner
        path.addLine(to: CGPoint(x: maxX - cr, y: minY))
        
        // Top-right corner
        path.addQuadCurve(
            to: CGPoint(x: maxX, y: minY + cr),
            control: CGPoint(x: maxX, y: minY)
        )
        
        // Right edge
        path.addLine(to: CGPoint(x: maxX, y: maxY - cr))
        
        // Bottom-right corner
        path.addQuadCurve(
            to: CGPoint(x: maxX - cr, y: maxY),
            control: CGPoint(x: maxX, y: maxY)
        )
        
        // Bottom edge
        path.addLine(to: CGPoint(x: minX + cr, y: maxY))
        
        // Bottom-left corner
        path.addQuadCurve(
            to: CGPoint(x: minX, y: maxY - cr),
            control: CGPoint(x: minX, y: maxY)
        )
        
        // Left edge
        path.addLine(to: CGPoint(x: minX, y: minY + cr))
        
        // Top-left corner
        path.addQuadCurve(
            to: CGPoint(x: minX + cr, y: minY),
            control: CGPoint(x: minX, y: minY)
        )
        
        path.closeSubpath()
        return path
    }
    
    func cgPath(in rect: CGRect) -> CGPath {
        return path(in: rect).cgPath
    }
    
    static func forScreen(_ screen: NSScreen? = NSScreen.main ?? NSScreen.screens.first) -> NeonBorderShape {
        guard let s = screen else {
            return NeonBorderShape(notchCompatible: false, cornerRadius: 18)
        }
        let topInset = s.safeAreaInsets.top
        if topInset > 0, let leftAux = s.auxiliaryTopLeftArea, let rightAux = s.auxiliaryTopRightArea, leftAux.width > 0, rightAux.width > 0 {
            let notchW = max(160, rightAux.minX - leftAux.maxX)
            let notchH = topInset
            return NeonBorderShape(
                notchCompatible: true,
                cornerRadius: 18,
                notchWidth: notchW,
                notchHeight: notchH,
                notchCornerRadius: 10
            )
        } else if topInset > 0 {
            return NeonBorderShape(
                notchCompatible: true,
                cornerRadius: 18,
                notchWidth: 200,
                notchHeight: topInset,
                notchCornerRadius: 10
            )
        } else {
            return NeonBorderShape(notchCompatible: false, cornerRadius: 18)
        }
    }
}
