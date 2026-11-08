import Foundation
import Testing
@testable import FotoTagCore

@Suite struct OriginaliTests {
    static func voce(_ p: String, mtime: Double = 0) -> Originali.Voce {
        Originali.voce(URL(fileURLWithPath: p), mtime: mtime, profilo: .lorenzo, pellicole: .diLorenzo)
    }
    static func trova(_ p: String, scatto: Date?, _ c: [Originali.Voce]) -> (String?, Originali.Livello) {
        Originali.trova(p, scatto: scatto, candidati: c, profilo: .lorenzo, pellicole: .diLorenzo)
    }
    static let scatto = Date(timeIntervalSince1970: 1_700_000_000)

    @Test(arguments: [("DSC_0247.NEF.jpg", "dsc_0247"), ("DSC_0247-2.jpg", "dsc_0247"), ("DSC_0247 copia.jpg", "dsc_0247"),
                      ("DSC_0247 (1).jpg", "dsc_0247"), ("IMG_1-modifica.jpg", "img_1"), ("11.jpg", "11")])
    func radice(_ nome: String, _ attesa: String) {
        #expect(Originali.radice(nome) == attesa)
    }

    @Test func sicuroConLaStrutturaDellImportazione() {
        let raw = Self.voce("/F/2026/2026-10-05 praga/RAW/DSC_0001.NEF")
        let altro = Self.voce("/F/2025/2025-01-01 roma/RAW/DSC_0001.NEF")
        let r = Self.trova("/F/2026/2026-10-05 praga/JPG/DSC_0001.jpg", scatto: nil, [altro, raw])
        #expect(r.0 == raw.percorso && r.1 == .sicuro)
    }

    @Test func sicuroConLaDataDelloScatto() {
        let vicino = Self.voce("/F/2024/maggio/DSC_0066.NEF", mtime: Self.scatto.timeIntervalSince1970 + 1800)
        let lontano = Self.voce("/F/2021/marzo/DSC_0066.NEF", mtime: Self.scatto.timeIntervalSince1970 - 86_400 * 900)
        let r = Self.trova("/E/2024/maggio/DSC_0066.jpg", scatto: Self.scatto, [lontano, vicino])
        #expect(r.0 == vicino.percorso && r.1 == .sicuro)
    }

    @Test func probabileSeUnoSoloEVicino() {
        let v = Self.voce("/F/2024/maggio/DSC_0066.NEF", mtime: Self.scatto.timeIntervalSince1970 + 20 * 3600)
        let r = Self.trova("/E/2024/maggio/DSC_0066.jpg", scatto: Self.scatto, [v])
        #expect(r.0 == v.percorso && r.1 == .probabile)
    }

    @Test func incertoSeDueVicini() {
        let a = Self.voce("/F/2024/maggio/a/DSC_0066.NEF", mtime: Self.scatto.timeIntervalSince1970 + 10 * 3600)
        let b = Self.voce("/F/2024/maggio/b/DSC_0066.NEF", mtime: Self.scatto.timeIntervalSince1970 + 20 * 3600)
        let r = Self.trova("/E/2024/maggio/DSC_0066.jpg", scatto: Self.scatto, [a, b])
        #expect(r.0 == a.percorso && r.1 == .incerto)
    }

    @Test func nessunoSeLaDataEDiversa() {
        let v = Self.voce("/F/2021/marzo/DSC_0066.NEF", mtime: Self.scatto.timeIntervalSince1970 - 86_400 * 900)
        let r = Self.trova("/E/2024/maggio/DSC_0066.jpg", scatto: Self.scatto, [v])
        #expect(r.0 == nil && r.1 == .nessuno)
    }

    @Test func senzaDataDecidonoLeCartelle() {
        let giusto = Self.voce("/F/Analogica/2024/maggio/1048/12.tif")
        let altro = Self.voce("/F/Analogica/2019/luglio/0501/12.tif")
        // nome generico ('12'): serve un punteggio pieno (anno + mese)
        let r = Self.trova("/E/2024/maggio/1048/12.jpg", scatto: nil, [altro, giusto])
        #expect(r.0 == giusto.percorso && r.1 == .probabile)
        let r2 = Self.trova("/E/2023/12.jpg", scatto: nil, [altro, giusto])
        #expect(r2.0 == nil && r2.1 == .nessuno)
    }

    @Test func nonCollegaSeStesso() {
        let p = "/E/2024/maggio/DSC_0066.jpg"
        #expect(Self.trova(p, scatto: Self.scatto, [Self.voce(p, mtime: Self.scatto.timeIntervalSince1970)]).1 == .nessuno)
    }
}
