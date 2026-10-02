import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Окно «Settle»: 1440×900 по центру экрана, минимум 1100×720.
    self.title = "Settle"
    self.minSize = NSSize(width: 1100, height: 720)
    if let screen = NSScreen.main?.visibleFrame {
      let width = min(1440, screen.width - 40)
      let height = min(900, screen.height - 40)
      let frame = NSRect(
        x: screen.midX - width / 2,
        y: screen.midY - height / 2,
        width: width,
        height: height)
      self.setFrame(frame, display: true)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
