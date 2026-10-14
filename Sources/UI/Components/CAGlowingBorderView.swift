import SwiftUI
import AppKit
import QuartzCore

/// GPU-Accelerated Core Animation glowing border view that traces the screen perimeter,
/// rounded corners, and MacBook notch cutout with a rotating angular gradient and multi-tier glows.
struct CAGlowingBorderView: NSViewRepresentable {
    let primaryColor: NSColor
    let secondaryColor: NSColor
    let notchShape: NeonBorderShape
    let glowIntensity: CGFloat
    let beatPulse: CGFloat
    
    func makeNSView(context: Context) -> GlowingBorderNSView {
        let view = GlowingBorderNSView()
        view.update(
            primaryColor: primaryColor,
            secondaryColor: secondaryColor,
            shape: notchShape,
            intensity: glowIntensity,
            beatPulse: beatPulse
        )
        return view
    }
    
    func updateNSView(_ nsView: GlowingBorderNSView, context: Context) {
        nsView.update(
            primaryColor: primaryColor,
            secondaryColor: secondaryColor,
            shape: notchShape,
            intensity: glowIntensity,
            beatPulse: beatPulse
        )
    }
}

final class GlowingBorderNSView: NSView {
    override var isFlipped: Bool { true }
    
    private let outerGlowLayer = CAShapeLayer()
    private let midGlowLayer = CAShapeLayer()
    private let gradientContainerLayer = CALayer()
    private let gradientLayer = CAGradientLayer()
    private let gradientMaskLayer = CAShapeLayer()
    private let coreStrokeLayer = CAShapeLayer()
    
    private var lastBounds: CGRect = .zero
    private var currentShape: NeonBorderShape = NeonBorderShape.forScreen()
    private var currentPrimaryColor: NSColor = .systemPink
    private var currentSecondaryColor: NSColor = .systemPurple
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }
    
    private func setupLayers() {
        wantsLayer = true
        guard let rootLayer = layer else { return }
        rootLayer.masksToBounds = false
        
        // 1. Outer Glow Layer (24pt shadow blur)
        outerGlowLayer.fillColor = nil
        outerGlowLayer.shadowOffset = .zero
        outerGlowLayer.shadowRadius = 24.0
        outerGlowLayer.shadowOpacity = 0.70
        outerGlowLayer.lineWidth = 4.0
        
        // 2. Mid Glow Layer (8pt shadow blur)
        midGlowLayer.fillColor = nil
        midGlowLayer.shadowOffset = .zero
        midGlowLayer.shadowRadius = 8.0
        midGlowLayer.shadowOpacity = 0.85
        midGlowLayer.lineWidth = 3.0
        
        // 3. Conic Gradient Layer for rotating border color
        gradientContainerLayer.masksToBounds = false
        
        gradientLayer.type = .conic
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1.0, y: 0.5)
        
        gradientMaskLayer.fillColor = nil
        gradientMaskLayer.lineWidth = 2.5
        gradientMaskLayer.strokeColor = NSColor.white.cgColor
        gradientContainerLayer.mask = gradientMaskLayer
        gradientContainerLayer.addSublayer(gradientLayer)
        
        // 4. Core Crisp Stroke Layer (2 to 3pt)
        coreStrokeLayer.fillColor = nil
        coreStrokeLayer.lineWidth = 2.0
        
        rootLayer.addSublayer(outerGlowLayer)
        rootLayer.addSublayer(midGlowLayer)
        rootLayer.addSublayer(gradientContainerLayer)
        rootLayer.addSublayer(coreStrokeLayer)
        
        startRotationAnimation()
    }
    
    private func startRotationAnimation() {
        // GPU rotation animation: 1 revolution per ~12 seconds
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0.0
        rotation.toValue = Double.pi * 2.0
        rotation.duration = 12.0
        rotation.repeatCount = .infinity
        rotation.isRemovedOnCompletion = false
        gradientLayer.add(rotation, forKey: "borderGradientRotation")
    }
    
    override func layout() {
        super.layout()
        updateGeometryIfNeeded()
    }
    
    func update(primaryColor: NSColor, secondaryColor: NSColor, shape: NeonBorderShape, intensity: CGFloat, beatPulse: CGFloat) {
        self.currentPrimaryColor = primaryColor
        self.currentSecondaryColor = secondaryColor
        self.currentShape = shape
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        let c1 = primaryColor.cgColor
        let c2 = secondaryColor.cgColor
        let accent = primaryColor.blended(withFraction: 0.5, of: secondaryColor)?.cgColor ?? c1
        gradientLayer.colors = [c1, c2, accent, c1]
        
        let pulseFactor = 1.0 + beatPulse * 0.20
        outerGlowLayer.strokeColor = c1
        outerGlowLayer.shadowColor = c1
        outerGlowLayer.shadowRadius = 24.0 * pulseFactor
        outerGlowLayer.shadowOpacity = Float(min(1.0, 0.70 * (intensity / 22.0) * pulseFactor))
        
        midGlowLayer.strokeColor = c2
        midGlowLayer.shadowColor = c2
        midGlowLayer.shadowRadius = 8.0 * pulseFactor
        midGlowLayer.shadowOpacity = Float(min(1.0, 0.85 * (intensity / 22.0) * pulseFactor))
        
        coreStrokeLayer.strokeColor = NSColor.white.withAlphaComponent(0.92).cgColor
        
        updateGeometryIfNeeded()
        CATransaction.commit()
    }
    
    private func updateGeometryIfNeeded() {
        guard bounds.width > 0 && bounds.height > 0 else { return }
        
        let path = currentShape.cgPath(in: bounds)
        
        gradientContainerLayer.frame = bounds
        gradientMaskLayer.frame = bounds
        gradientMaskLayer.path = path
        
        let maxDim = max(bounds.width, bounds.height) * 1.5
        let center = CGPoint(x: bounds.width / 2.0, y: bounds.height / 2.0)
        gradientLayer.bounds = CGRect(x: 0, y: 0, width: maxDim, height: maxDim)
        gradientLayer.position = center
        
        outerGlowLayer.frame = bounds
        outerGlowLayer.path = path
        
        midGlowLayer.frame = bounds
        midGlowLayer.path = path
        
        coreStrokeLayer.frame = bounds
        coreStrokeLayer.path = path
    }
}
