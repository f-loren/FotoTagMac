import Foundation
import Testing
@testable import FotoTagCore

@Suite struct IndicizzatoreTests {
    /// Crea file finti (per l'elenco conta solo il nome).
    func crea(_ dir: URL, _ percorsi: [String]) throws {
        for p in percorsi {
            let u = dir.appendingPathComponent(p)
            try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: u)
        }
    }

    func relative(_ r: Indicizzatore.Risultato) -> [String] {
        r.perCartella.keys.map { String($0.dropFirst(r.radice.count)) }.sorted()
    }

    @Test func iPNGNonSonoFoto() throws {
        let dir = try cartellaTemporanea()
        defer { try? FileManager.default.removeItem(at: dir) }
        try crea(dir, ["giochi/icona.png", "foto/a.jpg", "foto/b.PNG", "foto/c.heic", "foto/d.tiff", "foto/e.ORF"])
        let r = Indicizzatore.percorri(dir, saltate: [])
        #expect(relative(r) == ["/foto"])
        #expect(r.foto == 4)
    }

    /// Una cartella dentro un accesso già dato non diventa un secondo accesso; il disco in cloud in Library sì.
    @Test func cartellaGiaCompresa() {
        let accessi = ["/Users/a", "/Volumes/Disco"]
        #expect(Indicizzatore.compresa("/Users/a/Foto/2025", in: accessi))
        #expect(Indicizzatore.compresa("/Volumes/Disco/Foto", in: accessi))
        #expect(!Indicizzatore.compresa("/Volumes/Altro", in: accessi))
        #expect(!Indicizzatore.compresa("/Users/a", in: accessi))
        #expect(!Indicizzatore.compresa("/Users/a/Library/CloudStorage/BeeStation-x", in: accessi))
    }

    /// I PNG già nell'indice escono se mai analizzati, restano se c'è del lavoro; le foto tornano alla loro cartella.
    @Test func pulisceFormatiEVecchieCartelle() throws {
        let dir = try cartellaTemporanea()
        defer { try? FileManager.default.removeItem(at: dir) }
        try crea(dir, ["m/s/a.jpg", "m/b.png", "m/c.png"])
        let a = try Archivio(url: dir.appendingPathComponent("prova.db"))
        let madre = try a.aggiungiCartella(dir.appendingPathComponent("m").path, segnalibro: nil)
        let vecchie = ["m/s/a.jpg", "m/b.png", "m/c.png"].map { dir.appendingPathComponent($0) }
        try a.sincronizza(cartella: madre, file: vecchie)
        let id = { (nome: String) in try a.foto(cartella: madre).first { $0.nome == nome }!.id }
        try a.salvaAnalisi(try id("c.png"), parole: ["mare"], didascalia: "", scartate: [], risposta: "", secondi: 1, percorso: "", lingua: "it")

        try a.applicaIndice(Indicizzatore.percorri(dir, saltate: []), profilo: "generico", saltate: [])

        let foto = try a.foto(cartella: madre)
        #expect(foto.map(\.nome).sorted() == ["a.jpg", "c.png"])
        let figlia = try a.cartelle().first { $0.nome == "s" }!
        #expect(foto.first { $0.nome == "a.jpg" }!.cartellaID == figlia.id)
        #expect(try a.cartelle().first { $0.id == madre }!.nFoto == 1)  // il PNG analizzato tiene la cartella nell'elenco
    }

    @Test func discoStaccatoDuranteIlGiro() throws {
        let dir = try cartellaTemporanea()
        defer { try? FileManager.default.removeItem(at: dir) }
        try crea(dir, ["disco/Foto/a.jpg"])
        let disco = dir.appendingPathComponent("disco")
        let a = try Archivio(url: dir.appendingPathComponent("prova.db"))
        let r = Indicizzatore.percorri(disco, saltate: [])
        try a.applicaIndice(r, profilo: "generico", saltate: [])
        var vuoto = r
        vuoto.perCartella = [:]
        try FileManager.default.removeItem(at: disco)

        try a.applicaIndice(vuoto, profilo: "generico", saltate: [])

        let c = try #require(try a.cartelle().first { $0.nome == "Foto" })
        #expect(c.nFoto == 1)
        #expect(try a.foto(cartella: c.id).count == 1)
    }

    /// Il giro della cartella utente non tocca un disco in cloud che sta sotto di lei, anche se è staccato.
    @Test func accessoAnnidatoNonSiTocca() throws {
        let dir = try cartellaTemporanea()
        defer { try? FileManager.default.removeItem(at: dir) }
        try crea(dir, ["casa/a.jpg", "casa/Library/Cloud/b.jpg"])
        let a = try Archivio(url: dir.appendingPathComponent("prova.db"))
        let casa = dir.appendingPathComponent("casa"), cloud = casa.appendingPathComponent("Library/Cloud")
        try a.applicaIndice(Indicizzatore.percorri(cloud, saltate: []), profilo: "generico", saltate: [])
        try FileManager.default.removeItem(at: cloud)

        try a.applicaIndice(Indicizzatore.percorri(casa, saltate: []), profilo: "generico", saltate: [], annidate: [cloud.path])

        let c = try #require(try a.cartelle().first { $0.percorso == cloud.path })
        #expect(c.nFoto == 1)
        #expect(try a.foto(cartella: c.id).map(\.nome) == ["b.jpg"])
    }

    /// Una foto su un disco staccato non è scomparsa: una copia altrove non ne prende l'analisi.
    @Test func discoStaccatoNonCedeLAnalisi() throws {
        let dir = try cartellaTemporanea()
        defer { try? FileManager.default.removeItem(at: dir) }
        let copia = dir.appendingPathComponent("copia.jpg")
        try immagineDiProva(copia, tipo: .jpeg)
        let impronta = try #require(Immagini.impronta(copia))
        let a = try Archivio(url: dir.appendingPathComponent("prova.db"))
        let staccato = try a.aggiungiCartella("/Volumes/FotoTagStaccato/Foto", segnalibro: nil)
        try a.sincronizza(cartella: staccato, file: [URL(fileURLWithPath: "/Volumes/FotoTagStaccato/Foto/a.jpg")])
        let id = try #require(try a.foto(cartella: staccato).first?.id)
        try a.salvaImpronta(id, impronta)

        let qui = try a.aggiungiCartella(dir.path, segnalibro: nil)
        try a.sincronizza(cartella: qui, file: [copia])

        #expect(try a.foto(cartella: staccato).map(\.id) == [id])
        #expect(try a.foto(cartella: qui).map(\.nome) == ["copia.jpg"])
    }

    @Test func volumeDaProporre() {
        #expect(Indicizzatore.daProporre("/Volumes/SD", accessi: ["/Volumes/Disco"], ignorati: []))
        #expect(!Indicizzatore.daProporre("/Volumes/Disco", accessi: ["/Volumes/Disco"], ignorati: []))
        #expect(!Indicizzatore.daProporre("/Volumes/SD", accessi: [], ignorati: ["/Volumes/SD"]))
    }

    @Test func accessoAllaRadiceDelDisco() {
        let albero = Albero.costruisci(["/Users/a/Foto"], radici: ["/"], home: "/Users/a", collegata: { _ in true })
        #expect(albero.map(\.nome) == ["Disco di avvio"])
        #expect(albero[0].figli[0].percorso == "/Users")
        #expect(Indicizzatore.compresa("/Users", in: ["/"]))
        #expect(!Indicizzatore.compresa("/Volumes/Disco", in: ["/"]))
    }

    @Test func saltaSoloLeCoseTecniche() throws {
        let dir = try cartellaTemporanea()
        defer { try? FileManager.default.removeItem(at: dir) }
        try crea(dir, ["a.jpg", "2025/JPG/b.JPG", "2025/RAW/c.NEF", "2025/scans/d.tif", "2025/h/e.heic", "molto/in/fondo/a/piu/livelli/f.dng",
                       "2025/cornici/g.jpg", "2025/Cornice/h.jpg", ".nascosta/i.jpg", "Library/j.jpg", "x/node_modules/k.jpg",
                       "x/DerivedData/l.jpg", "x/_build/m.jpg", "Foto.photoslibrary/n.jpg", "App.app/o.jpg", "Anteprime/p.jpg", "doc/q.txt"])
        let r = Indicizzatore.percorri(dir, saltate: Profilo.lorenzo.sottocartelleSaltate, escluse: [dir.appendingPathComponent("Anteprime").path])
        #expect(r.letta)
        #expect(relative(r) == ["", "/2025/JPG", "/2025/RAW", "/2025/h", "/2025/scans", "/molto/in/fondo/a/piu/livelli"].sorted())
    }

    /// Il profilo generico non salta nessuna cartella per nome.
    @Test func genericoNonSaltaNulla() throws {
        let dir = try cartellaTemporanea()
        defer { try? FileManager.default.removeItem(at: dir) }
        try crea(dir, ["Mare/a.jpg", "cornici/b.jpg", "Cornice/c.jpg", "stampe/d.tif"])
        let r = Indicizzatore.percorri(dir, saltate: Profilo.generico.sottocartelleSaltate)
        #expect(relative(r) == ["/Cornice", "/Mare", "/cornici", "/stampe"].sorted())
    }

    @Test func radiceAssenteNonSiLegge() {
        let r = Indicizzatore.percorri(URL(fileURLWithPath: "/non/esiste"), saltate: [])
        #expect(!r.letta && r.perCartella.isEmpty)
    }

    @Test func rawColSuoJpgRestaUnaFotoSola() {
        let f = { (p: String) in Indicizzatore.FileFoto(percorso: p, dimensione: 1, mtime: 1) }
        let s = Indicizzatore.senzaCompagniRAW([f("/c/DSC_1.JPG"), f("/c/DSC_1.NEF"), f("/c/DSC_2.NEF")])
        #expect(s.map(\.percorso) == ["/c/DSC_1.JPG", "/c/DSC_2.NEF"])
    }

    @Test func radiciDiAccesso() {
        let h = "/Users/l"
        #expect(Indicizzatore.radiceAccesso(di: "/Users/l/TagTest-app/x", home: h) == h)
        #expect(Indicizzatore.radiceAccesso(di: "/Volumes/Disco/Foto", home: h) == "/Volumes/Disco")
        #expect(Indicizzatore.radiceAccesso(di: "/Users/l/Library/CloudStorage/BeeStation-Z/Foto/a", home: h) == "/Users/l/Library/CloudStorage/BeeStation-Z")
    }

    func indicizza(_ a: Archivio, _ dir: URL) throws {
        try a.applicaIndice(Indicizzatore.percorri(dir, saltate: ["cornici"]), profilo: "lorenzo", saltate: ["cornici"])
    }

    @Test func aggiornamentoIncrementaleECartellaSparita() throws {
        let dir = try cartellaTemporanea()
        defer { try? FileManager.default.removeItem(at: dir) }
        let radice = dir.appendingPathComponent("disco")
        try crea(radice, ["r1/a.jpg", "r1/b.jpg", "r2/c.nef", "vuota/nota.txt"])
        let a = try Archivio(url: dir.appendingPathComponent("prova.db"))
        try indicizza(a, radice)
        var cartelle = try a.cartelle()
        #expect(cartelle.map(\.nome).sorted() == ["r1", "r2"] && cartelle.allSatisfy { $0.profilo == "lorenzo" })
        #expect(cartelle.first { $0.nome == "r1" }?.nFoto == 2)
        let r1 = try #require(cartelle.first { $0.nome == "r1" })
        var foto = try a.foto(cartella: r1.id)
        #expect(foto.count == 2)

        // un'analisi su a.jpg e un secondo giro: niente doppioni, l'analisi resta
        try a.salvaAnalisi(foto[0].id, parole: ["mare"], didascalia: "", scartate: [], risposta: "{}", secondi: 1, percorso: "libero", lingua: "it")
        try a.salvaImpronta(foto[0].id, "1-x-y")
        try indicizza(a, radice)
        #expect(try a.foto(cartella: r1.id).count == 2)
        #expect(try a.foto(cartella: r1.id).first?.impronta == "1-x-y")  // file invariato: impronta intatta

        // file cambiato: l'impronta si rifà, l'analisi resta
        try Data("più lungo".utf8).write(to: radice.appendingPathComponent("r1/a.jpg"))
        try indicizza(a, radice)
        foto = try a.foto(cartella: r1.id)
        #expect(foto[0].impronta == nil && foto[0].parole == ["mare"])

        // nuova cartella e cornici; r2 sparita (senza analisi) esce; b.jpg sparita esce, a.jpg analizzata sparita resta
        try crea(radice, ["r3/d.jpg", "r1/cornici/e.jpg"])
        try FileManager.default.removeItem(at: radice.appendingPathComponent("r2"))
        try FileManager.default.removeItem(at: radice.appendingPathComponent("r1/a.jpg"))
        try FileManager.default.removeItem(at: radice.appendingPathComponent("r1/b.jpg"))
        try indicizza(a, radice)
        cartelle = try a.cartelle()
        #expect(cartelle.map(\.nome).sorted() == ["r1", "r3"])
        #expect(cartelle.first { $0.nome == "r1" }?.nFoto == 1)  // a.jpg analizzata tiene la cartella nell'elenco
        #expect(try a.foto(cartella: r1.id).map(\.nome) == ["a.jpg"])
    }

    /// Una cartella già registrata con le sue foto, poi l'indice trova tutti i rami: struttura inventata,
    /// nessun nome ha un significato speciale.
    @Test func alberoConTuttiIRami() throws {
        let dir = try cartellaTemporanea()
        defer { try? FileManager.default.removeItem(at: dir) }
        let radice = dir.appendingPathComponent("disco")
        try crea(radice, ["Viaggi/Asia/Nepal/a.jpg", "Viaggi/Asia/Laos/b.jpg", "Viaggi/Sud/Peru/c.jpg",
                          "Viaggi/Scatti/Lima/d.nef", "Viaggi/Varie/e.jpg"])
        let a = try Archivio(url: dir.appendingPathComponent("prova.db"))
        let radiceFoto = radice.appendingPathComponent("Viaggi")
        let vecchia = try a.aggiungiCartella(radiceFoto.path, segnalibro: nil)
        try a.sincronizza(cartella: vecchia, file: Immagini.fotoNellaCartella(radiceFoto))
        var passi = 0
        try a.applicaIndice(Indicizzatore.percorri(radice, saltate: []), profilo: "generico", saltate: []) { _ in passi += 1 }
        #expect(passi == 0)  // meno di 25 cartelle
        let visibili = try a.cartelle().filter { $0.nFoto != 0 }.map(\.percorso)
        func trova(_ n: NodoAlbero, _ fine: String) -> NodoAlbero? {
            n.percorso.hasSuffix(fine) ? n : n.figli.lazy.compactMap { trova($0, fine) }.first
        }
        // Viaggi non ha foto proprie: nell'albero c'è comunque, con un livello per riga
        let f = try #require(Albero.costruisci(visibili, radici: [radice.path], home: "/casa").lazy.compactMap { trova($0, "/Viaggi") }.first)
        #expect(f.figli.map(\.nome) == ["Asia", "Scatti", "Sud", "Varie"])
        #expect(f.figli[0].figli.map(\.nome) == ["Laos", "Nepal"])
    }

    /// Una cartella senza foto proprie si apre con tutte le sottocartelle e non cambia l'albero.
    @Test func cartellaSenzaFotoProprieSiApre() throws {
        let dir = try cartellaTemporanea()
        defer { try? FileManager.default.removeItem(at: dir) }
        let radice = dir.appendingPathComponent("disco")
        try crea(radice, ["Anno/Uno/a.jpg", "Anno/Due/b.jpg", "Anno/Due/Sotto/c.jpg"])
        let a = try Archivio(url: dir.appendingPathComponent("prova.db"))
        try indicizza(a, radice)
        let prima = try a.cartelle().filter { $0.nFoto != 0 }.map(\.percorso)
        let id = try a.aggiungiPassaggio(radice.appendingPathComponent("Anno").path, profilo: "generico")
        #expect(try a.foto(cartella: id).map(\.nome).sorted() == ["a.jpg", "b.jpg", "c.jpg"])
        #expect(try a.cartelle().filter { $0.nFoto != 0 }.map(\.percorso) == prima)
        // la seconda volta è la stessa riga
        #expect(try a.aggiungiPassaggio(radice.appendingPathComponent("Anno").path, profilo: "lorenzo") == id)
        try indicizza(a, radice)
        #expect(try a.cartelle().first { $0.id == id }?.nFoto == 0)
    }

    @Test func soloLeFotoDirette() throws {
        let dir = try cartellaTemporanea()
        defer { try? FileManager.default.removeItem(at: dir) }
        let radice = dir.appendingPathComponent("disco")
        try crea(radice, ["Viaggio/a.jpg", "Viaggio/Giorno 1/b.jpg", "Viaggio/Giorno 1/sera/c.jpg", "Viaggio 2/d.jpg"])
        let a = try Archivio(url: dir.appendingPathComponent("prova.db"))
        try indicizza(a, radice)
        let v = radice.appendingPathComponent("Viaggio").path
        let id = try #require(try a.cartelle().first { $0.percorso == v }).id
        let tutte = try a.foto(cartella: id)
        #expect(tutte.map(\.nome).sorted() == ["a.jpg", "b.jpg", "c.jpg"])  // «Viaggio 2» non entra
        #expect(FotoRecord.dirette(tutte, in: v).map(\.nome) == ["a.jpg"])
        #expect(FotoRecord.dirette(tutte, in: v + "/Altra").isEmpty)
    }

    @Test func avanzamentoOgni25Cartelle() throws {
        let dir = try cartellaTemporanea()
        defer { try? FileManager.default.removeItem(at: dir) }
        let radice = dir.appendingPathComponent("disco")
        try crea(radice, (0..<60).map { "c\($0)/a.jpg" })
        let a = try Archivio(url: dir.appendingPathComponent("prova.db"))
        var passi: [Int] = []
        try a.applicaIndice(Indicizzatore.percorri(radice, saltate: []), profilo: "generico", saltate: []) { passi.append($0) }
        #expect(passi == [25, 50])
        #expect(try a.cartelle().count == 60)
    }

    @Test func radiceStaccataNonToglieNulla() throws {
        let dir = try cartellaTemporanea()
        defer { try? FileManager.default.removeItem(at: dir) }
        let radice = dir.appendingPathComponent("disco")
        try crea(radice, ["r1/a.jpg"])
        let a = try Archivio(url: dir.appendingPathComponent("prova.db"))
        try indicizza(a, radice)
        let staccato = dir.appendingPathComponent("spostato")
        try FileManager.default.moveItem(at: radice, to: staccato)
        try indicizza(a, radice)  // la radice non c'è: disco staccato
        #expect(try a.cartelle().count == 1)
        #expect(try a.foto(cartella: a.cartelle()[0].id).count == 1)
    }

    @Test func accessiRestanoTogliendoNonSiCancellaNulla() throws {
        let dir = try cartellaTemporanea()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = try Archivio(url: dir.appendingPathComponent("prova.db"))
        try a.aggiungiAccesso("/Volumes/Disco", segnalibro: Data([1, 2]), profilo: "generico")
        #expect(try a.accessi().first?.segnalibro == Data([1, 2]))
        try a.impostaProfiloAccesso("/Volumes/Disco", "lorenzo")
        try a.aggiungiAccesso("/Volumes/Disco", segnalibro: Data([3]))  // il segnalibro nuovo non cambia le regole
        #expect(try a.accessi().first?.profilo == "lorenzo")
        try a.togliAccesso("/Volumes/Disco")
        #expect(try a.accessi().isEmpty)
    }
}
