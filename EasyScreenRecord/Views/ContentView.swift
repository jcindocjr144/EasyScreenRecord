import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: RecorderViewModel
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 28) {
            // Header
            VStack(spacing: 4) {
                HStack {
                    Image(systemName: "record.circle.fill")
                        .foregroundStyle(.blue.gradient)
                        .font(.title3)
                    Text("EASY RECORD")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .kerning(1.2)
                    Spacer()
                    Button(action: { showSettings.toggle() }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    Circle()
                        .fill(viewModel.isRecording ? Color.red : Color.gray.opacity(0.3))
                        .frame(width: 10, height: 10)
                        .shadow(color: viewModel.isRecording ? .red.opacity(0.6) : .clear, radius: 5)
                }
                HStack {
                    Text("ZOOM ON FOCUS TOOL")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .kerning(1.0)
                    Spacer()
                }
            }
            .padding(.horizontal, 4)
            
            // Preview/Status Area
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.black.opacity(0.25))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                
                if viewModel.isRecording {
                    VStack(spacing: 12) {
                        Image(systemName: "dot.circle.and.cursorarrow")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(.red)
                            .symbolEffect(.pulse, options: .repeating)
                        Text("RECORDING ACTIVE")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.red.opacity(0.8))
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "video.badge.plus")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(.secondary.opacity(0.4))
                        Text("AWAITING START")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 140)

            // Zoom Control
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.caption)
                    Text("DYNAMIC ZOOM")
                        .font(.system(size: 10, weight: .heavy))
                    Spacer()
                    Text(String(format: "%.1fX", viewModel.zoomScale))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.blue)
                }
                Slider(value: $viewModel.zoomScale, in: 1.0...4.0, step: 0.1)
                    .tint(.blue)
            }
            .padding(.horizontal, 8)
            
            // Region Selection
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "scope")
                        .font(.caption)
                    Text("CAPTURE AREA")
                        .font(.system(size: 10, weight: .heavy))
                    Spacer()
                }
                
                HStack(spacing: 12) {
                    AreaButton(
                        icon: "macwindow",
                        title: "FULL SCREEN",
                        isSelected: viewModel.recorder.baseRegion == nil,
                        action: { viewModel.setFullScreen() }
                    )
                    
                    AreaButton(
                        icon: "viewfinder",
                        title: "CUSTOM REGION",
                        isSelected: viewModel.recorder.baseRegion != nil,
                        action: { viewModel.startSelection() }
                    )
                }
            }
            .padding(.horizontal, 4)
            .disabled(viewModel.isRecording)
            
            // Primary Controls
            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    viewModel.toggleRecording()
                }
            }) {
                HStack(spacing: 12) {
                    Image(systemName: viewModel.isRecording ? "stop.fill" : "record.circle.fill")
                        .font(.title2)
                    Text(viewModel.isRecording ? "STOP RECORDING" : "START RECORDING")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    ZStack {
                        if viewModel.isRecording {
                            Color.red.opacity(0.8)
                        } else {
                            LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: (viewModel.isRecording ? Color.red : Color.blue).opacity(0.3), radius: 15, y: 8)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.recorder.isBusy)
            .opacity(viewModel.recorder.isBusy ? 0.6 : 1.0)

            // Settings Panel (collapsible)
            if showSettings {
                ZoomSettingsView(settings: viewModel.recorder.zoomSettings)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(32)
        .frame(width: 360)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow).ignoresSafeArea())
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showSettings)
    }
}

// MARK: - Zoom Settings View
struct ZoomSettingsView: View {
    @ObservedObject var settings: ZoomSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Smart Zoom Master Toggle
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "sparkle.magnifyingglass")
                        .foregroundStyle(.blue)
                    Text("Smart Zoom")
                        .font(.system(size: 11, weight: .bold))
                    Spacer()
                    Toggle("", isOn: $settings.smartZoomEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                Text("テキスト入力時に自動でズームイン。OFFにすると通常録画")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary.opacity(0.8))
            }
            .padding(10)
            .background(Color.blue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if settings.smartZoomEnabled {
                // Presets
                VStack(alignment: .leading, spacing: 6) {
                    Text("PRESETS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        PresetButton(title: "Smooth", icon: "tortoise.fill") {
                            applyPreset(.smooth)
                        }
                        PresetButton(title: "Default", icon: "circle.fill") {
                            applyPreset(.default)
                        }
                        PresetButton(title: "Fast", icon: "hare.fill") {
                            applyPreset(.responsive)
                        }
                    }
                }

                Divider().opacity(0.3)

                // Zoom Settings Section
                SettingSection(title: "ZOOM", icon: "plus.magnifyingglass") {
                    VStack(alignment: .leading, spacing: 10) {
                        SettingRow(label: "Scale", value: String(format: "%.1fx", settings.zoomScale), description: "ズーム倍率。2.0xで画面の半分のサイズに拡大") {
                            Stepper("", value: $settings.zoomScale, in: settings.minZoomScale...settings.maxZoomScale, step: 0.5)
                                .labelsHidden()
                        }
                        SettingRow(label: "Min", value: String(format: "%.1fx", settings.minZoomScale), description: "最小ズーム倍率（スライダー下限）") {
                            Stepper("", value: $settings.minZoomScale, in: 1.0...3.0, step: 0.5)
                                .labelsHidden()
                        }
                        SettingRow(label: "Max", value: String(format: "%.1fx", settings.maxZoomScale), description: "最大ズーム倍率（スライダー上限）") {
                            Stepper("", value: $settings.maxZoomScale, in: 2.0...10.0, step: 0.5)
                                .labelsHidden()
                        }
                    }
                }

                Divider().opacity(0.3)

                // Follow Behavior Section
                SettingSection(title: "FOLLOW BEHAVIOR", icon: "arrow.triangle.2.circlepath") {
                    VStack(alignment: .leading, spacing: 10) {
                        SettingRow(label: "Edge Margin", value: "\(Int(settings.edgeMarginRatio * 100))%", description: "セーフゾーンの幅。この範囲内ではカメラが追従しない") {
                            Stepper("", value: $settings.edgeMarginRatio, in: 0.05...0.4, step: 0.05)
                                .labelsHidden()
                        }
                        SettingRow(label: "Zoom Hold", value: String(format: "%.1fs", settings.zoomHoldDuration), description: "入力停止後にズームを維持する時間") {
                            Stepper("", value: $settings.zoomHoldDuration, in: 0.5...5.0, step: 0.5)
                                .labelsHidden()
                        }
                        SettingRow(label: "Reposition Delay", value: String(format: "%.1fs", settings.positionHoldDuration), description: "カーソル追従の遅延。大きいと安定、小さいと即座に追従") {
                            Stepper("", value: $settings.positionHoldDuration, in: 0.1...2.0, step: 0.1)
                                .labelsHidden()
                        }
                    }
                }

                Divider().opacity(0.3)

                // Center Offset Section
                SettingSection(title: "CENTER OFFSET", icon: "move.3d") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("カーソル位置からのズーム中心のオフセット")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary.opacity(0.7))
                        HStack(spacing: 12) {
                            SettingRow(label: "X", value: String(format: "%+.2f", settings.centerOffsetX)) {
                                Stepper("", value: $settings.centerOffsetX, in: -0.4...0.4, step: 0.05)
                                    .labelsHidden()
                            }
                            SettingRow(label: "Y", value: String(format: "%+.2f", settings.centerOffsetY)) {
                                Stepper("", value: $settings.centerOffsetY, in: -0.4...0.4, step: 0.05)
                                    .labelsHidden()
                            }
                            Button("Reset") {
                                settings.centerOffsetX = 0
                                settings.centerOffsetY = 0
                            }
                            .font(.system(size: 9))
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }

                Divider().opacity(0.3)

                // Animation Section
                SettingSection(title: "ANIMATION", icon: "waveform.path") {
                    VStack(alignment: .leading, spacing: 10) {
                        SettingRow(label: "Zoom Speed", value: String(format: "%.2f", settings.scaleSmoothing), description: "ズームイン/アウトの速度。大きいと速く、小さいと滑らか") {
                            Stepper("", value: $settings.scaleSmoothing, in: 0.01...0.2, step: 0.01)
                                .labelsHidden()
                        }
                        SettingRow(label: "Move Speed", value: String(format: "%.2f", settings.positionSmoothing), description: "カメラ移動の速度。大きいと速く、小さいと滑らか") {
                            Stepper("", value: $settings.positionSmoothing, in: 0.01...0.2, step: 0.01)
                                .labelsHidden()
                        }
                    }
                }

                Divider().opacity(0.3)

                // Overlay Section
                SettingSection(title: "OVERLAY", icon: "square.dashed") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("録画中の画面に表示するガイド（録画には映らない）")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary.opacity(0.7))
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Toggle("Corner Brackets", isOn: $settings.showOverlay)
                                    .toggleStyle(.switch)
                                    .controlSize(.small)
                                Text("四隅の赤い枠")
                                    .font(.system(size: 7))
                                    .foregroundStyle(.secondary.opacity(0.6))
                            }
                            Spacer()
                            VStack(alignment: .leading, spacing: 2) {
                                Toggle("Safe Zone", isOn: $settings.showSafeZone)
                                    .toggleStyle(.switch)
                                    .controlSize(.small)
                                Text("緑のセーフゾーン枠")
                                    .font(.system(size: 7))
                                    .foregroundStyle(.secondary.opacity(0.6))
                            }
                        }
                        .font(.system(size: 10, weight: .medium))

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Toggle("Dimming", isOn: $settings.showDimming)
                                    .toggleStyle(.switch)
                                    .controlSize(.small)
                                Text("録画範囲外を暗く")
                                    .font(.system(size: 7))
                                    .foregroundStyle(.secondary.opacity(0.6))
                            }
                            if settings.showDimming {
                                Spacer()
                                SettingRow(label: "Opacity", value: "\(Int(settings.dimmingOpacity * 100))%") {
                                    Stepper("", value: $settings.dimmingOpacity, in: 0.1...0.8, step: 0.1)
                                        .labelsHidden()
                                }
                            }
                        }
                        .font(.system(size: 10, weight: .medium))
                    }
                }
            }

            Divider().opacity(0.3)

            // Recording Section
            SettingSection(title: "RECORDING", icon: "video.fill") {
                VStack(alignment: .leading, spacing: 10) {
                    SettingRow(label: "Frame Rate", value: "\(settings.frameRate) fps", description: "録画のフレームレート。高いほど滑らかだがファイルサイズ増加") {
                        Picker("", selection: $settings.frameRate) {
                            Text("15").tag(15)
                            Text("30").tag(30)
                            Text("60").tag(60)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 100)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Toggle("Show Cursor", isOn: $settings.showCursor)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                            Text("録画にカーソルを含める")
                                .font(.system(size: 7))
                                .foregroundStyle(.secondary.opacity(0.6))
                        }
                        Spacer()
                        SettingRow(label: "Quality", value: "\(Int(settings.videoQuality * 100))%", description: "ビットレート") {
                            Stepper("", value: $settings.videoQuality, in: 0.5...1.0, step: 0.1)
                                .labelsHidden()
                        }
                    }
                    .font(.system(size: 10, weight: .medium))
                }
            }
        }
        .padding(14)
        .background(Color.black.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func applyPreset(_ preset: ZoomSettings) {
        withAnimation(.easeInOut(duration: 0.2)) {
            settings.scaleSmoothing = preset.scaleSmoothing
            settings.positionSmoothing = preset.positionSmoothing
            settings.edgeMarginRatio = preset.edgeMarginRatio
            settings.zoomHoldDuration = preset.zoomHoldDuration
            settings.positionHoldDuration = preset.positionHoldDuration
        }
    }
}

// MARK: - Setting Row
struct SettingRow<Content: View>: View {
    let label: String
    let value: String
    var description: String? = nil
    @ViewBuilder let control: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.blue)
                control
            }
            if let desc = description {
                Text(desc)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .lineLimit(2)
            }
        }
    }
}

// MARK: - Setting Section
struct SettingSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            content
        }
    }
}

// MARK: - Edge Margin Visual Indicator
struct EdgeMarginIndicator: View {
    let margin: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Outer frame (full area)
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)

                // Edge margin zones (red areas)
                let marginWidth = geo.size.width * margin
                let marginHeight = geo.size.height * margin

                // Left edge
                Rectangle()
                    .fill(Color.red.opacity(0.3))
                    .frame(width: marginWidth)
                    .position(x: marginWidth / 2, y: geo.size.height / 2)

                // Right edge
                Rectangle()
                    .fill(Color.red.opacity(0.3))
                    .frame(width: marginWidth)
                    .position(x: geo.size.width - marginWidth / 2, y: geo.size.height / 2)

                // Top edge
                Rectangle()
                    .fill(Color.red.opacity(0.3))
                    .frame(width: geo.size.width - marginWidth * 2, height: marginHeight)
                    .position(x: geo.size.width / 2, y: marginHeight / 2)

                // Bottom edge
                Rectangle()
                    .fill(Color.red.opacity(0.3))
                    .frame(width: geo.size.width - marginWidth * 2, height: marginHeight)
                    .position(x: geo.size.width / 2, y: geo.size.height - marginHeight / 2)

                // Center safe zone (green)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.green.opacity(0.2))
                    .frame(
                        width: geo.size.width - marginWidth * 2,
                        height: geo.size.height - marginHeight * 2
                    )

                // Cursor icon in center
                Image(systemName: "cursorarrow")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)

                // Labels
                Text("Safe Zone")
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(.green.opacity(0.8))
                    .offset(y: 12)
            }
        }
    }
}

struct PresetButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 8))
                Text(title)
                    .font(.system(size: 8, weight: .bold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

struct AreaButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.system(size: 9, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isSelected ? Color.blue.opacity(0.15) : Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.blue : Color.white.opacity(0.1), lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

#Preview {
    ContentView(viewModel: RecorderViewModel())
}
