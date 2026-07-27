import AppKit

/// Hosts a third-party Audio Unit instrument's own view controller (e.g.
/// Kontakt's or MainStage's patch browser) in a dedicated window — these are
/// often full-featured plugin UIs that don't belong embedded inline in
/// PipePlayer's compact player window.
final class PluginWindowController: NSWindowController {
    convenience init(viewController: NSViewController, title: String) {
        let fittingSize = viewController.view.fittingSize
        let size = (fittingSize.width > 0 && fittingSize.height > 0)
            ? fittingSize
            : NSSize(width: 480, height: 360)
        let window = NSWindow(contentViewController: viewController)
        window.title = title
        window.setContentSize(size)
        window.styleMask.insert([.titled, .closable, .resizable])
        self.init(window: window)
    }
}
