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

  private func setupChannelIfNeeded(messenger: FlutterBinaryMessenger) {
    guard self.widgetChannel == nil else { return }
    let channel = FlutterMethodChannel(name: "com.lanmonitor/widget", binaryMessenger: messenger)
    self.widgetChannel = channel
    channel.setMethodCallHandler { (call: FlutterMethodCall, resultHandler: @escaping FlutterResult) in
      var suiteNames = [
        "group.com.lanmonitor.lanMonitor",
        "group.com.lanmonitor.app",
        "group.com.lanmonitor"
      ]
      if let bundleId = Bundle.main.bundleIdentifier {
        suiteNames.append("group.\(bundleId)")
      }
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

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    if let controller = window?.rootViewController as? FlutterViewController {
      setupChannelIfNeeded(messenger: controller.binaryMessenger)
    } else {
      for scene in UIApplication.shared.connectedScenes {
        if let ws = scene as? UIWindowScene {
          for w in ws.windows {
            if let controller = w.rootViewController as? FlutterViewController {
              setupChannelIfNeeded(messenger: controller.binaryMessenger)
              break
            }
          }
        }
      }
    }
    return result
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    if self.widgetChannel == nil, let controller = window?.rootViewController as? FlutterViewController {
      setupChannelIfNeeded(messenger: controller.binaryMessenger)
    }
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    let urlString = url.absoluteString
    if urlString.hasPrefix("lanmonitor://") {
      var suiteNames = ["group.com.lanmonitor.lanMonitor", "group.com.lanmonitor.app", "group.com.lanmonitor"]
      if let bundleId = Bundle.main.bundleIdentifier {
        suiteNames.append("group.\(bundleId)")
      }
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
