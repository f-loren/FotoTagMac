import Testing
@testable import FotoTagCore

@Suite struct LetturaRispostaTests {
    @Test func jsonSporco() throws {
        let t = """
            Ecco il risultato:
            ```json
            {"soggetti": ["donna", "cane",], "luogo": "spiaggia", "oggetti": [], "azioni": ["camminare"],
             "atmosfera": ["tramonto"], "didascalia": “Una donna con il cane”}
            ```
            """
        let r = try #require(leggiRisposta(t))
        #expect(r.campi["soggetti"] == ["donna", "cane"])
        #expect(r.campi["luogo"] == ["spiaggia"])
        #expect(r.campi["oggetti"] == [])
        #expect(r.didascalia == "Una donna con il cane")
        #expect(r.numeroVoci == 5)
    }

    @Test func nonUnaRisposta() {
        #expect(leggiRisposta("niente JSON qui") == nil)
        #expect(leggiRisposta(#"{"a": 1, "b": 2}"#) == nil)
    }
}

@MainActor @Suite struct PuliziaTests {
    @Test func terminiPuliti() {
        let (buoni, scartati) = Pulizia.termini(["Spiaggia!", "spiaggia", "  mare  ", "fotografia", "un", "uno due tre quattro"],
                                                 lingua: .italiano)
        #expect(buoni == ["spiaggia", "mare"])
        #expect(scartati == ["fotografia", "un", "uno due tre quattro"])
    }

    @Test func paroleFuoriDizionarioSiScartano() {
        let (buoni, scartati) = Pulizia.termini(["parks", "albero", "sorrider", "venezia", "piazza san marco", "sorridere",
                                                  "xqzt", "laptop", "bar", "sport", "tram"], lingua: .italiano)
        #expect(buoni == ["albero", "venezia", "piazza san marco", "sorridere", "bar", "sport", "tram"])
        #expect(scartati == ["parks", "sorrider", "xqzt", "laptop"])
        // 'gire' (forma antica di «andare») è nel dizionario di macOS e ha un lemma: oggi passa
        #expect(Pulizia.termini(["gire"], lingua: .italiano).buoni == ["gire"])
    }

    @Test func massimoQuindiciSenzaDoppioni() {
        let tante = (1...12).map { "parola\($0)" }
        var r = Risposta(campi: [:], didascalia: "")
        r.campi["soggetti"] = ["donna", "uomo"] + tante.prefix(6)
        r.campi["luogo"] = ["donna", "piazza"] + tante.suffix(6)
        let (parole, _) = Pulizia.paroleChiave(r, lingua: .italiano)
        #expect(parole.count <= Pulizia.massimoParole)
        #expect(Set(parole).count == parole.count)
        #expect(parole.prefix(2) == ["donna", "uomo"])
    }
}
