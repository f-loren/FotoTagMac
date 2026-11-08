import SwiftUI

/// Gli unici valori di movimento di FotoTag (D67). Si anima solo ciò che cambia per un motivo esterno
/// (analisi, scrittura, arrivo di un file, apertura della ricerca), mai le azioni da tastiera ripetute
/// (↩, frecce, spazio). Con Riduci movimento restano solo le dissolvenze.
enum Movimento {
    /// Dissolvenze: miniature che arrivano dal disco, risultati della ricerca. Decelerazione decisa.
    static let rapida = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.15)
    /// Entrate e uscite: distintivi, tag, riquadri della barra laterale, foglio di scrittura, striscia della ricerca.
    static let standard = Animation.spring(response: 0.3, dampingFraction: 1)
    /// Un passaggio della linea dello scanner sulla foto in analisi.
    static let giroScanner = 1.6

    /// Entra ed esce dal bordo indicato; con Riduci movimento solo dissolvenza.
    static func dal(_ bordo: Edge, riduci: Bool) -> AnyTransition {
        riduci ? .opacity : .move(edge: bordo).combined(with: .opacity)
    }
    /// Distintivi e tag: si stringono appena e svaniscono; con Riduci movimento solo dissolvenza.
    static func comparsa(riduci: Bool) -> AnyTransition {
        riduci ? .opacity : .scale(scale: 0.9).combined(with: .opacity)
    }
}

/// Linea di luce che scorre sulla foto che il modello sta leggendo, come la barra di uno scanner sul negativo.
/// Con Riduci movimento: un bordo fermo del colore d'accento.
struct LineaScanner: View {
    @Environment(\.accessibilityReduceMotion) private var riduci

    var body: some View {
        if riduci {
            RoundedRectangle(cornerRadius: 5).strokeBorder(Color.accentColor, lineWidth: 2)
        } else {
            GeometryReader { g in
                KeyframeAnimator(initialValue: -0.3, repeating: true) { y in
                    LinearGradient(colors: [.clear, .accentColor.opacity(0.4), .white.opacity(0.8), .accentColor.opacity(0.4), .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: g.size.height * 0.3)
                        .offset(y: y * g.size.height)
                } keyframes: { _ in
                    KeyframeTrack { LinearKeyframe(1.0, duration: Movimento.giroScanner) }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
