import Foundation
import Testing
@testable import FotoTagCore

@Suite struct AnteprimeTests {
    @Test func chiaveDallImprontaNonDalPercorso() {
        let c = URL(fileURLWithPath: "/tmp/anteprime")
        let a = Anteprime.file(impronta: "123-abc-def", lato: 1024, in: c)
        #expect(a == Anteprime.file(impronta: "123-abc-def", lato: 1024, in: c))
        #expect(a != Anteprime.file(impronta: "123-abc-deg", lato: 1024, in: c))
        #expect(a.lastPathComponent.hasSuffix("_1024.jpg"))
        #expect(a.deletingLastPathComponent().lastPathComponent.count == 2)
    }

    @Test func salvaETrovaLaPiuGrande() throws {
        let dir = try cartellaTemporanea()
        defer { try? FileManager.default.removeItem(at: dir) }
        let foto = dir.appendingPathComponent("a.jpg")
        try immagineDiProva(foto, tipo: .jpeg)
        let anteprime = dir.appendingPathComponent("Anteprime")
        let imp = try #require(Immagini.impronta(foto))
        #expect(Anteprime.trova(impronta: imp, in: anteprime) == nil)
        try Anteprime.salva(da: foto, impronta: imp, lato: 640, in: anteprime)
        #expect(Anteprime.trova(impronta: imp, in: anteprime)?.lastPathComponent.hasSuffix("_640.jpg") == true)
        try Anteprime.salva(da: foto, impronta: imp, lato: 1024, in: anteprime)  // la nuova misura sostituisce la vecchia
        #expect(Anteprime.trova(impronta: imp, in: anteprime)?.lastPathComponent.hasSuffix("_1024.jpg") == true)
        #expect(Anteprime.campioni(in: anteprime).map(\.lato) == [1024])
        #expect(Anteprime.trova(impronta: nil, in: anteprime) == nil)
    }

    @Test func stimaDalPesoVeroRiportataAlLato() {
        // 100 KB a 1000 px → a 2000 px quattro volte tanto
        let c = [Anteprime.Campione(byte: 100_000, lato: 1000), Anteprime.Campione(byte: 100_000, lato: 1000)]
        #expect(Anteprime.stima(c, lato: 1000, foto: 10).kbAFoto == 100)
        let s = Anteprime.stima(c, lato: 2000, foto: 1000)
        #expect(s.kbAFoto == 400 && s.totaleMB == 400)
        // senza anteprime: circa 120 KB a 1024 px
        #expect(Anteprime.stima([], lato: 1024, foto: 5375) == (120, 645))
    }
}
