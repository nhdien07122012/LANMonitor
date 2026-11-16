import os

def patch():
    app_delegate_path = os.path.join(os.path.dirname(__file__), 'ios', 'Runner', 'AppDelegate.swift')
    if not os.path.exists(app_delegate_path):
        print(f"File not found: {app_delegate_path}")
        return

    swift_code = """import Flutter
import UIKit
import WidgetKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "com.lanmonitor/widget", binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
        if call.method == "updateWidget", let args = call.arguments as? [String: Any] {
          let defaults = UserDefaults(suiteName: "group.com.lanmonitor.lanMonitor") ?? UserDefaults(suiteName: "group.com.lanmonitor.app")
          if let defaults = defaults {
            for (key, val) in args {
              defaults.set(val, forKey: key)
            }
            defaults.synchronize()
          }
          if #available(iOS 14.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
          }
          result(true)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
"""
    with open(app_delegate_path, 'w', encoding='utf-8') as f:
        f.write(swift_code)
    print("Successfully patched AppDelegate.swift with AppGroup Widget synchronization.")

if __name__ == '__main__':
    patch()
