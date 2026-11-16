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

    // Call super first to ensure window and rootViewController are properly initialized
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    // Retrieve FlutterViewController after window initialization
    let rootVC = window?.rootViewController ?? UIApplication.shared.windows.first?.rootViewController
    if let controller = rootVC as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "com.lanmonitor/widget", binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { (call: FlutterMethodCall, resultHandler: @escaping FlutterResult) in
        if call.method == "updateWidget", let args = call.arguments as? [String: Any] {
          let suiteNames = ["group.com.lanmonitor.lanMonitor", "group.com.lanmonitor.app"]
          
          // 1. Write to App Group UserDefaults
          for suite in suiteNames {
            if let defaults = UserDefaults(suiteName: suite) {
              for (key, val) in args {
                defaults.set(val, forKey: key)
              }
              defaults.synchronize()
            }
          }

          // 2. Dual redundancy: Write to shared App Group container JSON file
          for suite in suiteNames {
            if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suite) {
              let fileURL = containerURL.appendingPathComponent("widget_data.json")
              if let jsonData = try? JSONSerialization.data(withJSONObject: args, options: []) {
                try? jsonData.write(to: fileURL)
              }
            }
          }

          // 3. Request WidgetKit reload immediately
          if #available(iOS 14.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
          }
          resultHandler(true)
        } else {
          resultHandler(FlutterMethodNotImplemented)
        }
      }
    }

    return result
  }
}
"""
    with open(app_delegate_path, 'w', encoding='utf-8') as f:
        f.write(swift_code)
    print("Successfully patched AppDelegate.swift with AppGroup Widget synchronization.")

if __name__ == '__main__':
    patch()
