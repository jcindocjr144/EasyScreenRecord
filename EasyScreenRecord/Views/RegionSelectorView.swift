import SwiftUI

struct RegionSelectorView: View {
    @ObservedObject var viewModel: RecorderViewModel
    @State private var isHovering = false
    
    var body: some View {
        ZStack {
            // Darkened background outside selection
            Color.black.opacity(0.15)
            
            // The Frame
            ZStack {
                // Main border with gradient
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.blue, .purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                
                // Corner Accents (Viewfinder style)
                ViewfinderCorners()
                    .stroke(Color.blue, lineWidth: 4)
                
                // Pulsing glow when hovered
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.blue.opacity(0.3), lineWidth: 8)
                    .blur(radius: 8)
                    .opacity(isHovering ? 1 : 0)
                    .animation(.easeInOut(duration: 0.5), value: isHovering)
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
            }
            
            // Centered Controls
            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 24, weight: .bold))
                    Text("SET RECORDING REGION")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .kerning(1.5)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
                
                Button(action: {
                    viewModel.confirmSelection()
                }) {
                    HStack {
                        Text("CONFIRM")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Image(systemName: "checkmark.circle.fill")
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 32)
                    .background(
                        LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(Capsule())
                    .shadow(color: .blue.opacity(0.4), radius: 15, y: 5)
                }
                .buttonStyle(PlainButtonStyle())
                .scaleEffect(isHovering ? 1.05 : 1.0)
                .animation(.spring(response: 0.3), value: isHovering)
            }
        }
        .ignoresSafeArea()
    }
}

struct ViewfinderCorners: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let len: CGFloat = 30
        let r: CGFloat = 16
        
        // Top Left
        path.move(to: CGPoint(x: 0, y: len))
        path.addLine(to: CGPoint(x: 0, y: r))
        path.addArc(center: CGPoint(x: r, y: r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.addLine(to: CGPoint(x: len, y: 0))
        
        // Top Right
        path.move(to: CGPoint(x: rect.width - len, y: 0))
        path.addLine(to: CGPoint(x: rect.width - r, y: 0))
        path.addArc(center: CGPoint(x: rect.width - r, y: r), radius: r, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.width, y: len))
        
        // Bottom Right
        path.move(to: CGPoint(x: rect.width, y: rect.height - len))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - r))
        path.addArc(center: CGPoint(x: rect.width - r, y: rect.height - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.width - len, y: rect.height))
        
        // Bottom Left
        path.move(to: CGPoint(x: len, y: rect.height))
        path.addLine(to: CGPoint(x: r, y: rect.height))
        path.addArc(center: CGPoint(x: r, y: rect.height - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: 0, y: rect.height - len))
        
        return path
    }
}
