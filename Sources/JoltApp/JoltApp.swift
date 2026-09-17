import AppKit
import SwiftUI

@main
struct JoltApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  @StateObject private var model = AppModel.shared
  @StateObject private var preferences = AppPreferences.shared

  var body: some Scene {
    Window("Jolt", id: "search") {
      // Keep dynamic content's measured minimum from resizing the native window. The
      // container takes the available space and reports only our fixed minimum to the scene.
      GeometryReader { _ in
        SearchView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
        .frame(
          minWidth: SearchWindowMetrics.minimumSize.width,
          minHeight: SearchWindowMetrics.minimumSize.height
        )
        .environmentObject(model)
        .environmentObject(preferences)
        .environmentObject(model.images)
        .background(
          WindowAccessor { window in
            window.identifier = NSUserInterfaceItemIdentifier("search")
            model.register(searchWindow: window)
          }
        )
        .onExitCommand { model.handleSearchEscape() }
    }
    .defaultSize(
      width: SearchWindowMetrics.defaultSize.width,
      height: SearchWindowMetrics.defaultSize.height
    )
    .windowResizability(.contentMinSize)
    .windowStyle(.hiddenTitleBar)
    .searchWindowLaunchBehavior()

    MenuBarExtra("Jolt", image: "MenuBarIcon") {
      Button("Search Issues") { model.showSearchWindow() }
      Button("Reset Size and Center") { model.centerSearchWindow() }
      SettingsMenuButton()
        .environmentObject(model)
      Divider()
      Button("Quit Jolt") { NSApp.terminate(nil) }
    }

    Settings {
      SettingsView()
        .environmentObject(model)
        .environmentObject(preferences)
    }
  }
}

private struct SettingsMenuButton: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    Button("Settings…") {
      model.prepareToOpenSettings()
      openSettings()
    }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    let preferences = AppPreferences.shared
    preferences.applyDockPolicy()
    preferences.applyAppearance()
    do {
      try HotKeyService.shared.register(preferences.shortcut) {
        AppModel.shared.toggleSearchWindow()
      }
    } catch {
      AppModel.shared.shortcutErrorMessage = error.userFacingMessage
    }
    AppModel.shared.start()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    AppModel.shared.applicationDidBecomeActive()
  }

  func applicationDidResignActive(_ notification: Notification) {
    AppModel.shared.applicationDidResignActive()
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    AppModel.shared.showSearchWindow()
    return true
  }
}

struct WindowAccessor: NSViewRepresentable {
  let onResolve: (NSWindow) -> Void

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async {
      if let window = view.window { onResolve(window) }
    }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    DispatchQueue.main.async {
      if let window = nsView.window { onResolve(window) }
    }
  }
}

private extension Scene {
  func searchWindowLaunchBehavior() -> some Scene {
    // SceneBuilder has no buildEither. Use its availability erasure for both OS branches.
    let scene = {
      if #available(macOS 15.0, *) {
        return SceneBuilder.buildLimitedAvailability(
          self
            .restorationBehavior(.disabled)
            .defaultWindowPlacement { _, context in
              let bounds = context.defaultDisplay.visibleRect
              let size = SearchWindowMetrics.defaultSize
              return WindowPlacement(
                CGPoint(
                  x: bounds.midX - size.width / 2,
                  y: bounds.minY + max(0, bounds.height - size.height) * 0.4
                ),
                size: size
              )
            }
        )
      }
      return SceneBuilder.buildLimitedAvailability(self)
    }()
    return SceneBuilder.buildOptional(scene)
  }
}
