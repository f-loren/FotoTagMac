import Foundation
import Testing
@testable import FotoTagCore

@Suite struct SuggerimentiTests {
    @Test func conteggiUnaVoltaPerFoto() {
        let c = Suggerimenti.conta([["piazza", "piazza", "uomo"], ["piazza"], ["nebbia"]])
        #expect(c == ["piazza": 2, "uomo": 1, "nebbia": 1])
    }

    @Test func frequentiSenzaQuelliGiaPresenti() {
        let c = ["piazza": 5, "uomo": 5, "nebbia": 3, "cane": 1, "bici": 1, "sole": 2]
        #expect(Suggerimenti.frequenti(c, esclusi: ["uomo"], massimo: 3) == ["piazza", "nebbia", "sole"])
        #expect(Suggerimenti.frequenti(c, esclusi: [], massimo: 2) == ["piazza", "uomo"])  // pari: ordine alfabetico
    }

    @Test func completamentoPrimaChiIniziaPoiChiContiene() {
        let c = ["piazza": 212, "pianta": 30, "spiaggia": 400, "piano": 30, "copia": 2, "pia": 1]
        let r = Suggerimenti.completa("Pia", conteggi: c, esclusi: ["pianta"])
        #expect(r.map(\.tag) == ["piazza", "piano", "spiaggia", "copia"])  // «pia» stesso non si propone
        #expect(r[0].foto == 212)
        #expect(Suggerimenti.completa("  ", conteggi: c, esclusi: []).isEmpty)
        #expect(Suggerimenti.completa("p", conteggi: c, esclusi: [], massimo: 2).count == 2)
    }

    @Test func manualiNonSonoNellaRisposta() {
        let r = #"{"soggetti":["uomo"],"luogo":["piazza"],"didascalia":"uomo in piazza"}"#
        #expect(Suggerimenti.manuali(parole: ["uomo", "piazza", "zio carlo"], risposta: r) == ["zio carlo"])
        #expect(Suggerimenti.manuali(parole: ["uomo"], risposta: nil).isEmpty)
    }

    @Test func conteggiDallArchivio() throws {
        let dir = try cartellaTemporanea()
        defer { try? FileManager.default.removeItem(at: dir) }
        let foto = dir.appendingPathComponent("r")
        try FileManager.default.createDirectory(at: foto, withIntermediateDirectories: true)
        for n in ["a", "b", "c"] { try immagineDiProva(foto.appendingPathComponent("\(n).jpg"), tipo: .jpeg) }
        let archivio = try Archivio(url: dir.appendingPathComponent("prova.db"))
        let c = try archivio.aggiungiCartella(foto.path, segnalibro: nil)
        try archivio.sincronizza(cartella: c, file: Immagini.fotoNellaCartella(foto))
        let f = try archivio.foto(cartella: c)
        let risposta = #"{"luogo":["piazza"],"soggetti":["uomo"]}"#
        for (i, x) in f.enumerated() {
            try archivio.salvaAnalisi(x.id, parole: ["piazza", "uomo"] + (i == 0 ? ["zio carlo"] : []), didascalia: "", scartate: ["xyz"],
                                      risposta: risposta, secondi: 1, percorso: "libero", lingua: "it")
        }
        try archivio.salvaRevisione(f[0].id, parole: ["piazza", "uomo", "zio carlo"], didascalia: "", stato: .rivista)
        let t = try archivio.tagPerSuggerimenti()
        // confermata: tutti i suoi tag; da rivedere: solo quelli aggiunti a mano (nessuno); le scartate mai
        #expect(t.archivio == ["piazza": 1, "uomo": 1, "zio carlo": 1])
        #expect(t.manuali == ["zio carlo": 1])
    }
}
