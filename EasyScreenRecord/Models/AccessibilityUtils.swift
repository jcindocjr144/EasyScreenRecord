import Foundation
import AppKit

struct AccessibilityUtils {

    // Text input role identifiers
    private static let textInputRoles: Set<String> = [
        kAXTextFieldRole as String,
        kAXTextAreaRole as String,
        kAXComboBoxRole as String,
        "AXSearchField"  // kAXSearchFieldRole is not available in Swift
    ]

    private static var lastDebugLog: Date = .distantPast

    static func getTypingCursorPosition() -> CGPoint? {
        // Try getting focused element from system-wide first
        var focusedElement: CFTypeRef?
        var result: AXError = .failure

        // Get frontmost app info for debugging
        let frontApp = NSWorkspace.shared.frontmostApplication
        let appName = frontApp?.localizedName ?? "unknown"

        // Method 1: System-wide element
        let systemWideElement = AXUIElementCreateSystemWide()
        result = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        #if DEBUG
        if Date().timeIntervalSince(lastDebugLog) > 2.0 {
            print("[Accessibility] Front app: \(appName), system-wide result: \(result.rawValue)")
        }
        #endif

        // Method 2: If system-wide fails, try via frontmost application
        if result != .success || focusedElement == nil {
            if let app = frontApp {
                let appElement = AXUIElementCreateApplication(app.processIdentifier)
                let appResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)

                #if DEBUG
                if Date().timeIntervalSince(lastDebugLog) > 2.0 {
                    print("[Accessibility] App element result: \(appResult.rawValue)")
                }
                #endif

                if appResult == .success {
                    result = appResult
                }
            }
        }

        guard result == .success, let element = focusedElement else {
            #if DEBUG
            if Date().timeIntervalSince(lastDebugLog) > 2.0 {
                print("[Accessibility] No focused element found, final result: \(result.rawValue)")
                lastDebugLog = Date()
            }
            #endif
            return nil
        }

        let axElement = element as! AXUIElement

        // Debug: Get role and subrole of focused element
        #if DEBUG
        if Date().timeIntervalSince(lastDebugLog) > 2.0 {
            var roleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(axElement, kAXRoleAttribute as CFString, &roleValue)
            let role = roleValue as? String ?? "unknown"

            var subroleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(axElement, kAXSubroleAttribute as CFString, &subroleValue)
            let subrole = subroleValue as? String ?? "none"

            var descValue: CFTypeRef?
            AXUIElementCopyAttributeValue(axElement, kAXDescriptionAttribute as CFString, &descValue)
            let desc = descValue as? String ?? "none"

            print("[Accessibility] Focused element - role: \(role), subrole: \(subrole), desc: \(desc)")
            lastDebugLog = Date()
        }
        #endif

        // Check if this is a text input element
        let isTextInput = isTextInputElement(axElement)
        #if DEBUG
        if !isTextInput && Date().timeIntervalSince(lastDebugLog) > 0.5 {
            print("[Accessibility] Element not recognized as text input")
        }
        #endif

        guard isTextInput else {
            return nil
        }

        // Try to get insertion point (caret) position using selected text range bounds
        if let caretPosition = getCaretPosition(for: axElement) {
            return caretPosition
        }

        // Fallback: Get Position and Size of the focused element
        return getElementCenterPosition(for: axElement)
    }

    private static func isTextInputElement(_ element: AXUIElement) -> Bool {
        var roleValue: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)

        if roleResult == .success, let role = roleValue as? String {
            // Check for known text input roles
            if textInputRoles.contains(role) {
                return true
            }

            // Also accept AXStaticText with editable trait (some apps use this)
            if role == "AXStaticText" || role == "AXWebArea" || role == "AXGroup" {
                // Check if it has selected text range (indicates text editing capability)
                var rangeValue: CFTypeRef?
                let rangeResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue)
                if rangeResult == .success {
                    return true
                }
            }
        }

        // Check if element has editable text trait (for web browsers, Electron apps, etc.)
        var editableValue: CFTypeRef?
        let editableResult = AXUIElementCopyAttributeValue(element, "AXInsertionPointLineNumber" as CFString, &editableValue)
        if editableResult == .success {
            return true
        }

        // Check for selected text range attribute (strong indicator of text input)
        var rangeValue: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue)
        if rangeResult == .success {
            return true
        }

        // Check for value attribute with string (text fields typically have this)
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
