import Foundation

/// Elenco di tutte le foto sotto una radice di accesso (disco o cartella), solo con lo stat: i file in cloud
/// non si scaricano. Da chiamare su una coda propria, mai dal thread principale né dal pool di Swift.
/// Salta solo le cose tecniche e ciò che il profilo chiede: mai le cartelle JPG/RAW.
public enum Indicizzatore {
    public struct FileFoto: Sendable, Equatable {
        public let percorso: String
        public let dimensione: Int
        public let mtime: Double
    }

    public struct Risultato: Sendable {
        public let radice: String
        public var perCartella: [String: [FileFoto]] = [:]
        /// percorsi non letti (permessi, disco staccato): lì non si toglie nulla dal database
        public var illeggibili: [String] = []
        /// false se la radice non c'è: non si tocca niente
        public var letta = false
        public var foto: Int { perCartella.values.reduce(0) { $0 + $1.count } }
    }

    /// Cartelle tecniche (in minuscolo); nascoste e pacchetti le salta già l'enumeratore.
    static let tecniche: Set<String> = ["library", "node_modules", "deriveddata", "_build"]
    /// Musica e libreria TV: macOS le protegge (anche GarageBand dentro Musica) e visitarle fa chiedere l'accesso
    /// ad Apple Music. Non sono posti da foto.
    static let multimediali: Set<String> = [NSHomeDirectory() + "/Music", NSHomeDirectory() + "/Movies/TV"]

    /// Radice di accesso per una cartella già nota: cartella utente, disco esterno o disco in cloud.
    public static func radiceAccesso(di percorso: String, home: String) -> String {
        let cloud = home + "/Library/CloudStorage/"
        if percorso.hasPrefix(cloud), let disco = percorso.dropFirst(cloud.count).split(separator: "/").first { return cloud + disco }
        return Albero.radice(di: percorso, home: home)
    }

    /// Una cartella dentro un accesso già dato non è un accesso nuovo: le sue foto si leggono già.
    /// Non vale sotto le cartelle tecniche, che l'indice non visita (i dischi in cloud stanno in Library).
    public static func compresa(_ percorso: String, in accessi: [String]) -> Bool {
        accessi.contains { a in
            // i dischi stanno in /Volumes, che l'indice non visita partendo da «/»
            percorso != a && Albero.contiene(a, percorso) && (a.hasPrefix("/Volumes/") || !percorso.hasPrefix("/Volumes/"))
                && !percorso.dropFirst(a.count).split(separator: "/").contains { tecniche.contains($0.lowercased()) }
        }
    }

    /// Un volume appena collegato da proporre: non già dentro un accesso e non rifiutato prima.
    public static func daProporre(_ volume: String, accessi: [String], ignorati: [String]) -> Bool {
        !ignorati.contains(volume) && !accessi.contains { Albero.contiene($0, volume) }
    }

    /// `escluse`: percorsi da non visitare (cartella delle anteprime, cartelle nascoste dall'utente).
    public static func percorri(_ radice: URL, saltate: [String], escluse: Set<String> = [],
                                progresso: (_ foto: Int, _ cartelle: Int) -> Void = { _, _ in }) -> Risultato {
        var r = Risultato(radice: radice.path)
        var dir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: radice.path, isDirectory: &dir), dir.boolValue else { return r }
        var illeggibili: [String] = []
        let e = FileManager.default.enumerator(
            at: radice, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { u, _ in illeggibili.append(u.path); return true })
        guard let e else { return r }
        var contati = 0
        while let u = e.nextObject() as? URL {
            let v = try? u.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
            if v?.isDirectory == true {
                let nome = u.lastPathComponent.lowercased()
                if tecniche.contains(nome) || saltate.contains(nome) || escluse.contains(u.path) || multimediali.contains(u.path) { e.skipDescendants() }
                continue
            }
            guard Immagini.estensioni.contains(u.pathExtension.lowercased()) else { continue }
            let f = FileFoto(percorso: u.path, dimensione: v?.fileSize ?? 0, mtime: v?.contentModificationDate?.timeIntervalSince1970 ?? 0)
            r.perCartella[u.deletingLastPathComponent().path, default: []].append(f)
            contati += 1
            if contati % 200 == 0 { progresso(contati, r.perCartella.count) }
        }
        r.illeggibili = illeggibili
        r.letta = true
        progresso(contati, r.perCartella.count)
        return r
    }

    /// Un RAW con lo stesso nome di un'altra foto della cartella (il suo JPG) resta una sola foto.
    static func senzaCompagniRAW(_ file: [FileFoto]) -> [FileFoto] {
        let base = { (p: String) in ((p as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased() }
        let altri = Set(file.filter { !Scrittura.eRAW(URL(fileURLWithPath: $0.percorso)) }.map { base($0.percorso) })
        return file.filter { !Scrittura.eRAW(URL(fileURLWithPath: $0.percorso)) || !altri.contains(base($0.percorso)) }
    }
}
