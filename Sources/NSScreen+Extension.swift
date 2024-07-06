import Cocoa

private let NSScreenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")

extension NSScreen {
    public static func all() -> [NSScreen] {
        screens
    }

    public static func focused() -> NSScreen? {
        main
    }

    public static func screen(for identifier: String) -> NSScreen? {
        screens.first { $0.identifier == identifier }
    }

    public var identifier: String {
        guard let number = deviceDescription[NSScreenNumberKey] as? NSNumber else {
            return ""
        }

        let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value).takeRetainedValue()
        return CFUUIDCreateString(nil, uuid) as String
    }

    public var next: NSScreen? {
        let screens = NSScreen.screens

        if var index = screens.firstIndex(of: self) {
            index += 1

            if index == screens.count {
                index = 0
            }

            return screens[index]
        }

        return nil
    }

    public var previous: NSScreen? {
        let screens = NSScreen.screens

        if var index = screens.firstIndex(of: self) {
            index -= 1

            if index == -1 {
                index = screens.count - 1
            }

            return screens[index]
        }

        return nil
    }

    public func currentSpace() -> Space? {
        Space.current(for: self)
    }

    public func spaces() -> [Space] {
        Space.all().filter { $0.screens().contains(self) }
    }
}
