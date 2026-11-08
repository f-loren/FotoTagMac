import Foundation
import Testing
@testable import FotoTagCore

@Suite struct ArchivioTests {
    /// Cartella di prova con due JPG diversi e un database vuoto.
    static func prepara() throws -> (dir: URL, foto: URL, archivio: Archivio) {
        let dir = try cartellaTemporanea()
        let foto = dir.appendingPathComponent("Rullino 1")
        try FileManager.default.createDirectory(at: foto, withIntermediateDirectories: true)
        try immagineDiProva(foto.appendingPathComponent("a.jpg"), tipo: .jpeg)
        try immagineDiProva(foto.appendingPathComponent("b.jpg"), tipo: .jpeg, tinta: 120)
        return (dir, foto, try Archivio(url: dir.appendingPathComponent("prova.db")))
    }

    static func analizza(_ a: Archivio, _ cartella: Int64) throws {
        for f in try a.foto(cartella: cartella) {
            try a.salvaAnalisi(f.id, parole: ["mare", f.nome], didascalia: "", scartate: [], risposta: "{}", secondi: 1,
                               percorso: f.percorso, lingua: "it")
        }
    }

    @Test func improntaStabileEDiversaPerFile() throws {
        let (dir, foto, _) = try Self.prepara()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = Immagini.impronta(foto.appendingPathComponent("a.jpg"))
        #expect(a != nil)
        #expect(a == Immagini.impronta(foto.appendingPathComponent("a.jpg")))
        #expect(a != Immagini.impronta(foto.appendingPathComponent("b.jpg")))
    }

    @Test func codeDaFareSuTuttoLArchivio() throws {
        let (dir, foto, archivio) = try Self.prepara()
        defer { try? FileManager.default.removeItem(at: dir) }
        let c = try archivio.aggiungiCartella(foto.path, segnalibro: nil)
        try archivio.sincronizza(cartella: c, file: Immagini.fotoNellaCartella(foto))
        try Self.analizza(archivio, c)
        #expect(try archivio.contaDaFare() == [.daRivedere: 2, .daScrivere: 0, .errori: 0])
        let (a, b) = try { let f = try archivio.foto(cartella: c); return (f[0], f[1]) }()
        try archivio.salvaRevisione(a.id, parole: a.parole, didascalia: "", stato: .rivista)
        try archivio.segnaErrore(b.id, messaggio: "prova")
        #expect(try archivio.contaDaFare() == [.daRivedere: 0, .daScrivere: 1, .errori: 1])
        #expect(try archivio.foto(daFare: .daScrivere).map(\.id) == [a.id])
        try archivio.salvaScrittura(a.id, parole: a.parole, gerarchia: [], didascalia: nil, file: [a.percorso])
        #expect(try archivio.contaDaFare()[.daScrivere] == 0)
    }

    @Test func cartellaRinominataRitrovataConLImpronta() throws {
        let (dir, foto, archivio) = try Self.prepara()
        defer { try? FileManager.default.removeItem(at: dir) }
        let c = try archivio.aggiungiCartella(foto.path, segnalibro: nil)
        try archivio.sincronizza(cartella: c, file: Immagini.fotoNellaCartella(foto))
        try archivio.completaImpronte(cartella: c)
        try Self.analizza(archivio, c)

        let nuova = dir.appendingPathComponent("Rullino 1 - mare")
        try FileManager.default.moveItem(at: foto, to: nuova)
        let c2 = try archivio.aggiungiCartella(nuova.path, segnalibro: nil)
        try archivio.sincronizza(cartella: c2, file: Immagini.fotoNellaCartella(nuova))
        let dopo = try archivio.foto(cartella: c2)
        #expect(dopo.map(\.nome) == ["a.jpg", "b.jpg"])
        #expect(dopo.allSatisfy { $0.stato == .proposta && $0.parole.contains("mare") })
        #expect(try archivio.foto(cartella: c).isEmpty)
    }

    @Test func copiaNonRubaLAnalisi() throws {
        let (dir, foto, archivio) = try Self.prepara()
        defer { try? FileManager.default.removeItem(at: dir) }
        let c = try archivio.aggiungiCartella(foto.path, segnalibro: nil)
        try archivio.sincronizza(cartella: c, file: Immagini.fotoNellaCartella(foto))
        try archivio.completaImpronte(cartella: c)
        try Self.analizza(archivio, c)
        let copia = dir.appendingPathComponent("Copia")
        try FileManager.default.copyItem(at: foto, to: copia)
        let c2 = try archivio.aggiungiCartella(copia.path, segnalibro: nil)
        try archivio.sincronizza(cartella: c2, file: Immagini.fotoNellaCartella(copia))
        #expect(try archivio.foto(cartella: c2).allSatisfy { $0.stato == .daAnalizzare })
        #expect(try archivio.foto(cartella: c).allSatisfy { $0.stato == .proposta })
    }

    @Test func riconnettiCartella() throws {
        let (dir, foto, archivio) = try Self.prepara()
        defer { try? FileManager.default.removeItem(at: dir) }
        let c = try archivio.aggiungiCartella(foto.path, segnalibro: nil)
        try archivio.sincronizza(cartella: c, file: Immagini.fotoNellaCartella(foto))
        try archivio.completaImpronte(cartella: c)
        try Self.analizza(archivio, c)
        let nuova = dir.appendingPathComponent("Spostata")
        try FileManager.default.moveItem(at: foto, to: nuova)
        try archivio.riconnetti(cartella: c, a: nuova.path, segnalibro: nil)
        #expect(try archivio.cartelle().map(\.percorso) == [nuova.path])
        let f = try archivio.foto(cartella: c)
        #expect(f.map(\.percorso) == [nuova.appendingPathComponent("a.jpg").path, nuova.appendingPathComponent("b.jpg").path])
        #expect(f.allSatisfy { $0.stato == .proposta })
    }

    @Test func riconnettiSuUnaCartellaGiaAggiunta() throws {
        let (dir, foto, archivio) = try Self.prepara()
        defer { try? FileManager.default.removeItem(at: dir) }
        let c = try archivio.aggiungiCartella(foto.path, segnalibro: nil)
        try archivio.sincronizza(cartella: c, file: Immagini.fotoNellaCartella(foto))
        try archivio.completaImpronte(cartella: c)
        try Self.analizza(archivio, c)
        let nuova = dir.appendingPathComponent("Spostata")
        try FileManager.default.moveItem(at: foto, to: nuova)
        // aggiunta di nuovo prima di riconnettere, con le impronte cancellate (come le foto di una versione precedente)
        try archivio.query("update foto set impronta = null")
        let c2 = try archivio.aggiungiCartella(nuova.path, segnalibro: nil)
        try archivio.query("insert into foto(cartella_id, percorso) values(?, ?)", [.intero(c2), .testo(nuova.appendingPathComponent("a.jpg").path)])
        try archivio.riconnetti(cartella: c, a: nuova.path, segnalibro: nil)
        #expect(try archivio.cartelle().map(\.id) == [c2])
        #expect(try archivio.foto(cartella: c2).allSatisfy { $0.stato == .proposta })
        #expect(try archivio.foto(cartella: c2).count == 2)
    }
}

@Suite struct SottocartelleTests {
    @Test func fotoNelleSottocartelleInOrdine() throws {
        let dir = try cartellaTemporanea()
        defer { try? FileManager.default.removeItem(at: dir) }
        for (sotto, nome) in [("", "z.jpg"), ("Rullino 10", "a.jpg"), ("Rullino 2", "b.jpg"), ("Rullino 2/scelte", "c.JPG"), (".nascosta", "d.jpg")] {
            let d = dir.appendingPathComponent(sotto)
            try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
            try immagineDiProva(d.appendingPathComponent(nome), tipo: .jpeg)
        }
        let tutte = Immagini.fotoNellaCartella(dir).map { String($0.path.dropFirst(dir.path.count + 1)) }
        #expect(tutte == ["z.jpg", "Rullino 2/b.jpg", "Rullino 2/scelte/c.JPG", "Rullino 10/a.jpg"])
        #expect(Immagini.fotoNellaCartella(dir, sottocartelle: false).map(\.lastPathComponent) == ["z.jpg"])

        // cartella madre aggiunta dopo una sottocartella: le foto della sottocartella si vedono in tutte e due
        let archivio = try Archivio(url: dir.appendingPathComponent("prova.db"))
        let figlia = try archivio.aggiungiCartella(dir.appendingPathComponent("Rullino 2").path, segnalibro: nil)
        try archivio.sincronizza(cartella: figlia, file: Immagini.fotoNellaCartella(dir.appendingPathComponent("Rullino 2")))
        let madre = try archivio.aggiungiCartella(dir.path, segnalibro: nil)
        try archivio.sincronizza(cartella: madre, file: Immagini.fotoNellaCartella(dir))
        #expect(try archivio.foto(cartella: madre).count == 4)
        #expect(try archivio.foto(cartella: figlia).count == 2)
        let n = try archivio.conteggi()
        #expect(n[madre]?.totale == 4 && n[figlia]?.totale == 2)
    }

    @Test func cartelleRecenti() throws {
        let dir = try cartellaTemporanea()
        defer { try? FileManager.default.removeItem(at: dir) }
        let archivio = try Archivio(url: dir.appendingPathComponent("prova.db"))
        let a = try archivio.aggiungiCartella(dir.appendingPathComponent("a").path, segnalibro: nil)
        let b = try archivio.aggiungiCartella(dir.appendingPathComponent("b").path, segnalibro: nil)
        #expect(try archivio.cartelle().allSatisfy { $0.usataIl == nil })
        try archivio.segnaUsata(b)
        try archivio.segnaUsata(a)  // millisecondi: due usi nello stesso secondo restano in ordine
        let recenti = try archivio.cartelle().filter { $0.usataIl != nil }.sorted { $0.usataIl! > $1.usataIl! }.map(\.id)
        #expect(recenti == [a, b])
        try archivio.cancellaRecenti()
        #expect(try archivio.cartelle().count == 2)
        #expect(try archivio.cartelle().allSatisfy { $0.usataIl == nil })
    }

    @Test func sottocartelleCorniciSaltate() throws {
        let dir = try cartellaTemporanea()
        defer { try? FileManager.default.removeItem(at: dir) }
        for (sotto, nome) in [("", "a.jpg"), ("sub", "b.jpg"), ("cornici", "c.jpg"), ("sub/Cornici", "d.jpg"), ("JPG", "e.jpg")] {
            let d = dir.appendingPathComponent(sotto)
            try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
            try immagineDiProva(d.appendingPathComponent(nome), tipo: .jpeg)
        }
        let saltate = Profilo.lorenzo.sottocartelleSaltate
        #expect(Profilo.generico.sottocartelleSaltate.isEmpty)  // regola personale: solo nel suo profilo
        let elenco = Immagini.fotoNellaCartella(dir, saltate: saltate).map { String($0.path.dropFirst(dir.path.count + 1)) }
        #expect(elenco == ["a.jpg", "JPG/e.jpg", "sub/b.jpg"])  // «JPG» resta: è in cartelleIgnorate, non tra le saltate

        // database con le copie già elencate (build 44): via quelle da analizzare, restano quelle analizzate
        let archivio = try Archivio(url: dir.appendingPathComponent("prova.db"))
        let c = try archivio.aggiungiCartella(dir.path, segnalibro: nil)
        try archivio.sincronizza(cartella: c, file: Immagini.fotoNellaCartella(dir))
        let d = try #require(try archivio.foto(cartella: c).first { $0.nome == "d.jpg" })
        try archivio.salvaAnalisi(d.id, parole: ["mare"], didascalia: "", scartate: [], risposta: "{}", secondi: 1,
                                  percorso: d.percorso, lingua: "it")
        let esito = try archivio.togliSaltate(cartella: c, saltate: saltate)
        #expect(esito.tolte == 1 && esito.analizzate == 1)
        #expect(try archivio.foto(cartella: c).map(\.nome).sorted() == ["a.jpg", "b.jpg", "d.jpg", "e.jpg"])
    }
}
