import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var lockChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 980, height: 640)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Tell Flutter to lock HQ when the Mac sleeps, the display sleeps,
    // the screen is locked, or you switch user. (lib/lock/lock_controller.dart)
    lockChannel = FlutterMethodChannel(
      name: "gemstok_hq/lock",
      binaryMessenger: flutterViewController.engine.binaryMessenger)

    let workspace = NSWorkspace.shared.notificationCenter
    workspace.addObserver(self, selector: #selector(lockNow),
                          name: NSWorkspace.willSleepNotification, object: nil)
    workspace.addObserver(self, selector: #selector(lockNow),
                          name: NSWorkspace.screensDidSleepNotification, object: nil)
    workspace.addObserver(self, selector: #selector(lockNow),
                          name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
    DistributedNotificationCenter.default().addObserver(
      self, selector: #selector(lockNow),
      name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)

    super.awakeFromNib()
  }

  @objc private func lockNow() {
    lockChannel?.invokeMethod("lockNow", arguments: nil)
  }
}
