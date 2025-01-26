import SwiftUI

struct GlassEffect: ViewModifier {
    let opacity: Double
    
    init(opacity: Double = 0.6) {
        self.opacity = opacity
    }
    
    func body(content: Content) -> some View {
        content
            .background {
                TranslucentBlurView()
                    .opacity(opacity)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .background {
                Color.white.opacity(0.15)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
            }
    }
}

struct TranslucentBlurView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIVisualEffectView {
        let blurEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        let view = UIVisualEffectView(effect: blurEffect)
        return view
    }
    
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

extension View {
    func glassEffect(opacity: Double = 0.6) -> some View {
        modifier(GlassEffect(opacity: opacity))
    }
} 