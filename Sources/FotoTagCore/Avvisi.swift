import Foundation

/// Testi della notifica di fine analisi.
public enum Avvisi {
    /// «dicembre: analisi finita» / «333 foto analizzate, 5 da rivedere, 2 con errore.» (parti a zero omesse).
    public static func fine(cartella: String, analizzate: Int, daRivedere: Int, errori: Int) -> (titolo: String, testo: String) {
        var parti: [String] = []
        if analizzate > 0 { parti.append(String(localized: "\(analizzate) foto analizzate")) }
        if daRivedere > 0 { parti.append(String(localized: "\(daRivedere) da rivedere")) }
        if errori > 0 { parti.append(String(localized: "\(errori) con errore")) }
        return (String(localized: "\(cartella): analisi finita"), parti.isEmpty ? String(localized: "Nessuna foto analizzata.") : parti.joined(separator: ", ") + ".")
    }

    /// Analisi fermata da un errore della GPU: «dicembre: analisi interrotta dopo 59 foto».
    public static func interrotta(cartella: String, dopo fatte: Int) -> (titolo: String, testo: String) {
        (String(localized: "\(cartella): analisi interrotta dopo \(fatte) foto"), String(localized: "Errore della GPU: riprova con «Analizza»."))
    }

    /// Distintivo dell'icona nel Dock: vuoto a zero.
    public static func distintivo(_ daRivedere: Int) -> String { daRivedere > 0 ? "\(daRivedere)" : "" }
}
