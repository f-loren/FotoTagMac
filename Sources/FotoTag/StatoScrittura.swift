import FotoTagCore
import SwiftUI

/// Scrittura dei tag nei file: cosa scrivere, conferma, esecuzione, esito.
extension Stato {
    /// Foto da scrivere: con più foto selezionate, quelle riviste della selezione;
    /// altrimenti tutte le riviste della cartella mai scritte o cambiate dopo l'ultima scrittura.
    var daScrivere: [FotoRecord] {
        if selezione.count > 1 { return selezionate.filter { $0.stato == .rivista } }
        return foto.filter { $0.stato == .rivista && ($0.scrittaIl == nil || $0.modificataDopo) }
    }

    func chiediScrittura(_ quali: [FotoRecord]) {
        let riviste = quali.filter { $0.stato == .rivista }
        guard !riviste.isEmpty else {
            messaggio = String(localized: "Si scrivono nei file solo le foto confermate: conferma i tag prima di scrivere.")
            return
        }
        scrittura = LavoroScrittura(foto: riviste)
    }

    /// Parole chiave gerarchiche come nel prototipo: Contenuto|categoria|parola, o Contenuto|manuale|parola.
    func gerarchia(_ f: FotoRecord, risposta: String?) -> [String] {
        let campi = risposta.flatMap(leggiRisposta)?.campi ?? [:]
        return f.parole.map { p in
            let c = categorie.first { cat in (campi[cat] ?? []).contains { $0.lowercased().trimmingCharacters(in: .whitespaces) == p } }
            return "\(lingua.t("Contenuto"))|\(lingua.t(c ?? "manuale"))|\(p)"
        }
    }

    func unici(_ l: [String]) -> [String] {
        var visti = Set<String>()
        return l.filter { visti.insert($0).inserted }
    }

    func eseguiScrittura() {
        guard var s = scrittura, !s.inCorso, let archivio else { return }
        s.inCorso = true
        scrittura = s
        let copia: URL? = copiaDiSicurezza
            ? FotoTagCore.Scrittura.cartellaCopie
                .appendingPathComponent(Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeSeparator(.omitted)))
            : nil
        let nome = FotoTagCore.Scrittura.NomeSidecar(rawValue: nomeSidecar) ?? .lightroom
        Diario.info("scrittura nei file di \(s.foto.count) foto, copia di sicurezza: \(copia != nil ? "sì" : "no")")
        Task {
            var fermeDiFila = 0  // foto di fila che il disco in cloud non ha restituito
            for f in s.foto {
                let dati = (try? archivio.datiScrittura(f.id)) ?? (risposta: nil, parole: [], gerarchia: [], didascalia: nil)
                // come il prototipo: prima i tag fissi (origine, data, pellicola…), poi quelli del contenuto
                let fissi = f.fissi
                var r = FotoTagCore.Scrittura.Richiesta(
                    file: f.url, parole: unici((fissi?.parole(lingua) ?? []) + f.parole), didascalia: f.didascalia,
                    gerarchia: (fissi?.gerarchia(lingua) ?? []) + gerarchia(f, risposta: dati.risposta),
                    paroleGiaScritte: dati.parole, gerarchiaGiaScritta: dati.gerarchia, didascaliaGiaScritta: dati.didascalia)
                // sidecar accanto all'originale collegato solo se il collegamento è sicuro o scelto a mano (come il prototipo)
                r.raw = (f.rawManuale || f.rawLivello == .sicuro) ? f.rawURL : nil
                let richiesta = r
                var riportate: [URL] = []  // dal cloud: si liberano dopo la scrittura, mai durante (D62)
                do {
                    // l'analisi libera le foto del disco in cloud: leggerle bloccherebbe senza scadenza.
                    // Dopo la scrittura si liberano appena il disco in cloud le ha caricate (D62)
                    let daPortare = await Task.detached(priority: .utility) { FotoTagCore.Scrittura.daPortareSulMac(richiesta, nomeSidecar: nome) }.value
                    riportate = daPortare.filter(Immagini.daScaricare)
                    for u in daPortare where await !Immagini.scarica(u, attesa: 60) {
                        fermeDiFila += 1
                        throw NSError(domain: "FotoTag", code: 3, userInfo: [NSLocalizedDescriptionKey:
                            String(localized: "\(u.lastPathComponent) non è ancora stata scaricata dal disco in cloud: non è stata modificata")])
                    }
                    fermeDiFila = 0
                    let esito = try await Task.detached(priority: .userInitiated) { try FotoTagCore.Scrittura.scrivi(r, copiaDiSicurezza: copia, nomeSidecar: nome) }.value
                    try archivio.salvaScrittura(f.id, parole: r.parole, gerarchia: r.gerarchia, didascalia: esito.didascaliaScritta,
                                                file: esito.fileScritti.map(\.path))
                    scrittura?.scritte += 1
                    scrittura?.riuscite.insert(f.id)
                    dimenticaAnnulla([f.id])  // scritta nei file: non si annulla (c'è la copia di sicurezza)
                    scrittura?.fileScritti += esito.fileScritti.count
                    scrittura?.avvisi += esito.avvisi
                } catch {
                    scrittura?.errori.append(error.localizedDescription)
                    Diario.errore("scrittura: \(error.localizedDescription)")
                }
                Immagini.liberaQuandoCaricate(riportate)
                scrittura?.fatte += 1
                if fermeDiFila >= 3 {
                    scrittura?.errori.append(String(localized: "Il disco in cloud non risponde: la scrittura si è fermata dopo \(scrittura?.fatte ?? 0) foto di \(s.foto.count)."))
                    break
                }
            }
            scrittura?.inCorso = false
            Diario.info("scrittura finita: \(scrittura?.scritte ?? 0) foto, \(scrittura?.fileScritti ?? 0) file, \(scrittura?.errori.count ?? 0) errori")
            scrittura?.finita = true
            if let copia { scrittura?.copia = copia }
            ricaricaFoto()
            aggiornaConteggi()  // «Da scrivere» nella barra laterale
            Immagini.liberaCaricate()
        }
    }
}

/// Stato del foglio di conferma/scrittura.
struct LavoroScrittura: Identifiable {
    let id = UUID()
    var foto: [FotoRecord]
    var riuscite: Set<FotoRecord.ID> = []  // scritte e rilette: la loro riga ha la spunta (D67)
    var inCorso = false
    var finita = false
    var fatte = 0
    var scritte = 0
    var fileScritti = 0
    var avvisi: [String] = []
    var errori: [String] = []
    var copia: URL?

    /// Originali che ricevono i tag (sidecar .xmp accanto ai RAW, o dentro le scansioni).
    var raw: [URL] {
        foto.compactMap { f in (f.rawManuale || f.rawLivello == .sicuro) ? f.rawURL : FotoTagCore.Scrittura.rawAccanto(f.url) }
    }
    /// Originali collegati ma non abbastanza sicuri: non ricevono nulla.
    var rawNonSicuri: Int { foto.filter { $0.raw != nil && !$0.rawManuale && $0.rawLivello != .sicuro }.count }
    static func inCloud(_ p: String) -> Bool { p.contains("/Library/CloudStorage/") || p.contains("/Mobile Documents/") }
    /// Vero se qualche file sta su un disco in cloud (BeeStation, iCloud…): si modificano gli originali sincronizzati.
    var inCloud: Bool { foto.contains { LavoroScrittura.inCloud($0.percorso) } || raw.contains { LavoroScrittura.inCloud($0.path) } }
}
