import Testing
@testable import FotoTagCore

@Suite struct AvvisiTests {
    @Test func testoDiFineSenzaLePartiAZero() {
        let a = Avvisi.fine(cartella: "dicembre", analizzate: 333, daRivedere: 5, errori: 2)
        #expect(a.titolo == "dicembre: analisi finita")
        #expect(a.testo == "333 foto analizzate, 5 da rivedere, 2 con errore.")
        #expect(Avvisi.fine(cartella: "x", analizzate: 12, daRivedere: 0, errori: 0).testo == "12 foto analizzate.")
        #expect(Avvisi.fine(cartella: "x", analizzate: 0, daRivedere: 0, errori: 3).testo == "3 con errore.")
    }

    @Test func interrottaEDistintivo() {
        #expect(Avvisi.interrotta(cartella: "dicembre", dopo: 59).titolo == "dicembre: analisi interrotta dopo 59 foto")
        #expect(Avvisi.distintivo(0) == "" && Avvisi.distintivo(7) == "7")
    }
}
