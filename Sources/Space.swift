import AppKit
import Cocoa
import CoreGraphics

private let SLSScreenIDKey = "Display Identifier"
private let SLSSpaceIDKey = "ManagedSpaceID"
private let SLSSpacesKey = "Spaces"
private let displaySpacesInfo = SLSCopyManagedDisplaySpaces(SLSMainConnectionID()).takeRetainedValue() as NSArray

public class Space: NSObject {
    private static let connectionID = SLSMainConnectionID()

    public static func all() -> [Space] {
        var spaces: [Space] = []

        let displaySpacesInfo = SLSCopyManagedDisplaySpaces(connectionID).takeRetainedValue() as NSArray

        for displaySpacesInfo in displaySpacesInfo {
            guard let spacesInfo = displaySpacesInfo as? [String: AnyObject] else {
                continue
            }

            guard let identifiers = spacesInfo[SLSSpacesKey] as? [[String: AnyObject]] else {
                continue
            }

            for item in identifiers {
                guard let identifier = item[SLSSpaceIDKey] as? uint64 else {
                    continue
                }

                spaces.append(Space(identifier: identifier))
            }
        }

        return spaces
    }

    public static func at(_ index: Int) -> Space? {
        all()[index]
    }

    public static func getById(_ id: UInt64) -> Space? {
        all().filter { $0.identifier == id }.first
    }

    public static func getByWindowId(_ windowId: CGWindowID) -> Space? {
        let identifiers = SLSCopySpacesForWindows(connectionID,
                                                  7,
                                                  [windowId] as CFArray).takeRetainedValue() as NSArray

        for space in all() {
            if identifiers.contains(space.identifier) {
                return space
            }
        }

        return nil
    }

    public static func get(for window: Window) -> Space? {
        getByWindowId(window.identifier)
    }

    public static func active() -> Space {
        Space(identifier: SLSGetActiveSpace(connectionID))
    }

    public static func current(for screen: NSScreen) -> Space? {
        let identifier = SLSManagedDisplayGetCurrentSpace(connectionID, screen.identifier as CFString)

        return Space(identifier: identifier)
    }

    init(identifier: uint64) {
        self.identifier = identifier
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let space = object as? Self else {
            return false
        }

        return identifier == space.identifier
    }

    public var identifier: uint64

    public var isNormal: Bool {
        SLSSpaceGetType(Self.connectionID, identifier) == 0
    }

    public var isFullscreen: Bool {
        SLSSpaceGetType(Self.connectionID, identifier) == 4
    }

    public func screens() -> [NSScreen] {
        if !NSScreen.screensHaveSeparateSpaces {
            return NSScreen.screens
        }

        let displaySpacesInfo = SLSCopyManagedDisplaySpaces(Self.connectionID).takeRetainedValue() as NSArray

        var screen: NSScreen?

        for displaySpacesInfo in displaySpacesInfo {
            guard let spacesInfo = displaySpacesInfo as? [String: AnyObject] else {
                continue
            }

            guard let screenIdentifier = spacesInfo[SLSScreenIDKey] as? String else {
                continue
            }

            guard let identifiers = spacesInfo[SLSSpacesKey] as? [[String: AnyObject]] else {
                continue
            }

            for item in identifiers {
                guard let identifier = item[SLSSpaceIDKey] as? uint64 else {
                    continue
                }

                if identifier == self.identifier {
                    screen = NSScreen.screen(for: screenIdentifier)
                }
            }
        }

        if screen != nil {
            return [screen!]
        } else {
            return []
        }
    }

    public func contains(window: Window) -> Bool {
        let spaceIDs = SLSCopySpacesForWindows(Self.connectionID,
                                               7,
                                               [window.identifier] as CFArray).takeRetainedValue() as NSArray
        return spaceIDs.contains(identifier)
    }

    public func getWindows(on state: State) -> [Window] {
        state.knownWindows.filter { $0.space?.identifier == self.identifier }
    }

    public func addWindows(_ windows: [Window]) {
        SLSAddWindowsToSpaces(Self.connectionID, windows.map(\.identifier) as CFArray, [identifier] as CFArray)
    }

    public func removeWindows(_ windows: [Window]) {
        SLSRemoveWindowsFromSpaces(Self.connectionID, windows.map(\.identifier) as CFArray, [identifier] as CFArray)
    }

    public func moveWindows(_ windows: [Window]) {
        SLSMoveWindowsToManagedSpace(Self.connectionID, windows.map(\.identifier) as CFArray, identifier)
    }

    public func moveWindowsById(_ windowIds: [CGWindowID]) {
        SLSMoveWindowsToManagedSpace(Self.connectionID, windowIds as CFArray, identifier)
    }
}

class OSXSpaceObserver: NSObject, NSWindowDelegate {
    private var trackers: [Int: SpaceTracker] = [:]
    private weak var ssd: SystemScreenDelegate?
    private var sst: SystemSpaceTracker
    private weak var notifier: EventNotifier?

    init(_ notifier: EventNotifier?, _ ssd: SystemScreenDelegate, _ sst: SystemSpaceTracker) {
        self.notifier = notifier
        self.ssd = ssd
        self.sst = sst
        super.init()
        for screen in ssd.screens {
            makeWindow(screen)
        }
        sst.onSpaceChanged { [weak self] in
            self?.emitSpaceWillChangeEvent()
        }
        // TODO: Detect screen configuration changes
    }

    /// Create an invisible window for tracking the current space.
    ///
    /// This helps us identify the space when we return to it in the future.
    /// It also helps us detect when a space is closed and merged into another.
    /// Without the window events we wouldn't have a way of noticing when this
    /// happened.
    @discardableResult
    private func makeWindow(_ screen: ScreenDelegate) -> Int {
        let win = sst.makeTracker(screen)
        trackers[win.id] = win
        return win.id
    }

    /// Emits a SpaceWillChangeEvent on the notifier this observer was
    /// constructed with.
    ///
    /// Used during initialization.
    func emitSpaceWillChangeEvent() {
        guard let ssd else { return }
        let visible = sst.visibleIds()
        log.debug("spaceChanged: visible=\(visible)")

        let screens = ssd.screens

        var visibleByScreen = [[Int]](repeating: [], count: screens.count)
        for id in visible {
            // This is O(N^2) in the number of screens, but thankfully that
            // never gets large.
            // TODO: Use directDisplayID?
            guard let screen = trackers[id]?.screen(ssd) else {
                log.info("Window id \(id) not associated with any screen")
                continue
            }
            for (idx, scr) in screens.enumerated() {
                if scr.equalTo(screen) {
                    visibleByScreen[idx].append(id)
                    break
                }
            }
        }

        var visiblePerScreen: [Int] = []
        for (idx, visible) in visibleByScreen.enumerated() {
            if let id = visible.min() {
                visiblePerScreen.append(id)
            } else {
                visiblePerScreen.append(makeWindow(screens[idx]))
            }
        }
        notifier?.notify(SpaceWillChangeEvent(external: true, ids: visiblePerScreen))
    }
}

protocol SystemSpaceTracker {
    /// Installs a handler to be called when the current space changes.
    func onSpaceChanged(_ handler: @escaping () -> Void)

    /// Creates a tracker for the current space on the given screen.
    func makeTracker(_ screen: ScreenDelegate) -> SpaceTracker

    /// Returns the list of IDs of SpaceTrackers whose spaces are currently visible.
    func visibleIds() -> [Int]
}

class OSXSystemSpaceTracker: SystemSpaceTracker {
    func onSpaceChanged(_ handler: @escaping () -> Void) {
        let sharedWorkspace = NSWorkspace.shared
        let notificationCenter = sharedWorkspace.notificationCenter
        notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: sharedWorkspace,
            queue: nil
        ) { _ in handler() }
    }

    func makeTracker(_ screen: ScreenDelegate) -> SpaceTracker {
        OSXSpaceTracker(screen)
    }

    func visibleIds() -> [Int] {
        (NSWindow.windowNumbers(options: []) ?? []) as! [Int]
    }
}

protocol SpaceTracker {
    var id: Int { get }
    func screen(_ ssd: SystemScreenDelegate) -> ScreenDelegate?
}

class OSXSpaceTracker: NSObject, NSWindowDelegate, SpaceTracker {
    let win: NSWindow

    var id: Int { win.windowNumber }

    init(_ screen: ScreenDelegate) {
        // win = NSWindow(contentViewController: NSViewController(nibName: nil, bundle: nil))
        // Size must be non-zero to receive occlusion state events.
        let rect = /* NSRect.zero */ NSRect(x: 0, y: 0, width: 1, height: 1)
        win = NSWindow(
            contentRect: rect,
            styleMask: .borderless /* [.titled, .resizable, .miniaturizable] */,
            backing: .buffered,
            defer: true,
            screen: screen.native
        )
        win.isReleasedWhenClosed = false
        win.ignoresMouseEvents = true
        win.hasShadow = false
        win.animationBehavior = .none
        win.backgroundColor = NSColor.clear
        win.level = .floating
        win.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        if #available(macOS 10.11, *) {
            win.collectionBehavior.update(with: .fullScreenDisallowsTiling)
        }

        super.init()
        win.delegate = self

        win.makeKeyAndOrderFront(nil)
        log.debug("new window windowNumber=\(win.windowNumber)")
    }

    func screen(_ ssd: SystemScreenDelegate) -> ScreenDelegate? {
        guard let screen = win.screen else {
            return nil
        }
        // This class should only be used with a "real" SystemScreenDelegate impl.
        return ssd.delegateForNative(screen: screen)!
    }

    func windowDidChangeScreen(_ notification: Notification) {
        let win = notification.object as! NSWindow
        log.debug("window \(win.windowNumber) changed screen; active=\(win.isOnActiveSpace)")
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        let win = notification.object as! NSWindow
        log.debug("""
            window \(win.windowNumber) occstchanged; \
            occVis=\(win.occlusionState.contains(NSWindow.OcclusionState.visible)), \
            vis=\(win.isVisible), activeSpace=\(win.isOnActiveSpace)
        """)
        let visible = (NSWindow.windowNumbers(options: []) ?? []) as! [Int]
        log.debug("visible=\(visible)")
        // TODO: Use this event to detect space merges.
    }
}

class FakeSystemSpaceTracker: SystemSpaceTracker {
    init() {}

    var spaceChangeHandler: (() -> Void)? = nil
    func onSpaceChanged(_ handler: @escaping () -> Void) {
        spaceChangeHandler = handler
    }

    var trackersMade: [StubSpaceTracker] = []
    func makeTracker(_ screen: ScreenDelegate) -> SpaceTracker {
        let tracker = StubSpaceTracker(screen, id: nextSpaceId)
        trackersMade.append(tracker)
        visible.append(tracker.id)
        return tracker
    }

    var nextSpaceId: Int { trackersMade.count + 1 }

    var visible: [Int] = []
    func visibleIds() -> [Int] { visible }
}

class StubSpaceTracker: SpaceTracker {
    var screen: ScreenDelegate?
    var id: Int
    init(_ screen: ScreenDelegate?, id: Int) {
        self.screen = screen
        self.id = id
    }

    func screen(_ ssd: SystemScreenDelegate) -> ScreenDelegate? { screen }
}
