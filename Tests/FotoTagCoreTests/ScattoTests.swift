import Foundation
import Testing
@testable import FotoTagCore

/// D66: il JPG trova il suo RAW dall'impronta dello scatto, anche con un altro nome.
@Suite struct ScattoTests {
    @Test func improntaUgualeFraProgrammiDiversi() {
        let raw = CalcoloFissi.impronta(modello: "NIKON D200", data: "2025:03:30 10:21:49", centesimi: "41")
        #expect(raw == "nikon d200|2025:03:30 10:21:49|41")
        #expect(CalcoloFissi.impronta(modello: " NIKON D200 ", data: "2025:03:30 10:21:49", centesimi: "410") == raw)
        #expect(CalcoloFissi.impronta(modello: "X", data: "2025:03:30 10:21:49", centesimi: "4") == "x|2025:03:30 10:21:49|40")
        #expect(CalcoloFissi.impronta(modello: "", data: "2025:03:30 10:21:49", centesimi: "41") == nil)
        #expect(CalcoloFissi.impronta(modello: "X", data: "2025:03", centesimi: "41") == nil)
        #expect(CalcoloFissi.impronta(modello: "X", data: "2025:03:30 10:21:49", centesimi: "") == nil)
    }

    @Test func originaliPerScattoERilettura() throws {
        let dir = try cartellaTemporanea()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = try Archivio(url: dir.appendingPathComponent("prova.db"))
        try a.aggiungiRadiceOriginali("/RAW", segnalibro: nil, soloRaw: false, profilo: "generico")
        let id = try #require(try a.radiciOriginali().first?.id)
        let k = "nikon d200|2025:03:30 10:21:49|41"
        try a.salvaIndice(radice: id, [
            Originali.Voce(percorso: "/RAW/_DSC4359.NEF", radice: "_dsc4359", ext: "nef", anno: 2025, mese: 3, mtime: 10, scatto: k),
            Originali.Voce(percorso: "/RAW/_DSC4360.NEF", radice: "_dsc4360", ext: "nef", anno: 2025, mese: 3, mtime: 11),
        ])
        #expect(try a.originaliPerScatto(k) == ["/RAW/_DSC4359.NEF"])
        #expect(try a.originaliSenzaScatto() == ["/RAW/_DSC4360.NEF"])
        #expect(try a.scattiNoti(radice: id)["/RAW/_DSC4359.NEF"]?.mtime == 10)
        try a.salvaScatto("/RAW/_DSC4360.NEF", "altro")
        #expect(try a.originaliSenzaScatto().isEmpty)
        // il database si riapre senza rifare la colonna
        _ = try Archivio(url: dir.appendingPathComponent("prova.db"))
    }
}
