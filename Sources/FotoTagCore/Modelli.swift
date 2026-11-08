import CryptoKit
import Foundation

/// Modelli di analisi: quale usare su questo Mac, dove stanno, come scaricarli.
public enum Modelli {
    public struct Modello: Identifiable, Hashable, Sendable {
        public let id: String          // "qwen8b", "qwen4b"
        public let repo: String        // Hugging Face
        public let revisione: String   // commit fissato: un aggiornamento del repo non cambia cosa si scarica
        public let nome: String
        public let descrizione: String
        public let gigabyte: Double    // download
        public let discoGB: Double     // occupati sul disco a installazione finita (SigLIP tiene anche la copia compilata)
        public let ramMinimaGB: Double // memoria del Mac consigliata
    }

    /// Spazio da lasciare libero oltre al modello.
    public static let margineDiscoGB = 2.0

    public static let qwen8b = Modello(
        id: "qwen8b", repo: "mlx-community/Qwen3-VL-8B-Instruct-4bit",
        revisione: "defcdea7cc7a4b0858fea563cbbce171d328e457", nome: "Qwen3-VL 8B",
        descrizione: String(localized: "Qualità piena. Circa 8 s per foto su M2 Pro, 6,4 GB di memoria durante l'analisi."),
        gigabyte: 5.8, discoGB: 5.8, ramMinimaGB: 16)
    public static let qwen4b = Modello(
        id: "qwen4b", repo: "mlx-community/Qwen3-VL-4B-Instruct-4bit",
        revisione: "2fd8dacbdb8f1e54b8c005f081ec5bf79c56376b", nome: String(localized: "Qwen3-VL 4B (leggero)"),
        descrizione: String(localized: "Per i Mac con 8 GB. Circa 2 volte più veloce, ma inventa più dettagli e riconosce meno luoghi: rivedi i tag."),
        gigabyte: 3.1, discoGB: 3.1, ramMinimaGB: 8)
    public static let tutti = [qwen8b, qwen4b]

    /// Modello per la ricerca: SigLIP 2 convertito in Core ML per FotoTag, pubblicato da Lorenzo.
    public static let siglip = Modello(
        id: "siglip2", repo: "f-loren/fototag-siglip2-coreml",
        revisione: "d1fc807a6d76b2070033f3d99106344fe8959b1b", nome: String(localized: "Ricerca (SigLIP 2)"),
        descrizione: String(localized: "Serve per «Cerca nelle foto». Google, licenza Apache 2.0."), gigabyte: 0.75, discoGB: 1.5, ramMinimaGB: 8)
    public static func con(id: String) -> Modello? { tutti.first { $0.id == id } }

    public static var ramGB: Double { Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824 }

    /// Il modello consigliato per questo Mac: l'8B dai 16 GB in su, altrimenti il 4B.
    public static var consigliato: Modello { ramGB >= 15 ? qwen8b : qwen4b }

    /// Cartella dei modelli scaricati dall'app.
    public static func cartellaApp() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FotoTag/Modelli", isDirectory: true)
    }

    static func completo(_ u: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: u.appendingPathComponent("config.json").path) else { return false }
        let file = (try? fm.contentsOfDirectory(atPath: u.path)) ?? []
        return file.contains { $0.hasSuffix(".safetensors") } && !file.contains { $0.hasSuffix(".parziale") }
    }

    /// Dove si trova il modello sul Mac (cartella dell'app o cache di Hugging Face), se c'è.
    public static func posizione(_ m: Modello) -> URL? {
        let app = cartellaApp().appendingPathComponent(m.repo.replacingOccurrences(of: "/", with: "--"))
        if completo(app) { return app }
        if let c = Tagger.modelloInCache(m.repo), completo(c) { return c }
        return nil
    }

    public static func scaricatoDallApp(_ m: Modello) -> Bool {
        completo(cartellaApp().appendingPathComponent(m.repo.replacingOccurrences(of: "/", with: "--")))
    }

    // MARK: download

    public struct FileRemoto: Decodable, Sendable {
        public let rfilename: String
        public let size: Int64?
        public let blobId: String?          // sha1 del blob git (file piccoli)
        public let lfs: LFS?
        public struct LFS: Decodable, Sendable { public let sha256: String }
    }
    struct Info: Decodable { let siblings: [FileRemoto] }

    /// Elenco dei file del modello su Hugging Face, alla revisione fissata.
    public static func elencoFile(_ m: Modello) async throws -> [FileRemoto] {
        let u = URL(string: "https://huggingface.co/api/models/\(m.repo)/revision/\(m.revisione)?blobs=true")!
        let (d, r) = try await URLSession.shared.data(from: u)
        guard (r as? HTTPURLResponse)?.statusCode == 200 else { throw Scrittura.errore(String(localized: "Hugging Face non risponde per \(m.repo)")) }
        return try JSONDecoder().decode(Info.self, from: d).siblings.filter { !$0.rfilename.hasPrefix(".") && $0.rfilename != "README.md" }
    }

    /// Scarica il modello nella cartella dell'app. `filtro` serve per le prove (scaricare solo alcuni file).
    /// `avanzamento(byteScaricati, byteTotali)`. I file arrivano come .parziale e vengono rinominati alla fine.
    public static func scarica(_ m: Modello, in cartella: URL? = nil, esattamenteIn: URL? = nil, filtro: ((String) -> Bool)? = nil,
                               avanzamento: @escaping @Sendable (Int64, Int64) -> Void) async throws -> URL {
        let dest = esattamenteIn ?? (cartella ?? cartellaApp()).appendingPathComponent(m.repo.replacingOccurrences(of: "/", with: "--"))
        let fm = FileManager.default
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        let file = try await elencoFile(m).filter { filtro?($0.rfilename) ?? true }
        let totale = file.reduce(Int64(0)) { $0 + ($1.size ?? 0) }
        // i file già completi (download ripreso) non contano
        let daScaricare = file.reduce(Int64(0)) { n, f in
            let s = f.size ?? 0
            return (try? fm.attributesOfItem(atPath: dest.appendingPathComponent(f.rfilename).path)[.size] as? Int64) == s ? n : n + s
        }
        let liberi = (try? dest.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage) ?? 0
        if liberi > 0, let servono = spazioMancante(liberi: liberi, daScaricare: daScaricare, m) {
            throw Scrittura.errore(String(format: String(localized: "Spazio insufficiente: servono %.1f GB liberi (il modello e %.0f GB di margine), ce ne sono %.1f."),
                                          servono, margineDiscoGB, Double(liberi) / 1e9))
        }
        var fatti: Int64 = 0
        for f in file {
            let finale = dest.appendingPathComponent(f.rfilename)
            if let s = f.size, (try? fm.attributesOfItem(atPath: finale.path)[.size] as? Int64) == s { fatti += s; continue }
            try fm.createDirectory(at: finale.deletingLastPathComponent(), withIntermediateDirectories: true)
            let u = URL(string: "https://huggingface.co/\(m.repo)/resolve/\(m.revisione)/\(f.rfilename)")!
            let base = fatti
            let (tmp, r) = try await URLSession.shared.download(from: u, delegate: Progresso { n in avanzamento(base + n, totale) })
            guard (r as? HTTPURLResponse)?.statusCode == 200 else { throw Scrittura.errore(String(localized: "download non riuscito: \(f.rfilename)")) }
            let parziale = finale.appendingPathExtension("parziale")
            try? fm.removeItem(at: parziale)
            try fm.moveItem(at: tmp, to: parziale)
            if let s = f.size, (try? fm.attributesOfItem(atPath: parziale.path)[.size] as? Int64) != s {
                try? fm.removeItem(at: parziale)
                throw Scrittura.errore(String(localized: "file incompleto: \(f.rfilename)"))
            }
            guard try integro(parziale, f) else {
                try? fm.removeItem(at: parziale)
                Diario.errore("download di \(m.repo): \(f.rfilename) non corrisponde all'impronta di Hugging Face")
                throw Scrittura.errore(String(localized: "file rovinato durante il download: \(f.rfilename). Riprova."))
            }
            try? fm.removeItem(at: finale)
            try fm.moveItem(at: parziale, to: finale)
            fatti += f.size ?? 0
            avanzamento(fatti, totale)
        }
        return dest
    }

    /// GB liberi che servono se non bastano, nil se lo spazio c'è: il modello come starà sul disco più il margine.
    static func spazioMancante(liberi: Int64, daScaricare: Int64, _ m: Modello) -> Double? {
        let servono = Double(daScaricare) / 1e9 * m.discoGB / m.gigabyte + margineDiscoGB
        return Double(liberi) / 1e9 < servono ? servono : nil
    }

    /// Vero se il file corrisponde a quello pubblicato: sha256 per i file LFS, sha1 del blob git per gli altri.
    static func integro(_ u: URL, _ f: FileRemoto) throws -> Bool {
        if let atteso = f.lfs?.sha256 { return try impronta(u, SHA256()) == atteso }
        if let atteso = f.blobId {
            var h = Insecure.SHA1()
            h.update(data: Data("blob \(try FileManager.default.attributesOfItem(atPath: u.path)[.size] as? Int ?? 0)\0".utf8))
            return try impronta(u, h) == atteso
        }
        return true
    }

    /// Hash del file letto a blocchi da 8 MB (i pesi sono di alcuni GB).
    static func impronta<H: HashFunction>(_ u: URL, _ iniziale: H) throws -> String {
        var h = iniziale
        let file = try FileHandle(forReadingFrom: u)
        defer { try? file.close() }
        while let blocco = try file.read(upToCount: 8 << 20), !blocco.isEmpty { h.update(data: blocco) }
        return h.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Elimina un modello scaricato dall'app (la cache di Hugging Face non si tocca).
    public static func elimina(_ m: Modello) throws {
        try FileManager.default.removeItem(at: cartellaApp().appendingPathComponent(m.repo.replacingOccurrences(of: "/", with: "--")))
    }

    final class Progresso: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let f: (Int64) -> Void
        init(_ f: @escaping (Int64) -> Void) { self.f = f }
        func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten t: Int64, totalBytesExpectedToWrite _: Int64) { f(t) }
        func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    }
}
