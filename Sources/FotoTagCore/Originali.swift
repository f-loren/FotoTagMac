import Foundation

/// Collegamento JPG → originale (RAW, TIFF o scansione): porting di originali.py del prototipo.
/// Lavora solo su nomi, cartelle e date dei file (stat): non scarica nulla dal disco in cloud.
/// I numeri della fotocamera (DSC_0066) si ripetono negli anni: il nome da solo non basta mai.
public enum Originali {
    /// priorità: prima il RAW, poi TIFF, poi JPG
    public static let priorita: [String: Int] = [
        "nef": 0, "arw": 0, "nrw": 0, "dng": 0, "cr2": 0, "cr3": 0, "raf": 0, "orf": 0, "rw2": 0,
        "tif": 1, "tiff": 1, "jpg": 2, "jpeg": 2,
    ]
    static let estensioniImmagine = Set(priorita.keys).union(["png", "heic"])
    public static let soloRAW = Set(priorita.filter { $0.value == 0 }.keys)

    public enum Livello: String, Codable, Sendable, CaseIterable {
        case sicuro, probabile, incerto, nessuno
    }

    /// Voce dell'indice degli originali.
    public struct Voce: Sendable {
        public var percorso: String
        public var radice: String        // stem
        public var ext: String
        public var anno: Int?
        public var mese: Int?
        public var mtime: Double
        public var scatto: String?       // impronta dello scatto (D66), solo per i RAW letti
        public init(percorso: String, radice: String, ext: String, anno: Int?, mese: Int?, mtime: Double, scatto: String? = nil) {
            self.percorso = percorso; self.radice = radice; self.ext = ext; self.anno = anno; self.mese = mese; self.mtime = mtime
            self.scatto = scatto
        }
    }

    /// 'DSC_0247.NEF.jpg', 'DSC_0247-2.jpg', 'DSC_0247 copia.jpg' → 'dsc_0247'.
    public static func radice(_ nome: String) -> String {
        var s = nome
        while true {
            let e = (s as NSString).pathExtension.lowercased()
            guard !e.isEmpty, estensioniImmagine.contains(e) else { break }
            s = (s as NSString).deletingPathExtension
        }
        s = s.replacingOccurrences(of: #"(\s*copia.*|\s*\(\d+\)|-(modifica|edit|bn|colore).*|[-_ ]\d{1,2})$"#,
                                   with: "", options: [.regularExpression, .caseInsensitive])
        return s.lowercased()
    }

    /// Voce dell'indice per un file (solo stat e percorso).
    public static func voce(_ url: URL, mtime: Double, profilo: Profilo, pellicole: TabellaPellicole) -> Voce {
        let c = Contesto.leggi(url.path, profilo: profilo, pellicole: pellicole)
        return Voce(percorso: url.path, radice: radice(url.lastPathComponent), ext: url.pathExtension.lowercased(),
                    anno: c.anno, mese: c.mese, mtime: mtime)
    }

    /// Visita una cartella degli originali (senza aprire i file). `soloRaw`: per le cartelle di esportazioni.
    public static func elenca(_ radiceCartella: URL, soloRaw: Bool, _ ciascuno: (URL, Double) -> Void) {
        let ammesse = soloRaw ? soloRAW : Set(priorita.keys)
        guard let e = FileManager.default.enumerator(at: radiceCartella, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                                                     options: [.skipsHiddenFiles]) else { return }
        for case let u as URL in e {
            guard ammesse.contains(u.pathExtension.lowercased()) else { continue }
            let v = try? u.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard v?.isRegularFile == true else { continue }
            ciascuno(u, v?.contentModificationDate?.timeIntervalSince1970 ?? 0)
        }
    }

    static let oreForte = 2.0, oreVicine = 36.0  // la data del RAW coincide con lo scatto (Sony ~1 h di scarto)

    /// Trova l'originale di `percorso` tra le voci con la stessa radice. `scatto`: data EXIF del JPG.
    public static func trova(_ percorso: String, scatto: Date?, candidati righe: [Voce], profilo: Profilo,
                             pellicole: TabellaPellicole) -> (String?, Livello) {
        let assoluto = (percorso as NSString).standardizingPath
        let rows = righe.filter { ($0.percorso as NSString).standardizingPath != assoluto }
        guard !rows.isEmpty else { return (nil, .nessuno) }
        let ctx = Contesto.leggi(percorso, profilo: profilo, pellicole: pellicole)
        var perCartella: [String: [Voce]] = [:]
        var ordine: [String] = []
        for r in rows {
            let d = (r.percorso as NSString).deletingLastPathComponent
            if perCartella[d] == nil { ordine.append(d) }
            perCartella[d, default: []].append(r)
        }
        struct Cand { var punti: Int; var ore: Double?; var percorso: String }
        var cands: [Cand] = []
        for d in ordine {
            let rs = perCartella[d]!
            let best = rs.min { (priorita[$0.ext] ?? 9) < (priorita[$1.ext] ?? 9) }!
            var punti = 0
            if let y = ctx.anno, best.anno == y { punti += 2 }
            if let m = ctx.mese, best.mese == m { punti += 2 }
            if !ctx.rullini.isEmpty, ctx.rullini.contains(where: { (d.lowercased() + "/").contains("/\($0)/") }) { punti += 1 }
            let ore = scatto.map { abs(best.mtime - $0.timeIntervalSince1970) / 3600 }
            cands.append(Cand(punti: punti, ore: ore, percorso: best.percorso))
        }
        let nome = radice((percorso as NSString).lastPathComponent)
        let generico = nome.range(of: #"^\d{1,4}[a-z]?$"#, options: .regularExpression) != nil  // '11.jpg' dei laboratori

        // struttura dell'importazione: .../AAAA-MM-GG soggetto/JPG/x.jpg ↔ .../RAW/x.NEF
        let qui = (percorso as NSString).deletingLastPathComponent
        if (qui as NSString).lastPathComponent.lowercased() == "jpg" {
            let su = (qui as NSString).deletingLastPathComponent
            let fratelli = cands.filter {
                let p = ($0.percorso as NSString).deletingLastPathComponent
                return (p as NSString).lastPathComponent.lowercased() == "raw" && (p as NSString).deletingLastPathComponent == su
            }
            if fratelli.count == 1 { return (fratelli[0].percorso, .sicuro) }
        }

        if scatto != nil {
            var forti = cands.filter { $0.ore! <= oreForte }
            if forti.count == 1 { return (forti[0].percorso, .sicuro) }
            if forti.count > 1 {
                forti = ordinaStabile(forti) { ($0.punti, -$0.ore!) > ($1.punti, -$1.ore!) }
                return (forti[0].percorso, forti[0].punti - forti[1].punti >= 2 ? .probabile : .incerto)
            }
            let vicini = ordinaStabile(cands.filter { $0.ore! <= oreVicine }) { ($0.punti, -$0.ore!) > ($1.punti, -$1.ore!) }
            if let v = vicini.first { return (v.percorso, vicini.count == 1 ? .probabile : .incerto) }
            return (nil, .nessuno)  // data diversa: stesso nome ma un'altra foto
        }

        cands = ordinaStabile(cands) { $0.punti > $1.punti }
        if cands[0].punti < 4 && (generico || cands.count > 1) { return (nil, .nessuno) }
        if cands.count == 1 { return (cands[0].percorso, cands[0].punti >= 4 ? .probabile : .incerto) }
        return (cands[0].percorso, cands[0].punti - cands[1].punti >= 2 ? .probabile : .incerto)
    }

    /// sort() di Python è stabile: a parità resta l'ordine originale.
    static func ordinaStabile<T>(_ a: [T], _ prima: (T, T) -> Bool) -> [T] {
        a.enumerated().sorted { x, y in
            if prima(x.element, y.element) { return true }
            if prima(y.element, x.element) { return false }
            return x.offset < y.offset
        }.map(\.element)
    }

    /// merge_context del prototipo: unisce il contesto della cartella del JPG con quello dell'originale.
    public static func unisci(_ ctx: ContestoCartella, _ raw: ContestoCartella) -> ContestoCartella {
        var o = ctx
        func unici(_ l: [String]) -> [String] { var v = Set<String>(); return l.filter { v.insert($0).inserted } }
        o.rullini = unici(ctx.rullini + raw.rullini)
        o.pellicole = unici(ctx.pellicole + raw.pellicole)
        o.contesto = unici(ctx.contesto + raw.contesto)
        o.indizioPellicola = ctx.indizioPellicola || raw.indizioPellicola
        o.tiraggio = ctx.tiraggio ?? raw.tiraggio
        // la data della cartella dell'originale è quella di scatto solo per il digitale: per la pellicola
        // .../Analogica/2025/settembre/20250922/ è il giorno della digitalizzazione
        let rawPellicola = raw.indizioPellicola || raw.origineDaCartella == "analogica" || ctx.indizioPellicola
        if raw.anno == ctx.anno && !rawPellicola && (ctx.mese == nil || (raw.mese == ctx.mese && ctx.giorno == nil)) {
            o.mese = raw.mese ?? ctx.mese
            o.giorno = raw.giorno
        }
        o.origineDaCartella = ctx.origineDaCartella ?? raw.origineDaCartella
        return o
    }
}
