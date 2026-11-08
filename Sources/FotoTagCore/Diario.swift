import Foundation
import os

/// Registro dell'app: righe nel Logger di sistema e in Application Support/FotoTag/log.txt
/// (oltre 1 MB il file diventa log.1.txt e si ricomincia). Serve per «Esporta diagnostica…».
public enum Diario {
    static let logger = Logger(subsystem: "it.lorenzozanna.fototag", category: "app")
    static let coda = DispatchQueue(label: "FotoTag.Diario")
    static let limite = 1_000_000

    public static var file: URL {
        // durante le prove (xcodebuild test) il registro vero resta pulito
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return FileManager.default.temporaryDirectory.appendingPathComponent("FotoTagTests-log.txt")
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FotoTag/log.txt")
    }

    public static func info(_ s: String) { scrivi("info", s); logger.info("\(s, privacy: .public)") }
    public static func errore(_ s: String) { scrivi("ERRORE", s); logger.error("\(s, privacy: .public)") }

    static func scrivi(_ livello: String, _ s: String) {
        let riga = "\(Date().formatted(.iso8601)) \(livello) \(s)\n"
        coda.async {
            let fm = FileManager.default
            let u = file
            try? fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let n = (try? fm.attributesOfItem(atPath: u.path)[.size] as? Int), n > limite {
                let vecchio = u.deletingLastPathComponent().appendingPathComponent("log.1.txt")
                try? fm.removeItem(at: vecchio)
                try? fm.moveItem(at: u, to: vecchio)
            }
            if let h = try? FileHandle(forWritingTo: u) {
                h.seekToEndOfFile(); h.write(Data(riga.utf8)); try? h.close()
            } else {
                try? Data(riga.utf8).write(to: u)
            }
        }
    }

    /// Aspetta che le righe in coda siano sul disco (prima di un possibile crash).
    public static func attendi() { coda.sync {} }

    /// Le ultime `n` righe del registro.
    public static func ultimeRighe(_ n: Int) -> [String] {
        coda.sync {}  // aspetta le scritture in corso
        guard let t = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return Array(t.split(separator: "\n").suffix(n).map(String.init))
    }
}
