import AppKit
import Carbon.HIToolbox
import Foundation
import JoltCore
import ServiceManagement
import SwiftUI

enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
  case automatic
  case light
  case dark

  var id: String { rawValue }

  var title: String { rawValue.capitalized }

  var systemImage: String {
    switch self {
    case .automatic: return "circle.lefthalf.filled"
    case .light: return "sun.max.fill"
    case .dark: return "moon.stars.fill"
    }
  }

  var nsAppearance: NSAppearance? {
    switch self {
    case .automatic: return nil
    case .light: return NSAppearance(named: .aqua)
    case .dark: return NSAppearance(named: .darkAqua)
    }
  }
}

enum BackgroundMode: String, Codable, CaseIterable, Identifiable {
  case opaque
  case tinted
  case clear

  var id: String { rawValue }

  var title: String { rawValue.capitalized }

  static func restoring(_ storedValue: String) -> BackgroundMode {
    switch storedValue {
    case opaque.rawValue, "solid": return .opaque
    case tinted.rawValue, "hud": return .tinted
    case clear.rawValue, "liquidGlassRegular", "liquidGlassClear": return .clear
    default: return .tinted
    }
  }
}

enum ScopeBarLayoutMode: String, Codable, CaseIterable, Identifiable {
  case rankedByFrequency
  case groupedByKind
  case off

  var id: String { rawValue }

  var title: String {
    switch self {
    case .rankedByFrequency: return "Ranked by Frequency"
    case .groupedByKind: return "Grouped by Project & Type"
    case .off: return "Off"
    }
  }
}

enum SearchResultLimit: Int, Codable, CaseIterable, Identifiable {
  case ten = 10
  case twentyFive = 25
  case fifty = 50
  case oneHundred = 100

  var id: Int { rawValue }

  var title: String { String(rawValue) }
}

struct KeyboardShortcutSpec: Codable, Equatable {
  var keyCode: UInt32
  var modifiers: UInt32
  var key: String

  static let defaultShortcut = KeyboardShortcutSpec(
    keyCode: UInt32(kVK_ANSI_J),
    modifiers: UInt32(optionKey),
    key: "J"
  )

  var displayName: String {
    var output = ""
    if modifiers & UInt32(controlKey) != 0 { output += "⌃" }
    if modifiers & UInt32(optionKey) != 0 { output += "⌥" }
    if modifiers & UInt32(shiftKey) != 0 { output += "⇧" }
    if modifiers & UInt32(cmdKey) != 0 { output += "⌘" }
    return output + key.uppercased()
  }

  var isAllowed: Bool {
    let primaryModifiers = UInt32(cmdKey) | UInt32(optionKey) | UInt32(controlKey)
    return modifiers & primaryModifiers != 0
      || (modifiers == 0 && Self.functionKeyName(for: keyCode) != nil)
  }

  static func functionKeyName(for keyCode: UInt32) -> String? {
    switch Int(keyCode) {
    case kVK_F1: return "F1"
    case kVK_F2: return "F2"
    case kVK_F3: return "F3"
    case kVK_F4: return "F4"
    case kVK_F5: return "F5"
    case kVK_F6: return "F6"
    case kVK_F7: return "F7"
    case kVK_F8: return "F8"
    case kVK_F9: return "F9"
    case kVK_F10: return "F10"
    case kVK_F11: return "F11"
    case kVK_F12: return "F12"
    default: return nil
    }
  }
}

@MainActor
final class AppPreferences: ObservableObject {
  static let shared = AppPreferences()

  private enum Key {
    static let appearance = "appearance"
    static let background = "background"
    static let showDockIcon = "showDockIcon"
    static let launchAtLogin = "launchAtLogin"
    static let shortcut = "shortcut"
    static let selectedSite = "selectedSite"
    static let scopeBarLayout = "scopeBarLayout"
    static let searchResultLimit = "searchResultLimit"
  }

  @Published var appearance: AppearanceMode {
    didSet {
      defaults.set(appearance.rawValue, forKey: Key.appearance)
      applyAppearance()
    }
  }
  @Published var background: BackgroundMode {
    didSet { defaults.set(background.rawValue, forKey: Key.background) }
  }
  @Published var scopeBarLayout: ScopeBarLayoutMode {
    didSet { defaults.set(scopeBarLayout.rawValue, forKey: Key.scopeBarLayout) }
  }
  @Published var searchResultLimit: SearchResultLimit {
    didSet { defaults.set(searchResultLimit.rawValue, forKey: Key.searchResultLimit) }
  }
  @Published var showDockIcon: Bool {
    didSet {
      defaults.set(showDockIcon, forKey: Key.showDockIcon)
      NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
    }
  }
  @Published var launchAtLogin: Bool {
    didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) }
  }
  @Published var shortcut: KeyboardShortcutSpec {
    didSet {
      if let data = try? JSONEncoder().encode(shortcut) {
        defaults.set(data, forKey: Key.shortcut)
      }
    }
  }

  private let defaults: UserDefaults

  private init(defaults: UserDefaults = .standard) {
    let storedBackground = defaults.string(forKey: Key.background) ?? ""
    let restoredBackground = BackgroundMode.restoring(storedBackground)

    self.defaults = defaults
    self.appearance =
      AppearanceMode(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .automatic
    self.background = restoredBackground
    self.scopeBarLayout =
      ScopeBarLayoutMode(rawValue: defaults.string(forKey: Key.scopeBarLayout) ?? "")
      ?? .rankedByFrequency
    self.searchResultLimit =
      SearchResultLimit(rawValue: defaults.object(forKey: Key.searchResultLimit) as? Int ?? 25)
      ?? .twentyFive
    self.showDockIcon = defaults.object(forKey: Key.showDockIcon) as? Bool ?? true
    self.launchAtLogin = defaults.object(forKey: Key.launchAtLogin) as? Bool ?? false
    if let data = defaults.data(forKey: Key.shortcut),
      let saved = try? JSONDecoder().decode(KeyboardShortcutSpec.self, from: data),
      saved.isAllowed
    {
      self.shortcut = saved
    } else {
      self.shortcut = .defaultShortcut
    }

    if storedBackground != restoredBackground.rawValue {
      defaults.set(restoredBackground.rawValue, forKey: Key.background)
    }
  }

  var selectedSite: JiraSite? {
    get {
      guard let data = defaults.data(forKey: Key.selectedSite) else { return nil }
      return try? JSONDecoder().decode(JiraSite.self, from: data)
    }
    set {
      if let newValue, let data = try? JSONEncoder().encode(newValue) {
        defaults.set(data, forKey: Key.selectedSite)
      } else {
        defaults.removeObject(forKey: Key.selectedSite)
      }
    }
  }

  func applyDockPolicy() {
    NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
  }

  func applyAppearance() {
    NSApp.appearance = appearance.nsAppearance
    for window in NSApp.windows {
      window.contentView?.needsDisplay = true
      window.displayIfNeeded()
    }
  }

  func setLaunchAtLogin(_ enabled: Bool) throws {
    if enabled {
      try SMAppService.mainApp.register()
    } else {
      try SMAppService.mainApp.unregister()
    }
    launchAtLogin = enabled
  }
}
