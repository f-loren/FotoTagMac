import Foundation
import Testing
@testable import FotoTagCore

@Suite struct AlberoTests {
    let home = "/Users/mario"
    let cloud = "/Users/mario/Library/CloudStorage/BeeStation-Casa"

    @Test func radici() {
        #expect(Albero.radice(di: "/Users/mario/Prove/uno", home: home) == home)
        #expect(Albero.radice(di: "/Volumes/Archivio/Foto/2025", home: home) == "/Volumes/Archivio")
        #expect(Albero.radice(di: "/tmp/x", home: home) == "/")
    }

    @Test func righeVisibili() {
        let albero = Albero.costruisci(["/Volumes/A/Foto/2025", "/Volumes/A/Foto/2024", "/Volumes/A/Altro"],
                                       radici: ["/Volumes/A"], home: home, collegata: { _ in true })
        let chiuso = Albero.righe(albero) { _, livello in livello == 0 }
        #expect(chiuso.map(\.nodo.nome) == ["A", "Altro", "Foto"])
        #expect(chiuso.map(\.livello) == [0, 1, 1])
        let aperto = Albero.righe(albero) { _, _ in true }
        #expect(aperto.map(\.nodo.nome) == ["A", "Altro", "Foto", "2024", "2025"])
        #expect(aperto.map(\.livello) == [0, 1, 1, 2, 2])
        #expect(Albero.righe(albero) { _, _ in false }.map(\.nodo.nome) == ["A"])
    }

    @Test func unaRadicePerAccessoEUnLivelloPerRiga() {
        let albero = Albero.costruisci([
            "/Volumes/Archivio/Foto/2025/dicembre",
            "/Volumes/Archivio/Foto/2025/maggio",
            "/Users/mario/Prove/uno",
            cloud + "/Foto/2024",
        ], radici: ["/Volumes/Archivio", cloud, home], home: home, collegata: { _ in true })
        #expect(albero.map(\.nome) == ["mario", "Archivio", "BeeStation"])
        #expect(albero[0].figli.map(\.nome) == ["Prove"])
        #expect(albero[0].figli[0].figli.map(\.nome) == ["uno"])

        // ogni riga è una cartella sola: niente «A > B», anche con un solo figlio
        let foto = albero[1].figli[0]
        #expect(foto.nome == "Foto" && foto.percorso == "/Volumes/Archivio/Foto")
        #expect(foto.figli.map(\.nome) == ["2025"])
        #expect(foto.figli[0].figli.map(\.nome) == ["dicembre", "maggio"])
        #expect(albero[2].figli[0].percorso == cloud + "/Foto")
    }

    @Test func nomeUgualeAlPercorso() {
        func controlla(_ n: NodoAlbero) {
            #expect(n.nome == (n.percorso as NSString).lastPathComponent)
            n.figli.forEach(controlla)
        }
        let albero = Albero.costruisci(["/Volumes/D/Claude/a/Foto", "/Volumes/D/Foto/b"], radici: ["/Volumes/D"],
                                       home: home, collegata: { _ in true })
        #expect(albero[0].figli.map(\.nome) == ["Claude", "Foto"])
        controlla(albero[0])
    }

    @Test func accessoPiuSpecificoEDiscoStaccato() {
        let albero = Albero.costruisci(["/Users/mario/Foto/a", "/Users/mario/Altro", "/Volumes/Via/x"],
                                       radici: [home, "/Users/mario/Foto", "/Volumes/Via"], home: home,
                                       collegata: { $0 != "/Volumes/Via" })
        #expect(albero.map(\.nome) == ["mario", "Via", "Foto"])
        #expect(albero[0].figli.map(\.nome) == ["Altro"])
        #expect(albero[2].figli.map(\.nome) == ["a"])
        #expect(!albero[1].collegata && !albero[1].figli[0].collegata)
        #expect(albero[0].collegata)
    }

    @Test func fuoriDagliAccessiNonSiVede() {
        let albero = Albero.costruisci(["/Volumes/Tolto/x"], radici: [home], home: home, collegata: { _ in true })
        #expect(albero.map(\.nome) == ["mario"] && albero[0].figli.isEmpty)
    }
}
