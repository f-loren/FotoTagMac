import Testing
@testable import FotoTagCore

/// Riferimento: contesto.parse del prototipo Python sugli stessi percorsi (ottobre 2026).
struct Atteso: Sendable, CustomTestStringConvertible {
    var percorso: String
    var anno: Int? = nil, mese: Int? = nil, giorno: Int? = nil
    var rullini: [String] = [], pellicole: [String] = [], tiraggio: Int? = nil, contesto: [String] = []
    var indizioPellicola = false, dataImportazione = false, origine: String? = nil
    var testDescription: String { percorso }
}

@Suite struct ContestoTests {
    static let lorenzo: [Atteso] = [
        .init(percorso: "/Volumes/Foto/Analogica/2025/marzo - alluvione/1048/img001.jpg",
              anno: 2025, mese: 3, rullini: ["1048"], contesto: ["alluvione"], origine: "analogica"),
        .init(percorso: "/Volumes/Foto/Analogica/2025/maggio/9 maggio cpa/02 cascine/x.jpg",
              anno: 2025, mese: 5, giorno: 9, rullini: ["02"], contesto: ["cpa", "cascine"], origine: "analogica"),
        .init(percorso: "/Volumes/Foto/Digitale/2024/24-05-25 marvin/DSC_0247.jpg",
              anno: 2024, mese: 5, giorno: 25, contesto: ["marvin"], origine: "digitale"),
        .init(percorso: "/Volumes/Foto/Digitale/2025/25-03-05 sieci/DSC_0001.jpg",
              anno: 2025, mese: 3, giorno: 5, contesto: ["sieci"], origine: "digitale"),
        .init(percorso: "/Volumes/Foto/Analogica/2025/aprile/1° + giardino iris/scan01.jpg",
              anno: 2025, mese: 4, giorno: 1, contesto: ["giardino iris"], origine: "analogica"),
        .init(percorso: "/Users/l/Foto/2026/2026-10-05 praga - Ilford HP5 Plus@1600/JPG/DSC_0001.jpg",
              anno: 2026, mese: 10, giorno: 5, pellicole: ["ilford hp5 plus"], tiraggio: 1600, contesto: ["praga"],
              indizioPellicola: true, dataImportazione: true),
        .init(percorso: "/Users/l/Foto/2026/2026-10-05 praga - Ilford HP5 Plus@1600/RAW/DSC_0001.NEF",
              anno: 2026, mese: 10, giorno: 5, pellicole: ["ilford hp5 plus"], tiraggio: 1600, contesto: ["praga"],
              indizioPellicola: true, dataImportazione: true),
        .init(percorso: "/Volumes/Foto/Analogica/2023/settembre/20230922/hp5 @800 - lago/01.jpg",
              anno: 2023, mese: 9, giorno: 22, pellicole: ["Ilford HP5 Plus 400"], tiraggio: 800, contesto: ["lago"],
              indizioPellicola: true, origine: "analogica"),
        .init(percorso: "/Volumes/Foto/Analogica/2022/rullino fomapan 200 + mare, amici/12.jpg",
              anno: 2022, pellicole: ["Fomapan 200"], contesto: ["mare", "amici"], indizioPellicola: true, origine: "analogica"),
        .init(percorso: "/Volumes/Foto/Analogica/2024/positivi/portra 400 - montagna/03.tif",
              anno: 2024, pellicole: ["portra 400"], contesto: ["montagna"], indizioPellicola: true, origine: "analogica"),
        .init(percorso: "/Volumes/Foto/2021/101NIKON/jpg/DSC_0066.jpg", anno: 2021),
        .init(percorso: "/Volumes/Foto/Varie/senza anno/foto.jpg"),
        .init(percorso: "/Volumes/Foto/Analogica/2025/giugno/04- prove obiettivo/delta 3200 1600 iso/a.jpg",
              anno: 2025, mese: 6, rullini: ["04"], pellicole: ["delta 3200"], tiraggio: 1600, contesto: ["prove obiettivo"],
              indizioPellicola: true, origine: "analogica"),
        .init(percorso: "/Volumes/Foto/2020/wetransfer_abc/x.jpg", anno: 2020),
    ]

    @Test(arguments: lorenzo)
    func profiloLorenzoComeIlPrototipo(_ a: Atteso) {
        let c = Contesto.leggi(a.percorso, profilo: .lorenzo, pellicole: .diLorenzo)
        #expect(c.anno == a.anno)
        #expect(c.mese == a.mese)
        #expect(c.giorno == a.giorno)
        #expect(c.rullini == a.rullini)
        #expect(c.pellicole == a.pellicole)
        #expect(c.tiraggio == a.tiraggio)
        #expect(c.contesto == a.contesto)
        #expect(c.indizioPellicola == a.indizioPellicola)
        #expect(c.dataImportazione == a.dataImportazione)
        #expect(c.origineDaCartella == a.origine)
    }

    @Test func genericoUsaLaCartellaComeContesto() {
        let c = Contesto.leggi("/Users/x/Pictures/Vacanze Sardegna/IMG_0001.jpg", profilo: .generico, pellicole: .diLorenzo)
        #expect(c.contesto == ["vacanze sardegna"])
        #expect(c.anno == nil)
        #expect(!c.indizioPellicola)
    }

    @Test func genericoDataInTestaEPellicola() {
        let c = Contesto.leggi("/Users/x/Scansioni/2019-07-14 matrimonio portra 400/01.jpg", profilo: .generico, pellicole: .diLorenzo)
        #expect(c.anno == 2019 && c.mese == 7 && c.giorno == 14)
        #expect(c.pellicole == ["portra 400"])
        #expect(c.indizioPellicola)
        #expect(c.contesto == ["matrimonio portra 400"])
    }

    @Test func genericoIgnoraLeCartelleTecniche() {
        let c = Contesto.leggi("/Users/x/Pictures/export/IMG_1.jpg", profilo: .generico, pellicole: .diLorenzo)
        #expect(c.contesto.isEmpty)
    }

    @Test func tabellaPellicoleSiglaSenzaNome() {
        #expect(TabellaPellicole.diLorenzo.nome("hp5") == "Ilford HP5 Plus 400")
        #expect(TabellaPellicole.diLorenzo.nome("sconosciuta") == "sconosciuta")
        // di base niente sigle personali; ognuno ha la sua tabella
        #expect(Profilo.generico.tabella.nome("gothic 100") == "gothic 100")
        #expect(Profilo.generico.tabella.nome("portra 400") == "Kodak Portra 400")
        #expect(Profilo.lorenzo.tabella.nome("gothic 100") == "Lineag Gothic RN 100")
    }
}
