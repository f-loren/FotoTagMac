import Darwin
import Foundation

/// Memoria del Mac e di MLX: tetto alla cache della GPU e controllo prima dell'analisi.
public enum Memoria {
    /// Tetto alla cache di MLX (buffer della GPU tenuti per riusarli): senza tetto può crescere fino a
    /// togliere memoria al sistema. Più piccolo sui Mac con poca memoria.
    public static func limiteCache(ramGB: Double) -> Int {
        let mb = 1 << 20
        if ramGB <= 8 { return 256 * mb }
        if ramGB <= 16 { return 1024 * mb }
        return 2048 * mb
    }

    /// Memoria che macOS considera disponibile (GB): la stessa stima di «memory_pressure» («free percentage»,
    /// kern.memorystatus_level), che conta anche quella recuperabile comprimendo. Libera + inattiva da sola
    /// è troppo prudente: su un Mac da 16 GB con qualche app aperta dà ~6 GB anche quando va tutto bene.
    public static func disponibileGB() -> Double {
        var livello: Int32 = 0
        var n = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_level", &livello, &n, nil, 0) == 0, livello > 0 else { return .infinity }
        return Double(livello) / 100 * Modelli.ramGB
    }

    /// Pressione sulla memoria secondo macOS: 1 normale, 2 attenzione, 4 critica.
    public static func pressione() -> Int {
        var p: Int32 = 0
        var n = MemoryLayout<Int32>.size
        return sysctlbyname("kern.memorystatus_vm_pressure_level", &p, &n, nil, 0) == 0 ? Int(p) : 1
    }

    /// Margine oltre al modello: l'immagine, la generazione e il resto dell'app.
    public static let margineGB = 1.5

    /// Nil se la memoria basta; altrimenti l'avviso da mostrare prima di partire. `modelloGB` conta solo se il
    /// modello non è ancora caricato.
    public static func avvisoPrimaDellAnalisi(disponibileGB: Double, modelloGB: Double, caricato: Bool, pressione: Int = 1) -> String? {
        let servono = (caricato ? 0 : modelloGB) + margineGB
        guard disponibileGB < servono || pressione >= 2 else { return nil }
        let gb = { (x: Double) in x.formatted(.number.precision(.fractionLength(1))) }
        return String(localized: "C'è poca memoria libera: \(gb(disponibileGB)) GB, e per l'analisi ne servono circa \(gb(servono)). Chiudi le app pesanti o aspetta che finiscano le compilazioni in corso (per esempio Xcode o Rust), poi riprova. Analizzare adesso può rallentare molto il Mac o fermarsi con un errore della GPU.")
    }
}
