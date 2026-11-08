import Foundation

/// Suggerimenti di tag nel pannello: dalle foto vicine, dai tag aggiunti a mano, completamento mentre si scrive.
public enum Suggerimenti {
    /// In quante foto compare ogni tag (una volta per foto).
    public static func conta(_ liste: [[String]]) -> [String: Int] {
        var c: [String: Int] = [:]
        for l in liste { for t in Set(l) { c[t, default: 0] += 1 } }
        return c
    }

    /// I più frequenti che la foto non ha ancora; a parità di frequenza, in ordine alfabetico.
    public static func frequenti(_ conteggi: [String: Int], esclusi: Set<String>, massimo: Int = 5) -> [String] {
        conteggi.filter { !esclusi.contains($0.key) }
            .sorted { ($1.value, $0.key) < ($0.value, $1.key) }
            .prefix(massimo).map(\.key)
    }

    /// Mentre si scrive: prima i tag che iniziano con il testo, poi quelli che lo contengono; ognuno per frequenza.
    public static func completa(_ testo: String, conteggi: [String: Int], esclusi: Set<String>, massimo: Int = 6) -> [(tag: String, foto: Int)] {
        let q = testo.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        let candidati = conteggi.filter { !esclusi.contains($0.key) && $0.key != q && $0.key.contains(q) }
        return candidati.sorted { a, b in
            let (pa, pb) = (a.key.hasPrefix(q), b.key.hasPrefix(q))
            if pa != pb { return pa }
            return (b.value, a.key) < (a.value, b.key)
        }
        .prefix(massimo).map { ($0.key, $0.value) }
    }

    /// Tag aggiunti a mano: quelli che non compaiono nella risposta salvata del modello.
    /// shortcut: confronto sul testo grezzo della risposta (non la rilegge col JSON); basta per i conteggi.
    public static func manuali(parole: [String], risposta: String?) -> [String] {
        guard let r = risposta?.lowercased(), !r.isEmpty else { return [] }
        return parole.filter { !r.contains($0.lowercased()) }
    }
}
