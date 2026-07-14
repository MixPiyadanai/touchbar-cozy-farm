import AppKit
import Darwin

// ponytail: persistent Control Strip items require private API; fall back to
// BetterTouchTool if Apple removes these symbols in a future macOS release.
enum ControlStrip {
    private typealias PresenceFunction = @convention(c) (NSString, Bool) -> Void
    private typealias CloseBoxFunction = @convention(c) (Bool) -> Void
    private static let handle = dlopen(
        "/System/Library/PrivateFrameworks/DFRFoundation.framework/Versions/A/DFRFoundation",
        RTLD_NOW
    )

    static var isSupported: Bool {
        handle != nil && (NSTouchBarItem.self as AnyObject).responds(
            to: NSSelectorFromString("addSystemTrayItem:")
        )
    }

    static func add(_ item: NSTouchBarItem) {
        let selector = NSSelectorFromString("addSystemTrayItem:")
        guard isSupported else { return }
        _ = (NSTouchBarItem.self as AnyObject).perform(selector, with: item)
        setPresent(item.identifier, true)
    }

    static func remove(_ item: NSTouchBarItem) {
        setPresent(item.identifier, false)
        let selector = NSSelectorFromString("removeSystemTrayItem:")
        guard (NSTouchBarItem.self as AnyObject).responds(to: selector) else { return }
        _ = (NSTouchBarItem.self as AnyObject).perform(selector, with: item)
    }

    static func present(_ touchBar: NSTouchBar, from identifier: NSTouchBarItem.Identifier) {
        symbol("DFRSystemModalShowsCloseBoxWhenFrontMost", as: CloseBoxFunction.self)?(false)
        for name in [
            "presentSystemModalTouchBar:systemTrayItemIdentifier:",
            "presentSystemModalFunctionBar:systemTrayItemIdentifier:"
        ] {
            let selector = NSSelectorFromString(name)
            guard (NSTouchBar.self as AnyObject).responds(to: selector) else { continue }
            _ = (NSTouchBar.self as AnyObject).perform(selector, with: touchBar, with: identifier.rawValue)
            return
        }
    }

    static func dismiss(_ touchBar: NSTouchBar) {
        for name in ["dismissSystemModalTouchBar:", "dismissSystemModalFunctionBar:"] {
            let selector = NSSelectorFromString(name)
            guard (NSTouchBar.self as AnyObject).responds(to: selector) else { continue }
            _ = (NSTouchBar.self as AnyObject).perform(selector, with: touchBar)
            return
        }
    }

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: type)
    }

    private static func setPresent(_ identifier: NSTouchBarItem.Identifier, _ present: Bool) {
        guard let handle, let symbol = dlsym(handle, "DFRElementSetControlStripPresenceForIdentifier") else {
            return
        }
        let function = unsafeBitCast(symbol, to: PresenceFunction.self)
        function(identifier.rawValue as NSString, present)
    }
}
