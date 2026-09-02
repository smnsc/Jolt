import Carbon.HIToolbox
import Foundation

protocol HotKeyRegistering: AnyObject {
  func register(_ shortcut: KeyboardShortcutSpec, handler: @escaping () -> Void) throws
  func unregister()
}

private func hotKeyEventHandler(
  _ nextHandler: EventHandlerCallRef?,
  _ event: EventRef?,
  _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
  guard let userData else { return noErr }
  let service = Unmanaged<HotKeyService>.fromOpaque(userData).takeUnretainedValue()
  DispatchQueue.main.async { service.performHandler() }
  return noErr
}

final class HotKeyService: HotKeyRegistering {
  static let shared = HotKeyService()

  private var hotKeyRef: EventHotKeyRef?
  private var eventHandlerRef: EventHandlerRef?
  private var handler: (() -> Void)?

  private init() {}

  func register(_ shortcut: KeyboardShortcutSpec, handler: @escaping () -> Void) throws {
    unregister()
    self.handler = handler

    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let installStatus = InstallEventHandler(
      GetApplicationEventTarget(),
      hotKeyEventHandler,
      1,
      &eventType,
      Unmanaged.passUnretained(self).toOpaque(),
      &eventHandlerRef
    )
    guard installStatus == noErr else {
      throw AppError.shortcutUnavailable(shortcut.displayName)
    }

    let signature = OSType(0x4A49_5241)  // "JIRA"
    let identifier = EventHotKeyID(signature: signature, id: 1)
    let status = RegisterEventHotKey(
      shortcut.keyCode,
      shortcut.modifiers,
      identifier,
      GetApplicationEventTarget(),
      0,
      &hotKeyRef
    )
    guard status == noErr else {
      unregister()
      throw AppError.shortcutUnavailable(shortcut.displayName)
    }
  }

  func unregister() {
    if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
    if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    hotKeyRef = nil
    eventHandlerRef = nil
  }

  fileprivate func performHandler() {
    handler?()
  }

  deinit {
    unregister()
  }
}
