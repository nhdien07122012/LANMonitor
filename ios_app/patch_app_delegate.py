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
  private var widgetChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    let rootVC = window?.rootViewController ?? UIApplication.shared.windows.first?.rootViewController
    if let controller = rootVC as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "com.lanmonitor/widget", binaryMessenger: controller.binaryMessenger)
      self.widgetChannel = channel
      channel.setMethodCallHandler { (call: FlutterMethodCall, resultHandler: @escaping FlutterResult) in
        let suiteNames = ["group.com.lanmonitor.lanMonitor", "group.com.lanmonitor.app"]
        if call.method == "updateWidgetHosts", let args = call.arguments as? [String: Any] {
          for suite in suiteNames {
            if let defs = UserDefaults(suiteName: suite) {
              for (k, v) in args {
                defs.set(v, forKey: k)
              }
              defs.synchronize()
            }
            if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suite) {
              let fileURL = url.appendingPathComponent("widget_hosts.json")
              if let data = try? JSONSerialization.data(withJSONObject: args) {
                try? data.write(to: fileURL)
              }
            }
          }
          for (k, v) in args {
            UserDefaults.standard.set(v, forKey: k)
          }
          UserDefaults.standard.synchronize()
          if #available(iOS 14.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
          }
          resultHandler(true)
        } else if call.method == "updateWidget", let args = call.arguments as? [String: Any] {
          for suite in suiteNames {
            if let defs = UserDefaults(suiteName: suite) {
              for (k, v) in args {
                defs.set(v, forKey: k)
              }
              defs.synchronize()
            }
            if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suite) {
              let fileURL = url.appendingPathComponent("widget_data.json")
              if let data = try? JSONSerialization.data(withJSONObject: args) {
                try? data.write(to: fileURL)
              }
            }
          }
          for (k, v) in args {
            UserDefaults.standard.set(v, forKey: k)
          }
          UserDefaults.standard.synchronize()
                try? data.write(to: fileURL)
              }
            }
          }
          if #available(iOS 14.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
          }
          resultHandler(true)
        } else if call.method == "getPendingOpenUrl" {
          var pending: String? = nil
          for suite in suiteNames {
            if let defs = UserDefaults(suiteName: suite), let u = defs.string(forKey: "pending_open_url"), !u.isEmpty {
              pending = u
              defs.removeObject(forKey: "pending_open_url")
              defs.synchronize()
              break
            }
          }
          resultHandler(pending)
        } else {
          resultHandler(FlutterMethodNotImplemented)
        }
      }
    }

    return result
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    let urlString = url.absoluteString
    if urlString.hasPrefix("lanmonitor://") {
      let suiteNames = ["group.com.lanmonitor.lanMonitor", "group.com.lanmonitor.app"]
      for suite in suiteNames {
        if let defs = UserDefaults(suiteName: suite) {
          defs.set(urlString, forKey: "pending_open_url")
          defs.synchronize()
        }
      }
      widgetChannel?.invokeMethod("openHostUrl", arguments: urlString)
      return true
    }
    return super.application(app, open: url, options: options)
  }
}
"""
    with open(app_delegate_path, 'w', encoding='utf-8') as f:
        f.write(swift_code)
    print("Successfully patched AppDelegate.swift with AppGroup Widget synchronization and DeepLink handler.")

if __name__ == '__main__':
    patch()
