import Testing
@testable import FotoTagCore

@Suite struct LinguaTests {
    @Test func tagFissiInInglese() {
        var t = TagFissi()
        t.origine = "analogica"; t.biancoNero = true; t.anno = 2025; t.mese = 9; t.giorno = 22
        t.digitalizzata = "3 ottobre 2025"; t.rullini = ["1048"]; t.pellicole = ["Ilford HP5 Plus 400"]; t.tiraggio = 800
        #expect(t.parole(.inglese) == ["analog", "black and white", "digitized on 3 october 2025", "2025", "september 2025",
                                       "22 september 2025", "roll 1048", "film Ilford HP5 Plus 400", "exposed at 800 iso"])
        #expect(t.gerarchia(.inglese).prefix(3) == ["Origin|analog", "Tone|black and white", "Date|2025|september"])
        // l'italiano resta com'era
        #expect(t.parole().first == "analogica" && t.gerarchia().first == "Origine|analogica")
    }

    @Test func linguaSconosciutaTornaAllItaliano() {
        #expect(Lingua.con(codice: "en").codice == "en")
        #expect(Lingua.con(codice: "xx").codice == "it")
    }
}
