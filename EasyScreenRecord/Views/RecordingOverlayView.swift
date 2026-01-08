import SwiftUI

struct RecordingOverlayView: View {
    let scale: CGFloat
    @State private var rotation: Double = 0
    
    var body: some View {
        ZStack {
            // High-tech scanner lines
            ViewfinderFrame()
                .stroke(
                    LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 2
                )
            
            // Pulsing center reticle
            ZStack {
                Circle()
                    .stroke(.red.opacity(0.3), lineWidth: 1)
                    .frame(width: 40, height: 40)
                    .scaleEffect(rotation == 0 ? 0.8 : 1.2)
                
                Rectangle()
                    .fill(.red)
                    .frame(width: 10, height: 1)
                Rectangle()
                    .fill(.red)
                    .frame(width: 1, height: 10)
            }
            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: rotation)
        }
        .padding(2) // Small inset for the border
        .onAppear {
            rotation = 360
        }
    }
}

struct ViewfinderFrame: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let size: CGFloat = 20
        let thickness: CGFloat = 2
        
        // Top Left
        path.move(to: CGPoint(x: 0, y: size))
        path.addLine(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: size, y: 0))
        
        // Top Right
        path.move(to: CGPoint(x: rect.width - size, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: size))
        
        // Bottom Right
        path.move(to: CGPoint(x: rect.width, y: rect.height - size))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: rect.width - size, y: rect.height))
        
        // Bottom Left
        path.move(to: CGPoint(x: size, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height - size))
        
        return path
    }
}
