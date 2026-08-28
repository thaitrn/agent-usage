import AppKit
import UsageCore

/// Menu bar mark: a stylised "T" (for Thái) built like the Tesla wordmark —
/// a detached crescent above a swept crossbar with a tapering blade stem.
enum BrandIcon {
    /// Normal stays a template image so it follows the menu bar's own colour;
    /// warning and critical are tinted, which is exactly when it should stand out.
    private static let normal = make(tint: nil)
    private static let warning = make(tint: .systemOrange)
    private static let critical = make(tint: .systemRed)

    static func image(for severity: Severity) -> NSImage {
        switch severity {
        case .normal: normal
        case .warning: warning
        case .critical: critical
        }
    }

    private static func make(tint: NSColor?, width: CGFloat = 13, height: CGFloat = 15) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            (tint ?? .black).setFill()

            // Crescent cap: two arcs sharing endpoints, the gap under it is what
            // makes the Tesla mark read as a blade rather than a plain T.
            let cap = NSBezierPath()
            cap.move(to: NSPoint(x: 2.9, y: 12.5))
            cap.curve(to: NSPoint(x: 10.1, y: 12.5),
                      controlPoint1: NSPoint(x: 4.6, y: 15.1), controlPoint2: NSPoint(x: 8.4, y: 15.1))
            cap.curve(to: NSPoint(x: 2.9, y: 12.5),
                      controlPoint1: NSPoint(x: 8.3, y: 13.6), controlPoint2: NSPoint(x: 4.7, y: 13.6))
            cap.close()
            cap.fill()

            // Crossbar with swept-up ends, flowing into a stem that tapers downward.
            let body = NSBezierPath()
            body.move(to: NSPoint(x: 0.5, y: 12.1))
            body.curve(to: NSPoint(x: 12.5, y: 12.1),
                       controlPoint1: NSPoint(x: 4.5, y: 11.95), controlPoint2: NSPoint(x: 8.5, y: 11.95))
            body.line(to: NSPoint(x: 11.9, y: 11.0))
            body.curve(to: NSPoint(x: 7.5, y: 9.7),
                       controlPoint1: NSPoint(x: 10.4, y: 10.5), controlPoint2: NSPoint(x: 8.8, y: 10.0))
            body.line(to: NSPoint(x: 7.0, y: 0.6))
            body.line(to: NSPoint(x: 6.0, y: 0.6))
            body.line(to: NSPoint(x: 5.5, y: 9.7))
            body.curve(to: NSPoint(x: 1.1, y: 11.0),
                       controlPoint1: NSPoint(x: 4.2, y: 10.0), controlPoint2: NSPoint(x: 2.6, y: 10.5))
            body.close()
            body.fill()
            return true
        }
        image.isTemplate = tint == nil // template follows menu bar light/dark automatically
        return image
    }
}
