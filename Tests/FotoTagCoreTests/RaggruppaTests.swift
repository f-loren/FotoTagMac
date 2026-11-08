import Testing
@testable import FotoTagCore

@Suite struct RaggruppaTests {
    func r(_ id: Int64, _ p: String, _ s: Float) -> Ricerca.Risultato {
        Ricerca.Risultato(id: id, percorso: p, didascalia: "", punteggio: s, siglip: s, testo: 0)
    }

    @Test func gruppiPerCartellaInOrdineDiPertinenza() {
        let g = Ricerca.raggruppa([
            r(1, "/Foto/2025/dicembre/gothic/a.jpg", 0.4),
            r(2, "/Foto/2025/maggio/b.jpg", 0.9),
            r(3, "/Foto/2025/dicembre/gothic/c.jpg", 0.7),
            r(4, "/Foto/2025/maggio/d.jpg", 0.2),
            r(5, "/Foto/2024/x/e.jpg", 0.5),
        ])
        #expect(g.map(\.nome) == ["maggio", "gothic", "x"])
        #expect(g[0].ids == [2, 4] && g[1].ids == [3, 1])
        #expect(g[1].madre == "2025 > dicembre")
        #expect(g[0].madre == "Foto > 2025")
    }

    @Test func nessunRisultato() { #expect(Ricerca.raggruppa([]).isEmpty) }
}
