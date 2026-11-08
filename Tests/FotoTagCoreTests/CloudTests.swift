import Foundation
import os
import Testing
@testable import FotoTagCore

@Suite(.serialized) struct CloudTests {
    /// FileProvider che non risponde (BeeStation): la richiesta resta ferma, ma chi aspetta scade lo stesso.
    @Test func discoInCloudBloccatoNonFermaIlChiamante() async throws {
        let url = URL(fileURLWithPath: "/prova-fototag/solo-in-cloud-\(UUID().uuidString).jpg")
        let originale = Immagini.avviaScaricamento
        Immagini.avviaScaricamento = { _ in Thread.sleep(forTimeInterval: 5) }
        Immagini.richieste.withLock { _ = $0.provaSoloInCloud.insert(url.path) }
        defer {
            Immagini.avviaScaricamento = originale
            Immagini.richieste.withLock { _ = $0.provaSoloInCloud.remove(url.path) }
        }
        let t = Date()
        #expect(await Immagini.scarica(url, attesa: 1) == false)
        #expect(Date().timeIntervalSince(t) < 2)
        // la stessa foto chiesta di nuovo non si accoda una seconda volta
        Immagini.chiedi(url)
        #expect(Immagini.richieste.withLock { $0.inCorso.keys.filter { $0 == url.path }.count } == 1)
    }

    /// Foto solo in cloud: si indicizza dall'anteprima, senza anteprima si salta.
    @Test func indiceDiRicercaSceglieIlFile() {
        let url = URL(fileURLWithPath: "/prova-fototag/solo-in-cloud-\(UUID().uuidString).jpg")
        let anteprima = URL(fileURLWithPath: "/prova-fototag/anteprima.jpg")
        Immagini.richieste.withLock { _ = $0.provaSoloInCloud.insert(url.path) }
        defer { Immagini.richieste.withLock { _ = $0.provaSoloInCloud.remove(url.path) } }
        #expect(Ricerca.fileDaIndicizzare(url, anteprima: anteprima) == anteprima)
        #expect(Ricerca.fileDaIndicizzare(url, anteprima: nil) == nil)
        // disco staccato: come il cloud, l'anteprima se c'è
        let staccata = URL(fileURLWithPath: "/prova-fototag/non-esiste.jpg")
        #expect(Ricerca.fileDaIndicizzare(staccata, anteprima: anteprima) == anteprima)
        #expect(Ricerca.fileDaIndicizzare(staccata, anteprima: nil) == nil)
        let locale = FileManager.default.temporaryDirectory
        #expect(Ricerca.fileDaIndicizzare(locale, anteprima: anteprima) == locale)
    }

    /// Prima di scrivere: il JPG e il sidecar, mai il RAW.
    @Test func daPortareSulMacSenzaIlRAW() throws {
        let dir = try cartellaTemporanea()
        defer { try? FileManager.default.removeItem(at: dir) }
        let jpg = dir.appendingPathComponent("DSC_1.jpg"), raw = dir.appendingPathComponent("DSC_1.NEF")
        try Data().write(to: jpg)
        try Data().write(to: raw)
        var r = Scrittura.Richiesta(file: jpg, parole: [], didascalia: "", gerarchia: [])
        #expect(Scrittura.daPortareSulMac(r, nomeSidecar: .lightroom) == [jpg, dir.appendingPathComponent("DSC_1.xmp")])
        let tif = dir.appendingPathComponent("originale.tif")
        r.raw = tif
        #expect(Scrittura.daPortareSulMac(r, nomeSidecar: .lightroom) == [jpg, tif])
    }

    @Test func fileLocaleSubito() async throws {
        let dir = try cartellaTemporanea()
        defer { try? FileManager.default.removeItem(at: dir) }
        let u = dir.appendingPathComponent("a.jpg")
        try immagineDiProva(u, tipo: .jpeg)
        let t = Date()
        #expect(await Immagini.scarica(u, attesa: 5))
        #expect(Date().timeIntervalSince(t) < 0.1)
    }
}

@Suite(.serialized) struct LiberaDopoScritturaTests {
    /// D62: una foto non ancora caricata resta in attesa e si toglie al giro dopo.
    @Test func siLiberaQuandoIlDiscoInCloudHaCaricato() throws {
        let f = FileManager.default.temporaryDirectory.appendingPathComponent("scritta-\(UUID().uuidString).jpg")
        try Data("x".utf8).write(to: f)
        let originale = Immagini.togliDalMac
        let tolte = OSAllocatedUnfairLock(initialState: 0), caricata = OSAllocatedUnfairLock(initialState: false)
        Immagini.togliDalMac = { _ in
            guard caricata.withLock({ $0 }) else { throw CocoaError(.fileWriteUnknown) }
            tolte.withLock { $0 += 1 }
        }
        defer {
            Immagini.togliDalMac = originale
            UserDefaults.standard.removeObject(forKey: Immagini.chiaveDaLiberare)
            try? FileManager.default.removeItem(at: f)
        }
        let attesa = { Immagini.codaLibera.sync { UserDefaults.standard.stringArray(forKey: Immagini.chiaveDaLiberare) ?? [] } }
        Immagini.liberaQuandoCaricate([f])
        Immagini.liberaCaricate()
        #expect(attesa() == [f.path] && tolte.withLock { $0 } == 0)
        caricata.withLock { $0 = true }
        Immagini.liberaCaricate()
        #expect(attesa().isEmpty && tolte.withLock { $0 } == 1)
    }
}
