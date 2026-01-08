import SwiftUI
import AppKit

@main
struct EasyScreenRecordApp: App {
    @StateObject private var viewModel = RecorderViewModel()
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    init() {
        // Request Accessibility permission on app launch
        requestAccessibilityPermission()
    }

    private func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)

        #if DEBUG
        print("[Accessibility] Permission status: \(accessEnabled ? "granted" : "not granted")")
        #endif
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(viewModel: viewModel)
                .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow).ignoresSafeArea())
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra("EasyRecord", systemImage: viewModel.isRecording ? "record.circle.fill" : "video.fill") {
            Button(viewModel.isRecording ? "Stop Recording" : "Start Recording") {
                viewModel.toggleRecording()
            }
            .keyboardShortcut("r", modifiers: .command)
            
            Divider()
            
            Button("Open Controls...") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            .keyboardShortcut("o", modifiers: .command)
            
            Button("Settings...") {
                // Future settings
            }
            
            Divider()
            
            Button("Quit EasyRecord") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}
