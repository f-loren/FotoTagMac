import CoreGraphics
import Foundation
import ImageIO

/// Tag fissi: calcolati da percorso, EXIF e colori, non dal modello. Ogni valore incerto è segnato «da verificare».
public struct TagFissi: Codable, Hashable, Sendable {
    public var origine: String?          // "analogica" / "digitale"; nil = sconosciuta
    public var biancoNero: Bool?
    public var anno: Int?
    public var mese: Int?
    public var giorno: Int?
    public var digitalizzata: String?    // "22 settembre 2025" se la data della cartella è quella della scansione
    public var rullini: [String] = []
    public var pellicole: [String] = []
    public var tiraggio: Int?
    public var contesto: [String] = []
    /// campi da far controllare all'utente: "origine", "tono", "data", "pellicola"
    public var daVerificare: Set<String> = []

    public init() {}

    static let mesi = Contesto.mesi

    /// Data come si scrive nel campo: «2025», «2025-12», «2025-12-11».
    public var testoData: String {
        guard let y = anno else { return "" }
        return String(y) + (mese.map { String(format: "-%02d", $0) } ?? "") + (mese != nil ? giorno.map { String(format: "-%02d", $0) } ?? "" : "")
    }

    /// Legge la data scritta a mano (numeri separati da qualsiasi segno); i valori fuori misura si scartano.
    public mutating func impostaData(_ s: String) {
        let n = s.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        anno = n.first.flatMap { (1800...2100).contains($0) ? $0 : nil }
        mese = n.count > 1 && (1...12).contains(n[1]) ? n[1] : nil
        giorno = n.count > 2 && mese != nil && (1...31).contains(n[2]) ? n[2] : nil
        daVerificare.remove("data")
    }

    /// Tag piatti come contesto.tags del prototipo (stesso ordine e stesse parole), nella lingua dei tag.
    public func parole(_ l: Lingua = .italiano) -> [String] {
        var t = [l.t(origine ?? "origine sconosciuta"), l.t(biancoNero == true ? "bianco e nero" : "colore")]
        if let d = digitalizzata { t.append("\(l.t("digitalizzata il")) \(l.data(d))") }
        if let y = anno { t.append(String(y)) }
        if let y = anno, let mo = mese { t.append("\(l.mesi[mo - 1]) \(y)") }
        if let y = anno, let mo = mese, let d = giorno { t.append("\(d) \(l.mesi[mo - 1]) \(y)") }
        if origine != "digitale" { t += rullini.map { "\(l.t("rullino")) \($0)" } }
        t += pellicole.map { "\(l.t("pellicola")) \($0)" }
        if let p = tiraggio { t.append("\(l.t("esposta a")) \(p) iso") }
        t += contesto
        var visti = Set<String>()
        return t.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && visti.insert($0).inserted }
    }

    /// Parole chiave gerarchiche come write_metadata del prototipo, nella lingua dei tag.
    public func gerarchia(_ l: Lingua = .italiano) -> [String] {
        var h = ["\(l.t("Origine"))|\(l.t(origine ?? "origine sconosciuta"))", "\(l.t("Tono"))|\(l.t(biancoNero == true ? "bianco e nero" : "colore"))"]
        if let y = anno { h.append("\(l.t("Data"))|\(y)" + (mese.map { "|\(l.mesi[$0 - 1])" } ?? "")) }
        if origine != "digitale" { h += rullini.map { "\(l.t("Rullino"))|\($0)" } }
        h += pellicole.map { "\(l.t("Pellicola"))|\($0)" }
        if let p = tiraggio { h.append("\(l.t("Esposta a"))|\(p) iso") }
        h += contesto.map { "\(l.t("Contesto"))|\($0)" }
        return h
    }

    /// Data per photoshop:DateCreated (parziale): solo se è quella dello scatto.
    public var dataScatto: String? {
        guard let y = anno else { return nil }
        return String(y) + (mese.map { String(format: "-%02d", $0) } ?? "") + (mese != nil ? giorno.map { String(format: "-%02d", $0) } ?? "" : "")
    }
}

public enum CalcoloFissi {
    public static let marcheScanner = ["noritsu", "frontier", "fujifilm frontier", "ez controller", "epson", "plustek", "imacon",
                                       "hasselblad flextight", "pakon", "reflecta", "pacific image"]
    /// saturazione media (0–255) sotto cui la foto è in bianco e nero, come BW_SAT nel prototipo
    public static let sogliaBN: Double = 12
    /// fascia di dubbio attorno alla soglia
    public static let dubbioBN: ClosedRange<Double> = 8...16

    public struct EXIF: Sendable {
        public var marca = "", modello = "", software = ""
        public var dataScatto: Date?
        /// Impronta dello scatto (D66): modello, data e centesimi dall'EXIF. Uguale nel RAW e nel JPG che ne deriva,
        /// anche se il JPG cambia nome. Nil senza data o modello (scansioni, file senza EXIF).
        public var scatto: String?
        public init() {}
    }

    public static func exif(_ url: URL) -> EXIF {
        var e = EXIF()
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return e }
        let tiff = p[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let ex = p[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        e.marca = (tiff[kCGImagePropertyTIFFMake] as? String ?? "").trimmingCharacters(in: .whitespaces)
        e.modello = (tiff[kCGImagePropertyTIFFModel] as? String ?? "").trimmingCharacters(in: .whitespaces)
        e.software = tiff[kCGImagePropertyTIFFSoftware] as? String ?? ""
        // ImageIO ricava una DateTimeOriginal anche da photoshop:DateCreated dell'XMP (es. «2026:02» → 1 febbraio):
        // quella non è la data dello scatto, quindi si usa solo se l'EXIF ha anche altri campi della fotocamera
        let soloDaXMP = ex.count == 1 && CGImageSourceCopyMetadataAtIndex(src, 0, nil).flatMap {
            CGImageMetadataCopyTagWithPath($0, nil, "photoshop:DateCreated" as CFString)
        } != nil
        if !soloDaXMP, let s = ex[kCGImagePropertyExifDateTimeOriginal] as? String {
            let f = DateFormatter(); f.dateFormat = "yyyy:MM:dd HH:mm:ss"; f.locale = Locale(identifier: "en_US_POSIX")
            e.dataScatto = f.date(from: String(s.prefix(19)))
            let sub = (ex[kCGImagePropertyExifSubsecTimeOriginal] as? String ?? "").filter(\.isNumber)
            e.scatto = impronta(modello: e.modello, data: s, centesimi: sub)
        }
        return e
    }

    /// «nikon d200|2025:03:30 10:21:49|41». Centesimi a due cifre: i programmi ne scrivono una, due o tre.
    /// shortcut: niente numero di serie né numero dello scatto, che ImageIO non legge da tutti i RAW (D200 senza serie)
    /// e che le esportazioni possono togliere; da aggiungere come spareggio se capitano due scatti uguali.
    public static func impronta(modello: String, data: String, centesimi: String) -> String? {
        let m = modello.lowercased().trimmingCharacters(in: .whitespaces)
        // senza centesimi due scatti di raffica nello stesso secondo avrebbero la stessa impronta: niente impronta
        guard !m.isEmpty, data.count >= 19, !centesimi.isEmpty else { return nil }
        return "\(m)|\(data.prefix(19))|\((centesimi + "00").prefix(2))"
    }

    /// Saturazione media HSV su 256×256, come saturation() del prototipo (PIL: S = (max-min)·255/max).
    public static func saturazione(_ img: CGImage) -> Double? {
        let lato = 256
        var px = [UInt8](repeating: 0, count: lato * lato * 4)
        guard let ctx = CGContext(data: &px, width: lato, height: lato, bitsPerComponent: 8, bytesPerRow: lato * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: lato, height: lato))
        var somma = 0.0
        for i in stride(from: 0, to: px.count, by: 4) {
            let mx = max(px[i], px[i + 1], px[i + 2]), mn = min(px[i], px[i + 1], px[i + 2])
            if mx > 0 { somma += Double(Int(mx) - Int(mn)) * 255 / Double(mx) }
        }
        return somma / Double(lato * lato)
    }

    /// Origine come decide_source del prototipo.
    public static func origine(_ c: ContestoCartella, _ e: EXIF) -> String? {
        if c.indizioPellicola { return "analogica" }
        let mm = "\(e.marca) \(e.modello)".lowercased()
        if marcheScanner.contains(where: { mm.contains($0) }) { return "analogica" }
        if let o = c.origineDaCartella { return o }
        if e.dataScatto != nil && !e.marca.isEmpty { return "digitale" }
        return nil
    }

    /// Calcola i tag fissi. `saturazione` nil = non nota (es. foto non leggibile).
    public static func calcola(percorso: String, profilo: Profilo, pellicole: TabellaPellicole,
                               exif e: EXIF, saturazione sat: Double?, originale: String? = nil) -> TagFissi {
        var c = Contesto.leggi(percorso, profilo: profilo, pellicole: pellicole)
        // come context_for nel prototipo: le cartelle dell'originale completano quelle del JPG
        if let o = originale { c = Originali.unisci(c, Contesto.leggi(o, profilo: profilo, pellicole: pellicole)) }
        var t = TagFissi()
        t.origine = origine(c, e)
        if t.origine == nil { t.daVerificare.insert("origine") }
        if let sat {
            t.biancoNero = sat < sogliaBN
            if dubbioBN.contains(sat) { t.daVerificare.insert("tono") }
        } else { t.daVerificare.insert("tono") }

        t.anno = c.anno; t.mese = c.mese; t.giorno = c.giorno
        if t.origine == "analogica" {
            // pellicola: la data nella cartella dell'importazione (o una cartella AAAAMMGG) è quella della scansione
            if c.dataImportazione, let y = c.anno, let mo = c.mese, let d = c.giorno {
                t.digitalizzata = "\(d) \(Contesto.mesi[mo - 1]) \(y)"
                t.anno = nil; t.mese = nil; t.giorno = nil
                t.daVerificare.insert("data")
            }
            if t.anno == nil { t.daVerificare.insert("data") }
        } else {
            // digitale: la data dello scatto (EXIF) se la cartella non la dice o il profilo lo preferisce
            if let d = e.dataScatto, t.anno == nil || !profilo.leggiStrutturaAnno {
                let k = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: d)
                t.anno = k.year; t.mese = k.month; t.giorno = k.day
            }
            if t.anno == nil { t.daVerificare.insert("data") }
        }
        t.rullini = c.rullini
        t.pellicole = c.pellicole
        if c.pellicole.contains(where: { !$0.contains(" ") || $0 == $0.lowercased() }) { t.daVerificare.insert("pellicola") }  // solo sigla
        t.tiraggio = c.tiraggio
        t.contesto = c.contesto
        return t
    }
}
