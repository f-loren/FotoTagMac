import AppKit
import Foundation
import NaturalLanguage

/// Risposta del modello già divisa per campo.
public struct Risposta: Codable, Sendable, Equatable {
    public var campi: [String: [String]]
    public var didascalia: String

    public static let vuota = Risposta(campi: [:], didascalia: "")
    public var numeroVoci: Int { categorie.reduce(0) { $0 + (campi[$1]?.count ?? 0) } }
}

/// Legge il JSON prodotto dal modello, anche se "sporco": blocchi ```json, testo prima o dopo,
/// virgole finali, virgolette tipografiche, un campo stringa al posto di una lista. Nil se non si salva.
public func leggiRisposta(_ testo: String) -> Risposta? {
    var t = testo.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
    guard let a = t.firstIndex(of: "{"), let b = t.lastIndex(of: "}"), a < b else { return nil }
    t = String(t[a...b])
    var candidati = [t]
    var riparato = t.replacingOccurrences(of: "“", with: "\"").replacingOccurrences(of: "”", with: "\"")
    riparato = riparato.replacingOccurrences(of: #",\s*([\]}])"#, with: "$1", options: .regularExpression)
    candidati.append(riparato)
    for c in candidati {
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(c.utf8))) as? [String: Any] else { continue }
        var campi: [String: [String]] = [:]
        for k in categorie {
            switch obj[k] {
            case let l as [Any]: campi[k] = l.map { "\($0)" }
            case let s as String where !s.isEmpty: campi[k] = [s]
            default: campi[k] = []
            }
        }
        // se mancano quasi tutte le chiavi non è la risposta che volevamo
        if categorie.filter({ obj[$0] != nil }).count < 3 && obj["didascalia"] == nil { continue }
        return Risposta(campi: campi, didascalia: (obj["didascalia"] as? String) ?? "")
    }
    return nil
}

/// Pulizia delle parole chiave come clean_terms / _analyze_one nel prototipo.
@MainActor
public enum Pulizia {
    public static let massimoParole = 15

    static func ortografiaOK(_ parola: String, lingua: String) -> Bool {
        let sc = NSSpellChecker.shared
        for w in [parola, parola.capitalized] {
            let r = sc.checkSpelling(of: w, startingAt: 0, language: lingua, wrap: false,
                                     inSpellDocumentWithTag: 0, wordCount: nil)
            if r.length == 0 { return true }
        }
        return false
    }

    /// Vero se almeno una parola non è nel dizionario della lingua dei tag: inglese ('parks') o storpiata
    /// ('sorrider', 'gire'). I nomi propri passano perché si prova anche con l'iniziale maiuscola ('Venezia').
    /// Il dizionario di macOS accetta però le forme tronche ('sorrider'): se la parola finisce per consonante
    /// e NaturalLanguage non le trova un lemma, si scarta (sulle 457 parole dell'archivio: nessun falso scarto).
    static func fuoriDizionario(_ termine: String, lingua: Lingua) -> Bool {
        termine.split(separator: " ").contains { p in
            let w = String(p)
            if !ortografiaOK(w, lingua: lingua.codice) { return true }
            // le forme tronche sono un difetto dell'italiano: in inglese quasi tutte le parole finiscono per consonante
            guard lingua.codice == "it", let ultima = w.last, !"aeiouàèéìòù'".contains(ultima) else { return false }
            let t = NLTagger(tagSchemes: [.lemma])
            t.string = w
            t.setLanguage(NLLanguage(lingua.codice), range: w.startIndex..<w.endIndex)
            return t.tag(at: w.startIndex, unit: .word, scheme: .lemma).0 == nil
        }
    }

    public static func termini(_ grezzi: [String], lingua: Lingua) -> (buoni: [String], scartati: [String]) {
        var buoni: [String] = [], scartati: [String] = []
        for g in grezzi {
            var t = g.lowercased().replacingOccurrences(of: #"[^\p{L}\p{N}_' -]"#, with: "", options: .regularExpression)
            t = t.trimmingCharacters(in: CharacterSet(charactersIn: " -'"))
            t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            if t.isEmpty || buoni.contains(t) { continue }
            if lingua.paroleEscluse.contains(t) || t.count < 3 || t.split(separator: " ").count > 3
                || fuoriDizionario(t, lingua: lingua) {
                scartati.append(t)
                continue
            }
            buoni.append(t)
        }
        return (buoni, scartati)
    }

    /// Parole chiave finali (al massimo 15, senza doppioni tra campi) e parole scartate.
    public static func paroleChiave(_ r: Risposta, lingua: Lingua) -> (parole: [String], scartate: [String]) {
        var parole: [String] = [], scartate: [String] = []
        for c in categorie {
            let (buoni, cattivi) = termini(r.campi[c] ?? [], lingua: lingua)
            let nuovi = buoni.filter { !parole.contains($0) }.prefix(max(0, massimoParole - parole.count))
            parole += nuovi
            scartate += cattivi
        }
        return (parole, scartate)
    }
}
