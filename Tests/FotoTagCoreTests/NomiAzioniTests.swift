import Testing
@testable import FotoTagCore

@Suite struct NomiAzioniTests {
    @Test func nomiConLOggetto() {
        #expect(NomiAzioni.togliTag("nebbia") == "Togli tag «nebbia»")
        #expect(NomiAzioni.aggiungiTag("piazza") == "Aggiungi tag «piazza»")
        #expect(NomiAzioni.conferma(1) == "Conferma tag")
        #expect(NomiAzioni.conferma(5) == "Conferma tag (5 foto)")
        #expect(NomiAzioni.riapri(2) == "Riapri (2 foto)")
        #expect(NomiAzioni.didascalia == "Modifica didascalia")
        #expect(NomiAzioni.correggi("rullino") == "Correggi rullino")
    }
}

@Suite struct ValoreComuneTests {
    @Test func ugualeODiversi() {
        #expect(ValoreComune(["analogica", "analogica"]) == .uguale("analogica"))
        #expect(ValoreComune(["analogica", "digitale"]) == .diversi)
        #expect(ValoreComune([String]()) == .diversi)
        // origine incerta in tutte: valore comune «nessuno», non «valori diversi»
        #expect(ValoreComune([String?.none, nil]) == .uguale(nil))
        #expect(ValoreComune(["a", nil]).valore == nil)
    }

    @Test func nomeConIlNumeroDiFoto() {
        #expect(NomiAzioni.correggi("origine", foto: 14) == "Correggi origine (14 foto)")
        #expect(NomiAzioni.correggi("rullino") == "Correggi rullino")
    }

    @Test func dataScrittaAMano() {
        var t = TagFissi()
        t.daVerificare = ["data"]
        t.impostaData("2025/12/11")
        #expect(t.testoData == "2025-12-11" && t.daVerificare.isEmpty)
        t.impostaData("2025-13")
        #expect(t.testoData == "2025")
        t.impostaData("")
        #expect(t.anno == nil && t.testoData == "")
    }
}
