/// Fake implementations of AXSwift functionality.
///
/// This gets used both in the public testing harness and in Swindler's own tests.

// TODO: Rename TestXyz classes to FakeXyz.

import AXSwift
import Cocoa

/// A dictionary of AX attributes.
///
/// Models redundancies in the data model (frame, position, and size).
class Attributes {
    private var values: [Attribute: Any] = [:]

    subscript(attr: Attribute) -> Any? {
        get {
            switch attr {
            case .position:
                guard let frame = values[.frame] as? CGRect else { return nil }
                return Optional(frame.origin)
            case .size:
                guard let frame = values[.frame] as? CGRect else { return nil }
                return Optional(frame.size)
            default:
                return values[attr]
            }
        }
        set {
            if attr == .position {
                let frame = values[.frame] as? CGRect ?? CGRect.zero
                values[.frame] = CGRect(origin: newValue as! CGPoint, size: frame.size)
                return
            }
            if attr == .size {
                let frame = values[.frame] as? CGRect ?? CGRect.zero
                values[.frame] = CGRect(origin: frame.origin, size: newValue as! CGSize)
                return
            }
            values[attr] = newValue
        }
    }

    func removeValue(forKey: Attribute) {
        values.removeValue(forKey: forKey)
    }
}

extension Attributes: CustomDebugStringConvertible {
    var debugDescription: String {
        "\(values)"
    }
}

class SyncAttributes {
    private var attrs: Attributes = .init()
    private var lock: NSRecursiveLock = .init()

    func with<R>(_ f: (Attributes) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return f(attrs)
    }

    subscript(attr: Attribute) -> Any? {
        get { with { $0[attr] } }
        set { with { $0[attr] = newValue } }
    }

    func removeValue(forKey attr: Attribute) {
        with { $0.removeValue(forKey: attr) }
    }
}

extension SyncAttributes: CustomDebugStringConvertible {
    var debugDescription: String {
        lock.lock()
        defer { lock.unlock() }
        return "\(attrs)"
    }
}

class TestUIElement: UIElementType, Hashable {
    static var globalMessagingTimeout: Float = 0

    static var elementCount: Int = 0

    var id: Int
    var processID: pid_t = 0
    var attrs: SyncAttributes = .init()

    var throwInvalid: Bool = false

    init() {
        TestUIElement.elementCount += 1
        id = TestUIElement.elementCount
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    func pid() throws -> pid_t { processID }
    func attribute<T>(_ attr: Attribute) throws -> T? {
        if throwInvalid { throw AXError.invalidUIElement }
        if let value = attrs[attr] {
            return (value as! T)
        }
        return nil
    }

    func arrayAttribute<T>(_ attr: Attribute) throws -> [T]? {
        if throwInvalid { throw AXError.invalidUIElement }
        guard let value = attrs[attr] else {
            return nil
        }
        return (value as! [T])
    }

    func getMultipleAttributes(_ attributes: [AXSwift.Attribute]) throws -> [Attribute: Any] {
        if throwInvalid { throw AXError.invalidUIElement }
        return attrs.with { attrs in
            var result: [Attribute: Any] = [:]
            for attr in attributes {
                result[attr] = attrs[attr]
            }
            return result
        }
    }

    func setAttribute(_ attr: Attribute, value: Any) throws {
        if throwInvalid { throw AXError.invalidUIElement }
        attrs[attr] = value
    }

    func addObserver(_: FakeObserver) {}

    var inspect: String {
        let role = attrs[.role] ?? "UIElement"
        return "\(role) (id \(id))"
    }
}

func == (lhs: TestUIElement, rhs: TestUIElement) -> Bool {
    lhs.id == rhs.id
}

class TestApplicationElement: TestUIElement, ApplicationElementType {
    typealias UIElementType = TestUIElement
    var toElement: TestUIElement { self }

    init(processID: pid_t? = nil, id: Int? = nil) {
        super.init()
        if let id {
            self.id = id
        }
        self.processID = processID ?? Int32(self.id)
        attrs.with { attrs in
            attrs[.role] = AXSwift.Role.application.rawValue
            attrs[.windows] = [TestUIElement]()
            attrs[.frontmost] = false
            attrs[.hidden] = false
        }
    }

    override func setAttribute(_ attribute: Attribute, value newValue: Any) throws {
        if attribute == .mainWindow {
            // Synchronize .mainWindow with .main on the window.
            attrs.with { attrs in
                let newWindowElement = newValue as! TestWindowElement
                let oldWindowElement = attrs[.mainWindow] as! TestWindowElement? ?? newWindowElement
                newWindowElement.attrs.with { newWindowAttrs in
                    // NOTE: This works if old and new are the same because we're using NSRecursiveLock.
                    oldWindowElement.attrs.with { oldWindowAttrs in
                        oldWindowAttrs[.main] = false
                        newWindowAttrs[.main] = true

                        attrs[.mainWindow] = newValue

                        // Propagate .mainWindow changes to .focusedWindow also.
                        // This is what happens 99% of the time, but it is still possible to set
                        // .focusedWindow only.
                        attrs[.focusedWindow] = newValue
                    }
                }
            }
            return
        }

        try super.setAttribute(attribute, value: newValue)
    }

    var windows: [TestUIElement] {
        get { attrs[.windows]! as! [TestUIElement] }
        set { attrs[.windows] = newValue }
    }
}

final class EmittingTestApplicationElement: TestApplicationElement {
    init() {
        observers = []
        super.init(processID: EmittingTestApplicationElement.nextPID)
        EmittingTestApplicationElement.nextPID += 1
    }

    static var nextPID: pid_t = 1

    override func setAttribute(_ attribute: Attribute, value: Any) throws {
        try super.setAttribute(attribute, value: value)
        let notifications = { () -> [AXNotification] in
            switch attribute {
            case .mainWindow:
                [.mainWindowChanged, .focusedWindowChanged]
            case .focusedWindow:
                [.focusedWindowChanged]
            case .hidden:
                (value as? Bool == true) ? [.applicationHidden] : [.applicationShown]
            default:
                []
            }
        }()
        for notification in notifications {
            for observer in observers {
                observer.unbox?.emit(notification, forElement: self)
            }
        }
    }

    func addWindow(_ window: EmittingTestWindowElement) {
        // TODO update attrs[.window]
        for observer in observers {
            observer.unbox?.emit(.windowCreated, forElement: window)
        }
    }

    private var observers: [WeakBox<FakeObserver>]

    override func addObserver(_ observer: FakeObserver) {
        observers.append(WeakBox(observer))
    }

    // Useful hack to store companion objects (like FakeApplication).
    weak var companion: AnyObject?
}

class TestWindowElement: TestUIElement {
    var app: TestApplicationElement
    init(forApp app: TestApplicationElement) {
        self.app = app
        super.init()
        processID = app.processID
        attrs.with { attrs in
            attrs[.role] = AXSwift.Role.window.rawValue
            attrs[.frame] = CGRect(x: 0, y: 0, width: 100, height: 100)
            attrs[.title] = "Window \(id)"
            attrs[.minimized] = false
            attrs[.main] = true
            attrs[.focused] = true
            attrs[.fullScreen] = false
        }
    }

    override func setAttribute(_ attribute: Attribute, value: Any) throws {
        // Synchronize .main with .mainWindow on the application.
        if attribute == .main {
            // Setting .main to false does nothing.
            guard value as! Bool == true else { return }

            // Let TestApplicationElement.setAttribute do the heavy lifting, and return.
            try app.setAttribute(.mainWindow, value: self)
            return
        }

        try super.setAttribute(attribute, value: value)
    }
}

extension TestWindowElement: CustomDebugStringConvertible {
    var debugDescription: String {
        let title = self.attrs[.title].map { "\"\($0)\"" }
        return "TestWindowElement(\(title ?? "<none>"))"
    }
}

class EmittingTestWindowElement: TestWindowElement {
    override init(forApp app: TestApplicationElement) {
        observers = []
        super.init(forApp: app)
    }

    override func setAttribute(_ attribute: Attribute, value: Any) throws {
        try super.setAttribute(attribute, value: value)
        let notifications = { () -> [AXNotification] in
            switch attribute {
            case .position: [.moved]
            case .size: [.resized]
            case .frame: [.moved, .resized]
            case .fullScreen: [.resized]
            case .title: [.titleChanged]
            case .minimized:
                (value as? Bool == true) ? [.windowDeminiaturized] : [.windowMiniaturized]
            default:
                []
            }
        }()
        for notification in notifications {
            for observer in observers {
                observer.unbox?.emit(notification, forElement: self)
            }
        }
    }

    private var observers: [WeakBox<FakeObserver>]

    override func addObserver(_ observer: FakeObserver) {
        observers.append(WeakBox(observer))
    }

    func destroy() {
        for observer in observers {
            observer.unbox?.emit(.uiElementDestroyed, forElement: self)
        }
    }

    // Useful hack to store companion objects (like FakeWindow).
    weak var companion: AnyObject?
}

class FakeObserver: ObserverType {
    typealias Context = FakeObserver
    typealias UIElement = TestUIElement
    var callback: Callback!
    var lock: NSLock = .init()
    var watchedElements: [TestUIElement: [AXNotification]] = [:]

    required init(processID: pid_t, callback: @escaping Callback) throws {
        self.callback = callback
    }

    func addNotification(_ notification: AXNotification, forElement element: TestUIElement) throws {
        lock.lock()
        defer { lock.unlock() }

        if watchedElements[element] == nil {
            watchedElements[element] = []
            element.addObserver(self)
        }
        watchedElements[element]!.append(notification)
    }

    func removeNotification(_ notification: AXNotification,
                            forElement element: TestUIElement) throws {
        lock.lock()
        defer { lock.unlock() }

        if let watchedNotifications = watchedElements[element] {
            watchedElements[element] = watchedNotifications.filter { $0 != notification }
        }
    }

    func emit(_ notification: AXNotification, forElement element: TestUIElement) {
        // These notifications usually happen on a window element, but are observed on the
        // application element.
        switch notification {
        case .windowCreated, .mainWindowChanged, .focusedWindowChanged:
            if let window = element as? TestWindowElement {
                doEmit(notification, watchedElement: window.app, passedElement: element)
            } else {
                doEmit(notification, watchedElement: element, passedElement: element)
            }
        default:
            doEmit(notification, watchedElement: element, passedElement: element)
        }
    }

    func doEmit(_ notification: AXNotification,
                watchedElement: TestUIElement,
                passedElement: TestUIElement) {
        lock.lock()
        defer { lock.unlock() }
        let watched = watchedElements[watchedElement] ?? []
        if watched.contains(notification) {
            performOnMainThread {
                callback(self, passedElement, notification)
            }
        }
    }
}

// This component is not actually part of AXSwift.
class FakeApplicationObserver: ApplicationObserverType {
    private var frontmost_: pid_t?
    var frontmostApplicationPID: pid_t? { frontmost_ }

    private var frontmostHandlers: [() -> Void] = []
    func onFrontmostApplicationChanged(_ handler: @escaping () -> Void) {
        frontmostHandlers.append(handler)
    }

    private var launchHandlers: [(pid_t) -> Void] = []
    func onApplicationLaunched(_ handler: @escaping (pid_t) -> Void) {
        launchHandlers.append(handler)
    }

    private var terminateHandlers: [(pid_t) -> Void] = []
    func onApplicationTerminated(_ handler: @escaping (pid_t) -> Void) {
        terminateHandlers.append(handler)
    }

    func onSpaceChanged(_ handler: @escaping (Int) -> Void) {
        // TODO
    }

    func makeApplicationFrontmost(_ pid: pid_t) throws {
        // This is called by property delegates on worker threads.
        performOnMainThread {
            setFrontmost(pid)
        }
    }

    typealias ApplicationElement = EmittingTestApplicationElement
    var allApps: [ApplicationElement] = []
    func allApplications() -> [EmittingTestApplicationElement] {
        allApps
    }

    func appElement(forProcessID processID: pid_t) -> EmittingTestApplicationElement? {
        allApps.first(where: { $0.processID == processID })
    }
}

extension FakeApplicationObserver {
    func setFrontmost(_ pid: pid_t?) {
        frontmost_ = pid
        frontmostHandlers.forEach { $0() }
    }

    func launch(_ pid: pid_t) {
        launchHandlers.forEach { $0(pid) }
    }

    func terminate(_ pid: pid_t) {
        terminateHandlers.forEach { $0(pid) }
    }
}

private final class WeakBox<A: AnyObject> {
    weak var unbox: A?
    init(_ value: A) {
        unbox = value
    }
}

/// Performs the given action on the main thread, synchronously, regardless of the current thread.
private func performOnMainThread(_ action: () -> Void) {
    if Thread.current.isMainThread {
        action()
    } else {
        DispatchQueue.main.sync {
            action()
        }
    }
}
