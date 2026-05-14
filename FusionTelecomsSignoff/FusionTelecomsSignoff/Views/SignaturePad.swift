import SwiftUI
import UIKit

struct SignaturePad: UIViewRepresentable {
    @Binding var signatureImage: UIImage?
    @Binding var hasSignature: Bool

    func makeUIView(context: Context) -> SignaturePadUIView {
        let view = SignaturePadUIView()
        view.onChanged = { image, signed in
            signatureImage = image
            hasSignature = signed
        }
        return view
    }

    func updateUIView(_ uiView: SignaturePadUIView, context: Context) {}
}

final class SignaturePadUIView: UIView {
    var onChanged: ((UIImage?, Bool) -> Void)?

    private var paths: [UIBezierPath] = []
    private var currentPath: UIBezierPath?
    private var previousPoint: CGPoint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        backgroundColor = .white
        layer.borderWidth = 1.5
        layer.borderColor = UIColor.systemGray4.cgColor
        layer.cornerRadius = 12
        isMultipleTouchEnabled = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let path = UIBezierPath()
        path.lineWidth = 2.5
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        let point = touch.location(in: self)
        path.move(to: point)
        previousPoint = point
        currentPath = path
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let path = currentPath else { return }
        let current = touch.location(in: self)
        if let prev = previousPoint {
            let mid = CGPoint(x: (prev.x + current.x) / 2, y: (prev.y + current.y) / 2)
            path.addQuadCurve(to: mid, controlPoint: prev)
        }
        previousPoint = current
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let path = currentPath else { return }
        path.addLine(to: touch.location(in: self))
        paths.append(path)
        currentPath = nil
        previousPoint = nil
        notifyChange()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        currentPath = nil
        previousPoint = nil
        notifyChange()
    }

    override func draw(_ rect: CGRect) {
        UIColor.black.setStroke()
        for path in paths { path.stroke() }
        currentPath?.stroke()
    }

    func clear() {
        paths.removeAll()
        currentPath = nil
        previousPoint = nil
        setNeedsDisplay()
        onChanged?(nil, false)
    }

    func captureImage() -> UIImage? {
        guard !paths.isEmpty else { return nil }
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        return renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(bounds)
            UIColor.black.setStroke()
            for path in paths { path.stroke() }
        }
    }

    private func notifyChange() {
        onChanged?(captureImage(), !paths.isEmpty)
    }
}
