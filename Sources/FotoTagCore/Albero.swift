import Foundation

/// Un nodo dell'albero delle cartelle nella barra laterale.
public struct NodoAlbero: Identifiable, Hashable, Sendable {
    public var id: String { percorso }
    public var percorso: String
    public var nome: String
    /// false se il disco della radice non è collegato: foto e tag restano, la riga è spenta
    public var collegata = true
    public var figli: [NodoAlbero]
}

/// Una riga visibile della barra laterale: il nodo e quanto è rientrato.
public struct RigaAlbero: Identifiable, Hashable, Sendable {
    public var id: String { nodo.id }
    public var nodo: NodoAlbero
    public var livello: Int
    public var aperto: Bool
}

/// Albero delle cartelle con foto: una radice per ogni accesso dato dall'utente e, sotto, il percorso vero,
/// un livello per riga. Una cartella sta sotto l'accesso più specifico che la contiene.
public enum Albero {
    /// Disco o cartella utente che contiene un percorso (per ricavare gli accessi delle vecchie cartelle).
    public static func radice(di percorso: String, home: String) -> String {
        if percorso == home || percorso.hasPrefix(home + "/") { return home }
        if percorso.hasPrefix("/Volumes/"), let disco = percorso.dropFirst("/Volumes/".count).split(separator: "/").first {
            return "/Volumes/" + disco
        }
        return "/"
    }

    /// «BeeStation-Account» → «BeeStation» (le cartelle di CloudStorage sono «Fornitore-account»).
    static func fornitore(_ cartella: String) -> String {
        cartella.split(separator: "-", maxSplits: 1).first.map(String.init) ?? cartella
    }

    static func base(_ r: String) -> String { r.hasSuffix("/") ? r : r + "/" }

    /// Il percorso è la cartella `r` o sta dentro di lei.
    public static func contiene(_ r: String, _ percorso: String) -> Bool { percorso == r || percorso.hasPrefix(base(r)) }

    static func nomeRadice(_ r: String, home: String) -> String {
        if r == "/" { return String(localized: "Disco di avvio") }
        let nome = (r as NSString).lastPathComponent
        return r.hasPrefix(home + "/Library/CloudStorage/") ? fornitore(nome) : nome
    }

    public static func costruisci(_ cartelle: [String], radici: [String], home: String,
                                  collegata: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> [NodoAlbero] {
        let piuSpecifiche = radici.sorted { $0.count > $1.count }
        var rami: [String: Ramo] = [:]
        for r in radici { rami[r] = Ramo() }
        for p in Set(cartelle) {
            guard let r = piuSpecifiche.first(where: { contiene($0, p) }), var q = rami[r] else { continue }
            for c in p.dropFirst(r.count).split(separator: "/").map(String.init) {
                if q.figli[c] == nil { q.figli[c] = Ramo() }
                q = q.figli[c]!
            }
        }
        func ordine(_ p: String) -> Int {
            p == home ? 0 : p.hasPrefix("/Volumes/") ? 1 : p.hasPrefix(home + "/Library/CloudStorage/") ? 2 : 3
        }
        return radici.sorted { (ordine($0), $0.localizedLowercase) < (ordine($1), $1.localizedLowercase) }.map { r in
            nodo(r, nome: nomeRadice(r, home: home), rami[r]!, collegata: collegata(r))
        }
    }

    /// Le righe da mostrare, in ordine: ogni nodo e, se è aperto, i suoi figli.
    public static func righe(_ nodi: [NodoAlbero], livello: Int = 0, aperto: (NodoAlbero, Int) -> Bool) -> [RigaAlbero] {
        nodi.flatMap { n in
            let a = aperto(n, livello)
            return [RigaAlbero(nodo: n, livello: livello, aperto: a)] + (a ? righe(n.figli, livello: livello + 1, aperto: aperto) : [])
        }
    }

    /// Un livello dell'albero mentre si costruisce: con migliaia di cartelle non si può ripassarle tutte a ogni nodo.
    final class Ramo {
        var figli: [String: Ramo] = [:]
    }

    static func nodo(_ percorso: String, nome: String, _ ramo: Ramo, collegata: Bool) -> NodoAlbero {
        let figli = ramo.figli.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { n in
            nodo(base(percorso) + n, nome: n, ramo.figli[n]!, collegata: collegata)
        }
        return NodoAlbero(percorso: percorso, nome: nome, collegata: collegata, figli: figli)
    }
}
