import SwiftUI

/// Keeps the signing area clear of the iPhone Duo's fold.
///
/// On iPhone Duo the fold is reported as a "division" reserved region. Only
/// *active* regions are returned by default, and the fold's region is inactive
/// with zero width while the device is flat — so a non-empty result means the
/// device is folded and a hinge physically crosses this view. Signing across a
/// hinge is miserable, so the pad is inset to the widest fold-free slice.
@available(iOS 27.1, *)
struct FoldAwareSignaturePad: View {
    @Binding var signatureImage: UIImage?
    @Binding var hasSignature: Bool
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let folds = proxy.reservedRegions(kind: .division).map(\.frame)
            let area = Self.widestFoldFreeRect(in: bounds, folds: folds)

            SignaturePad(signatureImage: $signatureImage, hasSignature: $hasSignature)
                .frame(width: area.width, height: area.height)
                .offset(x: area.minX, y: area.minY)
        }
        .frame(height: height)
    }

    /// The widest vertical slice of `bounds` that no fold crosses.
    ///
    /// A fold that spans the whole width (or misses this view entirely) can't be
    /// dodged horizontally, so `bounds` is returned unchanged in those cases.
    static func widestFoldFreeRect(in bounds: CGRect, folds: [CGRect]) -> CGRect {
        let crossing = folds
            .filter { $0.intersects(bounds) && $0.width < bounds.width }
            .sorted { $0.minX < $1.minX }
        guard !crossing.isEmpty else { return bounds }

        var slices: [CGRect] = []
        var cursor = bounds.minX
        for fold in crossing {
            if fold.minX > cursor {
                slices.append(CGRect(x: cursor, y: bounds.minY,
                                     width: fold.minX - cursor, height: bounds.height))
            }
            cursor = max(cursor, fold.maxX)
        }
        if bounds.maxX > cursor {
            slices.append(CGRect(x: cursor, y: bounds.minY,
                                 width: bounds.maxX - cursor, height: bounds.height))
        }
        // Every slice was degenerate (a fold covering the view) — keep the
        // original bounds rather than collapsing the pad to nothing.
        return slices.max { $0.width < $1.width } ?? bounds
    }
}
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
