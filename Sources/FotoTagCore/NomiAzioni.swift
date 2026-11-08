import Foundation

/// Nomi delle azioni nel menu Composizione («Annulla …», «Ripeti …»), con l'oggetto dell'azione.
public enum NomiAzioni {
    public static func togliTag(_ t: String) -> String { String(localized: "Togli tag «\(t)»") }
    public static func aggiungiTag(_ t: String) -> String { String(localized: "Aggiungi tag «\(t)»") }
    public static func conferma(_ n: Int) -> String { n > 1 ? String(localized: "Conferma tag (\(n) foto)") : String(localized: "Conferma tag") }
    public static func riapri(_ n: Int) -> String { n > 1 ? String(localized: "Riapri (\(n) foto)") : String(localized: "Riapri") }
    public static var didascalia: String { String(localized: "Modifica didascalia") }
    /// `campo` è una parola italiana fissa («rullino», «tag fissi»…): si traduce con la sua voce nel catalogo.
    public static func correggi(_ campo: String, foto n: Int = 1) -> String {
        let c = Bundle.main.localizedString(forKey: campo, value: campo, table: nil)
        return n > 1 ? String(localized: "Correggi \(c) (\(n) foto)") : String(localized: "Correggi \(c)")
    }
}

/// Valore di un campo su più foto: uguale in tutte, oppure «valori diversi».
public enum ValoreComune<T: Equatable>: Equatable {
    case uguale(T)
    case diversi

    public init(_ valori: [T]) {
        guard let primo = valori.first, valori.allSatisfy({ $0 == primo }) else { self = .diversi; return }
        self = .uguale(primo)
    }

    public var valore: T? { if case .uguale(let v) = self { return v } else { return nil } }
}
