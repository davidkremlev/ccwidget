import AppKit
import SwiftUI

/// The window as a pane of translucent material over the desktop.
///
/// **A departure from Apple's adoption guide, named as one.** The guide puts
/// Liquid Glass on the layer of controls and navigation and asks for custom
/// backgrounds under content to be reduced, not added. The owner chose the
/// translucent window over the opaque one on 21 August 2026, with that on
/// the table and with the measurement of 18 August in hand: real Liquid
/// Glass (`NSGlassEffectView`) draws opaque as a window background — it
/// refracts only its own window's content, never the desktop — so the
/// see-through look system panels have is not available to an application,
/// and what this uses instead is the pre-glass translucent material,
/// `NSVisualEffectView` with `.behindWindow` blending
/// (`apple/appkit-nsvisualeffectview.md`). The toolbar above keeps its real
/// Liquid Glass; the two coexist.
///
/// `.popover` rather than `.hudWindow` or `.underWindowBackground`: the three
/// were rendered side by side on 18 August and this one kept the quiet grey
/// text readable while still letting the desktop through. `.state = .active`
/// on purpose — the default follows the window's key state, and a glanceable
/// window that turns flat whenever it is not frontmost would spend most of
/// its life looking like the opaque window this replaces.
struct WindowBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> BackdropView { BackdropView() }
    func updateNSView(_ view: BackdropView, context: Context) {}
}

final class BackdropView: NSView {
    private let material: NSVisualEffectView

    override init(frame: NSRect) {
        material = NSVisualEffectView()
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        super.init(frame: frame)
        material.autoresizingMask = [.width, .height]
        material.frame = bounds
        addSubview(material)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// The window made see-through around the material. Done here because
    /// SwiftUI's `Window` scene hands out no `NSWindow`, and this is the
    /// first moment the view can reach the one it lives in. The flags are
    /// idempotent; a view that moves twice does no harm.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
    }
}

/// SwiftUI paints its own opaque ground behind the window's content;
/// `containerBackground(.clear, for: .window)` is what turns that off, and it
/// exists from macOS 15. **On macOS 14 this is a no-op and the window most
/// likely stays opaque — unverified**, no macOS 14 desktop has rendered this
/// (the same standing gap README's Requirements section admits for the tiles).
/// The degradation is the window this project shipped until today.
struct ClearWindowGround: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.containerBackground(.clear, for: .window)
        } else {
            content
        }
    }
}
