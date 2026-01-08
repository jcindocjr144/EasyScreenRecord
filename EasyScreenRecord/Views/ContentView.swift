import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: RecorderViewModel
    
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
        }
        .padding(32)
        .frame(width: 360)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow).ignoresSafeArea())
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
