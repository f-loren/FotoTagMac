import Foundation
import Testing
@testable import FotoTagCore

@Suite struct ModelliTests {
    static func file(_ testo: String) throws -> URL {
        let u = try cartellaTemporanea().appendingPathComponent("f.txt")
        try Data(testo.utf8).write(to: u)
        return u
    }
    static func remoto(blob: String? = nil, sha256: String? = nil) throws -> Modelli.FileRemoto {
        var j: [String: Any] = ["rfilename": "f.txt"]
        if let blob { j["blobId"] = blob }
        if let sha256 { j["lfs"] = ["sha256": sha256] }
        return try JSONDecoder().decode(Modelli.FileRemoto.self, from: JSONSerialization.data(withJSONObject: j))
    }

    @Test func blobGit() throws {
        let u = try Self.file("ciao\n")  // git hash-object → 887ae93…
        #expect(try Modelli.integro(u, Self.remoto(blob: "887ae9333d92a1d72400c210546e28baa1050e44")))
        #expect(try !Modelli.integro(u, Self.remoto(blob: "0000000000000000000000000000000000000000")))
    }

    @Test func fileLFS() throws {
        let u = try Self.file("ciao\n")
        #expect(try Modelli.integro(u, Self.remoto(sha256: "6f0378f21a495f5c13247317d158e9d51da45a5bf68fc2f366e450deafdc8302")))
        #expect(try !Modelli.integro(u, Self.remoto(blob: "887ae9333d92a1d72400c210546e28baa1050e44", sha256: String(repeating: "0", count: 64))))
    }

    @Test func spazioPerIlModello() {
        // il caso del MacBook Air: 3,8 GB liberi bastano a SigLIP (1,5 sul disco + 2 di margine)
        #expect(Modelli.spazioMancante(liberi: 3_800_000_000, daScaricare: 750_000_000, Modelli.siglip) == nil)
        #expect(Modelli.spazioMancante(liberi: 3_000_000_000, daScaricare: 750_000_000, Modelli.siglip).map { abs($0 - 3.5) < 0.01 } == true)
        #expect(Modelli.spazioMancante(liberi: 7_000_000_000, daScaricare: 5_800_000_000, Modelli.qwen8b).map { abs($0 - 7.8) < 0.01 } == true)
        #expect(Modelli.spazioMancante(liberi: 2_500_000_000, daScaricare: 0, Modelli.qwen8b) == nil)  // tutto già scaricato
    }

    @Test func revisioniFissate() {
        for m in Modelli.tutti + [Modelli.siglip] { #expect(m.revisione.count == 40, "\(m.id)") }
    }
}
