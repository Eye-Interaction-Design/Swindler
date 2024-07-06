import ApplicationServices
import Cocoa
import CoreGraphics

// MARK: - AXUIElement

@_silgen_name("_AXUIElementGetWindow")
public func _AXUIElementGetWindow(_ element: AXUIElement, _ window: UnsafeMutablePointer<CGWindowID>) -> AXError

// MARK: - SkyLight

let libSkyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

public let SLSMainConnectionID = unsafeBitCast(dlsym(
    libSkyLight,
    "SLSMainConnectionID"
), to: (@convention(c) () -> Int).self)

public let SLSGetActiveSpace = unsafeBitCast(dlsym(
    libSkyLight,
    "SLSGetActiveSpace"
), to: (@convention(c) (Int) -> UInt64).self)

public let SLSAddWindowsToSpaces = unsafeBitCast(dlsym(
    libSkyLight,
    "SLSAddWindowsToSpaces"
), to: (@convention(c) (Int, CFArray, CFArray) -> Void).self)

public let SLSRemoveWindowsFromSpaces = unsafeBitCast(dlsym(
    libSkyLight,
    "SLSRemoveWindowsFromSpaces"
), to: (@convention(c) (Int, CFArray, CFArray) -> Void).self)

public let SLSMoveWindowsToManagedSpace = unsafeBitCast(dlsym(
    libSkyLight,
    "SLSMoveWindowsToManagedSpace"
), to: (@convention(c) (Int, CFArray, UInt64) -> Void).self)

public let SLSManagedDisplayGetCurrentSpace = unsafeBitCast(dlsym(
    libSkyLight,
    "SLSManagedDisplayGetCurrentSpace"
), to: (@convention(c) (Int, CFString) -> UInt64).self)

public let SLSCopyManagedDisplaySpaces = unsafeBitCast(dlsym(
    libSkyLight,
    "SLSCopyManagedDisplaySpaces"
), to: (@convention(c) (Int) -> Unmanaged<CFArray>).self)

public let SLSCopySpacesForWindows = unsafeBitCast(dlsym(
    libSkyLight,
    "SLSCopySpacesForWindows"
), to: (@convention(c) (Int, Int, CFArray) -> Unmanaged<CFArray>).self)

public let SLSSpaceGetType = unsafeBitCast(dlsym(
    libSkyLight,
    "SLSSpaceGetType"
), to: (@convention(c) (Int, UInt64) -> Int).self)
