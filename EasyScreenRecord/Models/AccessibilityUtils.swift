import Foundation
import AppKit
import Carbon.HIToolbox

/// Keyboard input monitor for detecting typing activity
class KeyboardMonitor {
    static let shared = KeyboardMonitor()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var lastKeyPressTime: Date = .distantPast
    private(set) var isTyping: Bool = false

    // Keys to ignore (modifiers, function keys, navigation)
    private static let ignoredKeyCodes: Set<Int> = [
        kVK_Command, kVK_Shift, kVK_Option, kVK_Control,
        kVK_RightCommand, kVK_RightShift, kVK_RightOption, kVK_RightControl,
        kVK_Function, kVK_CapsLock,
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
        kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12,
        kVK_Escape,
        kVK_UpArrow, kVK_DownArrow, kVK_LeftArrow, kVK_RightArrow,
        kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown,
    ]

    private init() {}

    func startMonitoring() {
        guard eventTap == nil else { return }

        // Create event tap to capture keyboard events
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        // Use a static callback that can access the shared instance
        let callback: CGEventTapCallBack = { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
            // Handle tap disabled event
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = KeyboardMonitor.shared.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passRetained(event)
            }

            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

            // Check if it's a typing key (not modifier/function/navigation)
            if !KeyboardMonitor.ignoredKeyCodes.contains(Int(keyCode)) {
                // Check modifier flags - ignore if Command or Control is held
                let flags = event.flags
                let hasCommandOrControl = flags.contains(.maskCommand) || flags.contains(.maskControl)

                if !hasCommandOrControl {
                    KeyboardMonitor.shared.lastKeyPressTime = Date()
                    KeyboardMonitor.shared.isTyping = true

                    #if DEBUG
                    print("[KeyboardMonitor] Key detected: \(keyCode)")
                    #endif
                }
            }

            return Unmanaged.passRetained(event)
        }

        // Create the event tap (listen only, don't modify events)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: nil
        ) else {
            #if DEBUG
            print("[KeyboardMonitor] Failed to create event tap. Check accessibility permissions.")
            #endif
            return
        }

        eventTap = tap

        // Create run loop source and add to current run loop
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        // Enable the tap
        CGEvent.tapEnable(tap: tap, enable: true)

        #if DEBUG
        print("[KeyboardMonitor] Started monitoring keyboard events with CGEvent tap")
        #endif
    }

    func stopMonitoring() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }

        eventTap = nil
        isTyping = false

        #if DEBUG
        print("[KeyboardMonitor] Stopped monitoring keyboard events")
        #endif
    }

    /// Check if typing was detected within the given time interval
    func isTypingActive(within interval: TimeInterval) -> Bool {
        let timeSinceLastKey = Date().timeIntervalSince(lastKeyPressTime)
        let active = timeSinceLastKey < interval
        if !active {
            isTyping = false
        }
        return active
    }
}

struct AccessibilityUtils {

    // Text input role identifiers (used as fallback)
    private static let textInputRoles: Set<String> = [
        kAXTextFieldRole as String,
        kAXTextAreaRole as String,
        kAXComboBoxRole as String,
        "AXSearchField",
        "AXWebArea",
        "AXScrollArea",
    ]

    private static var lastDebugLog: Date = .distantPast

    /// Get cursor position - uses keyboard monitoring + focused element position
    static func getTypingCursorPosition() -> CGPoint? {
        // Check if typing is active (keyboard was pressed recently)
        // Use a short window (0.5s) - if no typing, return nil immediately
        guard KeyboardMonitor.shared.isTypingActive(within: 0.5) else {
            return nil
        }

        // Typing detected - now find position to zoom to
        return getFocusedElementPosition()
    }

    /// Get position of the currently focused element (for zoom target)
    /// Strategy: try caret position first, then fall back to mouse cursor
    /// (element/window center is often wrong for Terminal/browsers)
    /// All positions are returned in screen coordinates (top-left origin, matching Accessibility API)
    static func getFocusedElementPosition() -> CGPoint? {
        let frontApp = NSWorkspace.shared.frontmostApplication

        // 1. Try to get focused element and its caret position
        var focusedElement: CFTypeRef?
        let systemWideElement = AXUIElementCreateSystemWide()
        var result = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        if result != .success || focusedElement == nil {
            if let app = frontApp {
                let appElement = AXUIElementCreateApplication(app.processIdentifier)
                result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
            }
        }

        if result == .success, let element = focusedElement {
            let axElement = element as! AXUIElement

            // Try caret position (most precise - works for text editors, some text fields)
            if let caretPos = getCaretPosition(for: axElement) {
                #if DEBUG
                if Date().timeIntervalSince(lastDebugLog) > 1.0 {
                    print("[Position] Using caret: \(caretPos)")
                    lastDebugLog = Date()
                }
                #endif
                return caretPos
            }

            // For small elements (likely text fields), use element center
            if let elemPos = getSmallElementPosition(for: axElement) {
                #if DEBUG
                if Date().timeIntervalSince(lastDebugLog) > 1.0 {
                    print("[Position] Using small element: \(elemPos)")
                    lastDebugLog = Date()
                }
                #endif
                return elemPos
            }
        }

        // 2. Fall back to mouse cursor position
        // This is better than window center for Terminal/browsers where caret position isn't available
        // Users typically have their focus (and often mouse) near where they're typing
        if let mousePos = getMousePositionInScreenCoords() {
            #if DEBUG
            if Date().timeIntervalSince(lastDebugLog) > 1.0 {
                print("[Position] Using mouse: \(mousePos)")
                lastDebugLog = Date()
            }
            #endif
            return mousePos
        }

        return nil
    }

    /// Get element position only if it's a small element (likely a text field, not a whole window)
    private static func getSmallElementPosition(for element: AXUIElement) -> CGPoint? {
        var pointValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &pointValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let pointRef = pointValue, CFGetTypeID(pointRef) == AXValueGetTypeID(),
              let sizeRef = sizeValue, CFGetTypeID(sizeRef) == AXValueGetTypeID() else {
            return nil
        }

        var pos = CGPoint.zero
        var size = CGSize.zero

        AXValueGetValue(pointRef as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)

        // Only use element position if it's reasonably small (like a text field)
        // Large elements (like terminal views, web areas) would give wrong center position
        let maxReasonableSize: CGFloat = 400
        if size.width > 0 && size.height > 0 &&
           size.width < maxReasonableSize && size.height < maxReasonableSize {
            return CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2)
        }

        return nil
    }

    /// Get mouse cursor position in screen coordinates (top-left origin)
    private static func getMousePositionInScreenCoords() -> CGPoint? {
        // NSEvent.mouseLocation is in bottom-left origin (Cocoa coordinates)
        let mouseLocation = NSEvent.mouseLocation

        // Find the screen containing the mouse
        for screen in NSScreen.screens {
            if screen.frame.contains(mouseLocation) {
                // Get the primary screen's height for coordinate conversion
                // Accessibility API uses top-left origin where Y=0 is at top of primary screen
                guard let primaryScreen = NSScreen.screens.first else { return nil }
                let primaryHeight = primaryScreen.frame.height

                // Convert: in Cocoa, Y increases upward; in Accessibility, Y increases downward
                let screenY = primaryHeight - mouseLocation.y
                return CGPoint(x: mouseLocation.x, y: screenY)
            }
        }

        return nil
    }

    /// Get element position (center point)
    private static func getElementPosition(for element: AXUIElement) -> CGPoint? {
        var pointValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &pointValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let pointRef = pointValue, CFGetTypeID(pointRef) == AXValueGetTypeID(),
              let sizeRef = sizeValue, CFGetTypeID(sizeRef) == AXValueGetTypeID() else {
            return nil
        }

        var pos = CGPoint.zero
        var size = CGSize.zero

        AXValueGetValue(pointRef as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)

        if size.width > 0 && size.height > 0 {
            return CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2)
        }

        return nil
    }

    private static func isTextInputElement(_ element: AXUIElement) -> Bool {
        var roleValue: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        let role = (roleResult == .success) ? (roleValue as? String ?? "") : ""

        // Check for known text input roles
        if textInputRoles.contains(role) {
            return true
        }

        // Check for selected text range attribute (strong indicator of text input)
        // This works for most text inputs including web browsers
        var rangeValue: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue)
        if rangeResult == .success {
            return true
        }

        // Check if element has editable text trait (for web browsers, Electron apps, etc.)
        var editableValue: CFTypeRef?
        let editableResult = AXUIElementCopyAttributeValue(element, "AXInsertionPointLineNumber" as CFString, &editableValue)
        if editableResult == .success {
            return true
        }

        // Check for AXFocused attribute on text-like elements (web content)
        if role == "AXStaticText" || role == "AXWebArea" || role == "AXGroup" || role == "AXUnknown" {
            var rangeValue2: CFTypeRef?
            let rangeResult2 = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue2)
            if rangeResult2 == .success {
                return true
            }
        }

        // Check for value attribute with string and editable flag
        var valueRef: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
        if valueResult == .success, valueRef is String {
            // Check if element is editable
            var editableRef: CFTypeRef?
            let editableAttrResult = AXUIElementCopyAttributeValue(element, "AXEditable" as CFString, &editableRef)
            if editableAttrResult == .success {
                return true
            }
        }

        // Additional check: some web browsers mark the element as having a role description
        // that includes "text" or "input"
        var roleDescValue: CFTypeRef?
        let roleDescResult = AXUIElementCopyAttributeValue(element, kAXRoleDescriptionAttribute as CFString, &roleDescValue)
        if roleDescResult == .success, let roleDesc = roleDescValue as? String {
            let lowerDesc = roleDesc.lowercased()
            if lowerDesc.contains("text") || lowerDesc.contains("入力") || lowerDesc.contains("テキスト") {
                return true
            }
        }

        return false
    }

    private static func getCaretPosition(for element: AXUIElement) -> CGPoint? {
        // Try to get selected text range
        var rangeValue: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue)

        guard rangeResult == .success, let rangeRef = rangeValue else {
            return nil
        }

        // Get bounds for the selected range (caret position)
        var boundsValue: CFTypeRef?
        let boundsResult = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeRef,
            &boundsValue
        )

        if boundsResult == .success,
           let boundsRef = boundsValue,
           CFGetTypeID(boundsRef) == AXValueGetTypeID() {
            var bounds = CGRect.zero
            AXValueGetValue(boundsRef as! AXValue, .cgRect, &bounds)

            // Return the center of the caret bounds
            // For a caret (zero-width selection), this will be the insertion point
            return CGPoint(x: bounds.midX, y: bounds.midY)
        }

        return nil
    }

    /// Get the currently typed/selected text from the focused element
    static func getTypedText() -> String? {
        // Only try to get text if typing was recently detected
        guard KeyboardMonitor.shared.isTypingActive(within: 1.0) else {
            return nil
        }

        var focusedElement: CFTypeRef?

        // Get focused element from system-wide
        let systemWideElement = AXUIElementCreateSystemWide()
        var result = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        // Fallback to frontmost app
        if result != .success || focusedElement == nil {
            if let app = NSWorkspace.shared.frontmostApplication {
                let appElement = AXUIElementCreateApplication(app.processIdentifier)
                result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
            }
        }

        guard result == .success, let element = focusedElement else {
            return nil
        }

        let axElement = element as! AXUIElement

        // Try to get selected text first
        var selectedTextValue: CFTypeRef?
        let selectedResult = AXUIElementCopyAttributeValue(axElement, kAXSelectedTextAttribute as CFString, &selectedTextValue)
        if selectedResult == .success, let selectedText = selectedTextValue as? String, !selectedText.isEmpty {
            return selectedText
        }

        // Get full value and extract recent text (last line or portion)
        var valueRef: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(axElement, kAXValueAttribute as CFString, &valueRef)
        if valueResult == .success, let text = valueRef as? String, !text.isEmpty {
            // Get the last line or last portion of text (for subtitle display)
            let lines = text.components(separatedBy: .newlines)
            if let lastLine = lines.last, !lastLine.isEmpty {
                // Limit to reasonable length for subtitle
                let maxLength = 80
                if lastLine.count > maxLength {
                    return String(lastLine.suffix(maxLength))
                }
                return lastLine
            }
        }

        return nil
    }

    private static func getElementCenterPosition(for element: AXUIElement) -> CGPoint? {
        var pointValue: CFTypeRef?
        let pointResult = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &pointValue)

        var sizeValue: CFTypeRef?
        let sizeResult = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)

        if pointResult == .success, let pointRef = pointValue, CFGetTypeID(pointRef) == AXValueGetTypeID(),
           sizeResult == .success, let sizeRef = sizeValue, CFGetTypeID(sizeRef) == AXValueGetTypeID() {

            var pos = CGPoint.zero
            var size = CGSize.zero

            AXValueGetValue(pointRef as! AXValue, .cgPoint, &pos)
            AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)

            // Only consider it valid if it's a reasonable text field size
            if size.height < 200 && size.height > 10 {
                return CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2)
            }
        }

        return nil
    }
}
