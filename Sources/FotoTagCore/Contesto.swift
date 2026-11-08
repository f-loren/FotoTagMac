import Foundation

/// Informazioni ricavate dal percorso di una foto (porting di contesto.parse del prototipo).
public struct ContestoCartella: Codable, Equatable, Sendable {
    public var anno: Int?
    public var mese: Int?
    public var giorno: Int?
    public var rullini: [String] = []
    public var pellicole: [String] = []
    public var tiraggio: Int?            // ISO a cui è stata esposta (push/pull)
    public var contesto: [String] = []
    public var indizioPellicola = false  // la cartella parla di pellicola (positivi, nome pellicola…)
    public var dataImportazione = false  // struttura Foto/AAAA/AAAA-MM-GG soggetto/RAW|JPG
    public var giornoDigitalizzazione: Int?  // giorno tolto perché è quello della scansione, non dello scatto
    public var origineDaCartella: String?    // "analogica"/"digitale" se una cartella lo dice
}

/// Regole per leggere i nomi delle cartelle. Sono dati, non codice: un fotografo può averne di sue.
public struct Profilo: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var nome: String
    public var descrizione: String
    /// cartelle tecniche che non dicono nulla sul contenuto
    public var cartelleIgnorate: [String]
    /// cartelle che indicano una scansione di pellicola
    public var cartellePellicola: [String]
    /// leggere data, rullino, pellicola e contesto da tutte le cartelle sotto l'anno (regole di Lorenzo)
    public var leggiStrutturaAnno: Bool
    /// usare il nome della cartella della foto come tag di contesto (profilo generico)
    public var cartellaComeContesto: Bool
    /// per la pellicola, una cartella AAAAMMGG è il giorno della digitalizzazione: si tiene solo il mese
    public var giornoCartellaPellicolaEDigitalizzazione: Bool
    /// sottocartelle che non si elencano (copie della stessa foto), in minuscolo; diverso da cartelleIgnorate,
    /// che vale per il contesto e contiene anche «jpg» e «raw», da elencare
    public var sottocartelleSaltate: [String] = []
    /// sigle delle pellicole nei nomi delle cartelle → nome completo da usare nei tag
    public var pellicole: [String: String] = TabellaPellicole.comune.nomi
    public var tabella: TabellaPellicole { TabellaPellicole(nomi: pellicole) }

    public static let generico = Profilo(
        id: "generico", nome: "Generico",
        descrizione: "Data dallo scatto (EXIF), nome della cartella come tag, pellicola solo con indizi chiari.",
        cartelleIgnorate: ["jpg", "jpeg", "raw", "export", "exports", "esportazioni", "edit", "originali", "selezione", "nuova cartella",
                           "untitled folder", "dcim", "pictures", "immagini", "foto", "photos", "desktop", "downloads", "documents"],
        cartellePellicola: ["negativi", "positivi", "scansioni", "pellicola", "analogica", "analogico", "film", "negatives", "scans"],
        leggiStrutturaAnno: false, cartellaComeContesto: true, giornoCartellaPellicolaEDigitalizzazione: true)

    public static func url() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FotoTag/profili.json")
    }

    /// Profili salvati; Generico c'è sempre ed è il primo. Al primo avvio le sigle di pellicole.json passano a Generico.
    /// Un file che c'è ma non si legge viene messo da parte con data e ora; se non si riesce, errore: chi chiama non salva sopra.
    public static func carica(da url: URL = url()) throws -> [Profilo] {
        var tutti: [Profilo] = []
        if FileManager.default.fileExists(atPath: url.path) {
            let d = try Data(contentsOf: url)
            if let p = try? JSONDecoder().decode([Profilo].self, from: d) { tutti = p } else {
                let ora = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
                try FileManager.default.moveItem(at: url, to: url.deletingPathExtension().appendingPathExtension("illeggibile-\(ora).json"))
            }
        }
        if !tutti.contains(where: { $0.id == generico.id }) {
            var g = generico
            let vecchie = url.deletingLastPathComponent().appendingPathComponent("pellicole.json")
            if let d = try? Data(contentsOf: vecchie), let o = try? JSONSerialization.jsonObject(with: d) as? [String: String] {
                g.pellicole = o.filter { !$0.key.hasPrefix("_") }
            }
            tutti.insert(g, at: 0)
        }
        return tutti
    }

    public static func salva(_ tutti: [Profilo], in url: URL = url()) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try e.encode(tutti).write(to: url, options: .atomic)
    }

    /// Un profilo esportato da «Esporta in un file…» (o scritto a mano): un solo oggetto JSON.
    public static func importa(_ url: URL) throws -> Profilo {
        let p = try JSONDecoder().decode(Profilo.self, from: Data(contentsOf: url))
        guard !p.id.isEmpty, !p.nome.trimmingCharacters(in: .whitespaces).isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        return p
    }

    public func esporta(_ url: URL) throws {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try e.encode(self).write(to: url, options: .atomic)
    }
}

extension Profilo {
    /// I campi con un valore di partenza possono mancare (file di versioni precedenti o scritti a mano).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let g = Profilo.generico
        id = try c.decode(String.self, forKey: .id)
        nome = try c.decode(String.self, forKey: .nome)
        descrizione = try c.decodeIfPresent(String.self, forKey: .descrizione) ?? ""
        cartelleIgnorate = try c.decodeIfPresent([String].self, forKey: .cartelleIgnorate) ?? g.cartelleIgnorate
        cartellePellicola = try c.decodeIfPresent([String].self, forKey: .cartellePellicola) ?? g.cartellePellicola
        leggiStrutturaAnno = try c.decodeIfPresent(Bool.self, forKey: .leggiStrutturaAnno) ?? g.leggiStrutturaAnno
        cartellaComeContesto = try c.decodeIfPresent(Bool.self, forKey: .cartellaComeContesto) ?? !leggiStrutturaAnno
        giornoCartellaPellicolaEDigitalizzazione = try c.decodeIfPresent(Bool.self, forKey: .giornoCartellaPellicolaEDigitalizzazione)
            ?? g.giornoCartellaPellicolaEDigitalizzazione
        sottocartelleSaltate = try c.decodeIfPresent([String].self, forKey: .sottocartelleSaltate) ?? []
        pellicole = try c.decodeIfPresent([String: String].self, forKey: .pellicole) ?? TabellaPellicole.comune.nomi
    }
}

/// Sigle delle pellicole nei nomi delle cartelle → nome completo (modificabile dall'utente).
public struct TabellaPellicole: Sendable {
    public var nomi: [String: String]
    public init(nomi: [String: String]) { self.nomi = nomi }

    /// Di base: i nomi commerciali completi delle pellicole più comuni; il resto lo aggiunge l'utente.
    public static let comune = TabellaPellicole(nomi: [
        "portra 160": "Kodak Portra 160", "portra 400": "Kodak Portra 400", "portra 800": "Kodak Portra 800",
        "gold 200": "Kodak Gold 200", "ektar 100": "Kodak Ektar 100", "tri-x 400": "Kodak Tri-X 400",
        "hp5": "Ilford HP5 Plus 400", "fp4": "Ilford FP4 Plus 125",
    ])

    public func nome(_ sigla: String) -> String {
        if let n = nomi[sigla], !n.isEmpty { return n }
        return sigla
    }
}

// MARK: - lettura del percorso

public enum Contesto {
    public static let mesi = ["gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno", "luglio", "agosto",
                              "settembre", "ottobre", "novembre", "dicembre"]
    static func numeroMese(_ s: String) -> Int? { mesi.firstIndex(of: s).map { $0 + 1 } }

    /// Regole sulle sigle delle pellicole: espressione → sigla ($1 = primo gruppo; ${1:-400} = valore se manca).
    static let regolePellicola: [(String, String)] = [
        (#"apx\s*-?\s*(100|400)"#, "apx $1"),
        (#"(?<![a-z])p\s*3200|t-?max\s*p?3200"#, "p3200"),
        (#"delta\s*(100|400|3200)"#, "delta $1"),
        (#"hp\s*5"#, "hp5"),
        (#"fp\s*4"#, "fp4"),
        (#"foma(?:pan)?\s*(\d{3})"#, "fomapan $1"),
        (#"superpan\s*(\d{3})"#, "superpan $1"),
        (#"retro\s*(80s|400s)"#, "retro $1"),
        (#"chs\s*100\s*(?:ii)?"#, "chs 100 ii"),
        (#"gothic\s*(\d{3})"#, "gothic $1"),
        (#"orto\s*(\d{3})"#, "orto $1"),
        (#"ultra\s*max(?:\s*(\d{3}))?"#, "ultramax ${1:-400}"),
        (#"portra\s*(\d{3})"#, "portra $1"),
        (#"ektar\s*(\d{3})?"#, "ektar 100"),
        (#"gold\s*(\d{3})"#, "gold $1"),
        (#"color\s*plus\s*(\d{3})?"#, "colorplus 200"),
        (#"tri-?\s*x"#, "tri-x 400"),
        (#"kentmere\s*(\d{3})"#, "kentmere $1"),
        (#"cinestill\s*(\d{3}[dt]?)"#, "cinestill $1"),
        (#"xp\s*2"#, "xp2"),
        (#"pan\s*f"#, "pan f"),
        (#"vision\s*3?\s*(50d|250d|200t|500t)"#, "vision3 $1"),
        (#"vision\s*3?\s*(250)"#, "vision3 250d"),
        (#"ferrania\s*p\s*30"#, "ferrania p30"),
    ]
    static let marchi = #"\b(agfa|rollei|ilford|kodak|fuji|fujifilm|adox|foma|ferrania|rullino|bn)\b"#

    // piccoli aiuti per le espressioni regolari (sintassi ICU, come Python per quello che serve qui)
    static func re(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p) }
    static func cerca(_ p: String, _ s: String) -> NSTextCheckingResult? {
        re(p).firstMatch(in: s, range: NSRange(s.startIndex..., in: s))
    }
    static func inizio(_ p: String, _ s: String) -> NSTextCheckingResult? {
        re(p).firstMatch(in: s, options: .anchored, range: NSRange(s.startIndex..., in: s))
    }
    static func intera(_ p: String, _ s: String) -> Bool { inizio("(?:" + p + ")$", s) != nil }
    static func gruppo(_ m: NSTextCheckingResult, _ i: Int, _ s: String) -> String? {
        guard i < m.numberOfRanges, let r = Range(m.range(at: i), in: s) else { return nil }
        return String(s[r])
    }
    static func togli(_ m: NSTextCheckingResult, _ s: String, sostituto: String = "") -> String {
        let r = Range(m.range, in: s)!
        return String(s[..<r.lowerBound]) + sostituto + String(s[r.upperBound...])
    }
    static func dopo(_ m: NSTextCheckingResult, _ s: String) -> String { String(s[Range(m.range, in: s)!.upperBound...]) }
    static func sostituisci(_ p: String, _ s: String, con t: String = "") -> String {
        re(p).stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: t)
    }
    /// strip(chars) di Python
    static func pulisci(_ s: String, _ caratteri: String) -> String { s.trimmingCharacters(in: CharacterSet(charactersIn: caratteri)) }

    /// '25-03-05 sieci' (aa-mm-gg) o '24-05-25 marvin' (gg-mm-aa): decide l'anno della cartella.
    static func dataInTesta(_ s: String, anno: Int?) -> ((Int, Int?, Int?), String)? {
        let aa = anno.map { $0 % 100 }
        if let m = inizio(#"((?:19|20)\d\d)-(\d{2})-(\d{2})\b[\s,-]*"#, s) {
            let y = Int(gruppo(m, 1, s)!)!, mo = Int(gruppo(m, 2, s)!)!, d = Int(gruppo(m, 3, s)!)!
            if (1...12).contains(mo) && (1...31).contains(d) { return ((y, mo, d), dopo(m, s)) }
        }
        if let m = inizio(#"(\d{2})-(\d{2})-(\d{2})\b[\s,-]*"#, s) {
            let a = Int(gruppo(m, 1, s)!)!, b = Int(gruppo(m, 2, s)!)!, c = Int(gruppo(m, 3, s)!)!
            var t: (Int, Int, Int)?
            if aa == nil || a == aa { t = (a, b, c) } else if c == aa { t = (c, b, a) } else { return nil }
            if let (y, mo, d) = t, (1...12).contains(mo) && (1...31).contains(d) { return ((2000 + y, mo, d), dopo(m, s)) }
        }
        if let m = inizio(#"(\d{2})-(\d{2})\b[\s,-]*"#, s) {
            let a = Int(gruppo(m, 1, s)!)!, b = Int(gruppo(m, 2, s)!)!
            if (aa == nil || a == aa) && (1...12).contains(b) { return ((2000 + a, b, nil), dopo(m, s)) }
        }
        if let m = inizio(#"((?:19|20)\d\d)(\d\d)(\d\d)(?:_\d+)?$"#, s) {
            return ((Int(gruppo(m, 1, s)!)!, Int(gruppo(m, 2, s)!)!, Int(gruppo(m, 3, s)!)!), "")
        }
        if let m = cerca(#"\b(\d\d)(\d\d)(\d\d)\b"#, s) {
            let d = Int(gruppo(m, 1, s)!)!, mo = Int(gruppo(m, 2, s)!)!, y = Int(gruppo(m, 3, s)!)!
            if let aa, y == aa, (1...12).contains(mo), (1...31).contains(d) {
                return ((2000 + y, mo, d), togli(m, s).trimmingCharacters(in: .whitespaces))
            }
        }
        return nil
    }

    static func siglaPellicola(_ m: NSTextCheckingResult, _ s: String, _ modello: String) -> String {
        var t = modello
        if let r = t.range(of: #"\$\{1:-([^}]*)\}"#, options: .regularExpression) {
            let difetto = String(t[r].dropFirst(5).dropLast())
            t.replaceSubrange(r, with: gruppo(m, 1, s) ?? difetto)
        }
        if t.contains("$1") { t = t.replacingOccurrences(of: "$1", with: gruppo(m, 1, s) ?? "") }
        return t
    }

    /// Legge il percorso (solo le cartelle, non il nome del file) con le regole del profilo.
    public static func leggi(_ percorso: String, profilo: Profilo, pellicole: TabellaPellicole) -> ContestoCartella {
        let parti = (percorso as NSString).pathComponents.dropFirst().dropLast().map { $0 }  // senza "/" e senza il file
        let basso = parti.map { $0.lowercased() }
        var o = ContestoCartella()
        o.origineDaCartella = basso.contains("analogica") ? "analogica" : basso.contains("digitale") ? "digitale" : nil

        guard profilo.leggiStrutturaAnno else { return leggiGenerico(parti, profilo: profilo, pellicole: pellicole, o) }

        guard let inizioAnno = parti.firstIndex(where: { intera(#"(19|20)\d\d"#, $0) }) else { return o }
        o.anno = Int(parti[inizioAnno])
        if parti.count >= 2, ["raw", "jpg"].contains(basso.last!), inizio(#"(19|20)\d\d-\d\d-\d\d"#, parti[parti.count - 2]) != nil {
            o.dataImportazione = true
        }
        for grezza in parti[(inizioAnno + 1)...] {
            o = leggiCartella(grezza, profilo: profilo, pellicole: pellicole, o)
        }
        return o
    }

    /// Una cartella sotto l'anno (corpo del ciclo di contesto.parse).
    static func leggiCartella(_ grezza: String, profilo: Profilo, pellicole: TabellaPellicole, _ ingresso: ContestoCartella) -> ContestoCartella {
        var o = ingresso
        var s = grezza.trimmingCharacters(in: .whitespaces).lowercased()
        if s.hasPrefix("wetransfer") || profilo.cartelleIgnorate.contains(s) || intera(#"\d{3}[a-z][a-z0-9_]{4}"#, s) {
            if profilo.cartellePellicola.contains(s) { o.indizioPellicola = true }
            return o
        }
        if profilo.cartellePellicola.contains(s) { o.indizioPellicola = true; return o }
        // mese, anche con aggiunte: 'marzo - alluvione'
        let primo = s.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "-" || $0 == "\t" })
        if let p = primo.first, let mm = numeroMese(String(p)) {
            o.mese = o.mese ?? mm
            // come re.split(r"[\s\-]+", s, 1): il resto dopo il primo gruppo di separatori
            if let m = inizio(#"[^\s\-]+[\s\-]+"#, s) { s = dopo(m, s) } else { s = "" }
        }
        if let m = inizio(#"(\d{1,2})°?\s+("# + mesi.joined(separator: "|") + #")\b\s*"#, s) {
            o.giorno = Int(gruppo(m, 1, s)!); o.mese = numeroMese(gruppo(m, 2, s)!); s = dopo(m, s)
        } else if let m = inizio(#"(\d{1,2})°\s*[+-]?\s*"#, s) {
            o.giorno = Int(gruppo(m, 1, s)!); s = dopo(m, s)
        }
        if let ((y, mo, d), resto) = dataInTesta(s, anno: o.anno) {
            o.anno = y; o.mese = mo ?? o.mese; o.giorno = d ?? o.giorno; s = resto
        }
        // '2026-10-05 praga - Ilford HP5 Plus@1600': pellicola scritta per intero dall'importazione
        if let m = cerca(#"\s+-\s+([^-@]+?)\s*@\s*(\d{2,4})\s*$"#, s) {
            let film = gruppo(m, 1, s)!.trimmingCharacters(in: .whitespaces)
            o.pellicole.append(pellicole.nome(film)); o.tiraggio = Int(gruppo(m, 2, s)!); o.indizioPellicola = true
            s = String(s[..<Range(m.range, in: s)!.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        for (p, modello) in regolePellicola {
            if let m = cerca(p, s) {
                o.pellicole.append(pellicole.nome(siglaPellicola(m, s, modello))); o.indizioPellicola = true
                s = togli(m, s, sostituto: " ").trimmingCharacters(in: .whitespaces)
            }
        }
        if let m = cerca(#"@\s*(\d{2,4})(?:\s*iso)?|(\d{3,4})\s*iso"#, s) {
            o.tiraggio = Int(gruppo(m, 1, s) ?? gruppo(m, 2, s) ?? ""); s = togli(m, s).trimmingCharacters(in: .whitespaces)
        }
        if cerca(marchi, s) != nil && cerca(#"\b(fuji|rullino)\b"#, s) != nil { o.indizioPellicola = true }
        s = pulisci(sostituisci(marchi, s), " -")
        if cerca(#"\b(anal|analogica|analogico|sviluppo|negativi|positivi)\b"#, s) != nil {
            o.indizioPellicola = true
            s = sostituisci(#"\b(anal|analogica|analogico)\b"#, s).trimmingCharacters(in: .whitespaces)
        }
        // rullino: tutta la cartella ('1048', 'v1') oppure in testa ('02 cascine', '04- prove obiettivo')
        if intera(#"[a-z]{0,3}\d{1,4}[a-z]{0,3}"#, s) { o.rullini.append(s); return o }
        if let m = inizio(#"(\d{1,2})[\s\-]+(.+)"#, s) { o.rullini.append(gruppo(m, 1, s)!); s = gruppo(m, 2, s)! }
        for pezzo in re(#"\s+[-+]\s+|\s*\+\s*|,\s*"#).splitta(s) {
            let c = sostituisci(#"\s+"#, pulisci(pezzo, " -_."), con: " ").trimmingCharacters(in: .whitespaces)
            if c.count > 2 && !c.allSatisfy(\.isNumber) && !profilo.cartelleIgnorate.contains(c) && !o.contesto.contains(c) {
                o.contesto.append(c)
            }
        }
        return o
    }

    /// Profilo generico: indizi di pellicola e date solo dove sono chiari, nome della cartella della foto come tag.
    static func leggiGenerico(_ parti: [String], profilo: Profilo, pellicole: TabellaPellicole, _ ingresso: ContestoCartella) -> ContestoCartella {
        var o = ingresso
        for p in parti {
            let s = p.lowercased()
            if profilo.cartellePellicola.contains(s) { o.indizioPellicola = true }
            for (r, modello) in regolePellicola where !o.indizioPellicola || true {
                if let m = cerca(r, s) {
                    let nome = pellicole.nome(siglaPellicola(m, s, modello))
                    if !o.pellicole.contains(nome) { o.pellicole.append(nome) }
                    o.indizioPellicola = true
                }
            }
            if let m = cerca(#"@\s*(\d{2,4})(?:\s*iso)?|(\d{3,4})\s*iso"#, s), !o.pellicole.isEmpty {
                o.tiraggio = Int(gruppo(m, 1, s) ?? gruppo(m, 2, s) ?? "")
            }
        }
        // data scritta all'inizio del nome della cartella della foto (AAAA-MM-GG …): vale come data dichiarata
        if let ultima = parti.last {
            let s = ultima.lowercased()
            if let ((y, mo, d), _) = dataInTesta(s, anno: nil), y >= 1900 { o.anno = y; o.mese = mo; o.giorno = d }
            if profilo.cartellaComeContesto, !profilo.cartelleIgnorate.contains(s) {
                var c = s
                if let ((_, _, _), resto) = dataInTesta(s, anno: nil) { c = resto }
                c = pulisci(c, " -_.")
                if c.count > 2 && !c.allSatisfy(\.isNumber) { o.contesto.append(c) }
            }
        }
        return o
    }
}

extension NSRegularExpression {
    /// re.split di Python (senza gruppi catturati).
    func splitta(_ s: String) -> [String] {
        var out: [String] = []
        var da = s.startIndex
        for m in matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            let r = Range(m.range, in: s)!
            out.append(String(s[da..<r.lowerBound]))
            da = r.upperBound
        }
        out.append(String(s[da...]))
        return out
    }
}
