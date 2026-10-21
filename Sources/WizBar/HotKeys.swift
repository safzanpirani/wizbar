import Carbon.HIToolbox
import Foundation

/// System-wide shortcuts through Carbon's RegisterEventHotKey, which needs no
/// Accessibility permission.
@MainActor
final class HotKeys {
    struct Binding {
        let keyCode: Int
        let action: @MainActor () -> Void
    }
    static let modifiers = UInt32(controlKey | optionKey | cmdKey)
    static let modifierLabel = "⌃⌥⌘"

    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: @MainActor () -> Void] = [:]
    private var handler: EventHandlerRef?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            let hotKeys = Unmanaged<HotKeys>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { hotKeys.actions[id.id]?() }
            return noErr
        }, 1, &spec, context, &handler)
    }

    func register(_ bindings: [Binding]) {
        unregisterAll()
        for (index, binding) in bindings.enumerated() {
            let id = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(binding.keyCode), Self.modifiers,
                                             EventHotKeyID(signature: OSType(0x575A_4252), id: id), // "WZBR"
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
                actions[id] = binding.action
            }
        }
    }

    func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        actions.removeAll()
    }
}
