import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Scrive tag e didascalia nei file. Regole:
/// - JPG/TIFF/HEIC/PNG: metadati dentro il file, senza ricodificare i pixel (CGImageDestinationCopyImageSource);
/// - RAW: il file non si tocca mai; si crea o aggiorna il sidecar NOME.xmp accanto (come il prototipo);
/// - parole chiave aggiunte a quelle esistenti: si tolgono solo quelle scritte in precedenza da FotoTag;
/// - didascalia: si scrive solo se il file non ne ha una diversa scritta da qualcun altro
///   (quella messa dalla fotocamera, tipo «SONY DSC», conta come vuota: D59);
/// - file temporaneo + sostituzione, poi rilettura per verificare.
public enum Scrittura {
    public static let estensioniRAW: Set<String> = ["nef", "nrw", "arw", "srf", "sr2", "cr2", "cr3", "crw", "dng", "raf",
                                                    "orf", "rw2", "pef", "srw", "x3f", "3fr", "iiq", "rwl"]
    static let nsDC = "http://purl.org/dc/elements/1.1/" as CFString
    static let nsLR = "http://ns.adobe.com/lightroom/1.0/" as CFString

    /// Cosa scrivere per una foto.
    public struct Richiesta: Sendable {
        public var file: URL
        public var parole: [String]
        public var didascalia: String
        public var gerarchia: [String]           // es. "Contenuto|luogo|spiaggia"
        public var paroleGiaScritte: [String]    // scritte da FotoTag l'ultima volta: possono essere tolte
        public var gerarchiaGiaScritta: [String]
        public var didascaliaGiaScritta: String?
        /// originale collegato: il sidecar va accanto a lui. nil = RAW con lo stesso nome nella stessa cartella, se c'è
        public var raw: URL?
        public init(file: URL, parole: [String], didascalia: String, gerarchia: [String],
                    paroleGiaScritte: [String] = [], gerarchiaGiaScritta: [String] = [], didascaliaGiaScritta: String? = nil) {
            self.file = file; self.parole = parole; self.didascalia = didascalia; self.gerarchia = gerarchia
            self.paroleGiaScritte = paroleGiaScritte; self.gerarchiaGiaScritta = gerarchiaGiaScritta
            self.didascaliaGiaScritta = didascaliaGiaScritta
        }
    }

    public struct Esito: Sendable {
        public var fileScritti: [URL] = []
        public var parole: [String] = []          // parole chiave finali nel file
        public var paroleAltrui: [String] = []    // già presenti nel file, conservate
        public var didascaliaScritta: String?     // nil se lasciata quella esistente
        public var avvisi: [String] = []
    }

    public static func eRAW(_ u: URL) -> Bool { estensioniRAW.contains(u.pathExtension.lowercased()) }

    /// RAW con lo stesso nome nella stessa cartella del JPG (l'unico abbinamento sicuro per ora).
    public static func rawAccanto(_ jpg: URL) -> URL? {
        let base = jpg.deletingPathExtension().lastPathComponent
        let dir = jpg.deletingLastPathComponent()
        let file = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return file.first { eRAW($0) && $0.deletingPathExtension().lastPathComponent == base }
    }

    /// Come si chiama il file .xmp accanto al RAW: i programmi seguono due convenzioni.
    public enum NomeSidecar: String, CaseIterable, Sendable {
        case lightroom   // DSC_1234.xmp (Lightroom, Photomator, Capture One, il prototipo)
        case darktable   // DSC_1234.NEF.xmp (darktable, digiKam)
        public var descrizione: String {
            switch self {
            case .lightroom: "Lightroom / Capture One (DSC_1234.xmp)"
            case .darktable: "darktable (DSC_1234.NEF.xmp)"
            }
        }
    }

    public static func sidecar(di raw: URL) -> URL { raw.deletingPathExtension().appendingPathExtension("xmp") }
    public static func sidecarDarktable(di raw: URL) -> URL { raw.appendingPathExtension("xmp") }

    /// Sidecar da scrivere: quelli della convenzione scelta, più quelli che esistono già (si aggiornano sempre,
    /// così un altro programma non resta con tag vecchi).
    public static func sidecars(di raw: URL, nome: NomeSidecar) -> [URL] {
        let lr = sidecar(di: raw), dt = sidecarDarktable(di: raw)
        let fm = FileManager.default
        var out: [URL] = []
        if nome == .lightroom || fm.fileExists(atPath: lr.path) { out.append(lr) }
        if nome == .darktable || fm.fileExists(atPath: dt.path) { out.append(dt) }
        return out
    }

    // MARK: lettura

    static func lista(_ m: CGImageMetadata, _ percorso: String) -> [String] {
        guard let tag = CGImageMetadataCopyTagWithPath(m, nil, percorso as CFString),
              let v = CGImageMetadataTagCopyValue(tag) else { return [] }
        if let a = v as? [CGImageMetadataTag] { return a.compactMap { CGImageMetadataTagCopyValue($0) as? String } }
        if let a = v as? [String] { return a }
        if let s = v as? String { return [s] }
        return []
    }

    /// Didascalie che la fotocamera scrive da sola in ogni foto: non sono di nessuno, si possono sostituire.
    static let segnaposti: Set<String> = ["sony dsc", "olympus digital camera", "digital camera", "kodak digital still camera",
                                          "minolta digital camera", "konica minolta digital camera", "samsung digital camera",
                                          "exif_jpeg_picture"]
    static func segnaposto(_ s: String) -> Bool {
        segnaposti.contains(s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    /// Didascalia esistente come la vede la regola di scrittura: senza spazi ai lati, vuota se è un segnaposto.
    static func esistente(_ s: String?) -> String {
        let t = s?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return segnaposto(t) ? "" : t
    }

    static func didascalia(_ m: CGImageMetadata) -> String? {
        guard let tag = CGImageMetadataCopyTagWithPath(m, nil, "dc:description" as CFString),
              let v = CGImageMetadataTagCopyValue(tag) else { return nil }
        if let s = v as? String { return s }
        if let a = v as? [CGImageMetadataTag] { return a.compactMap { CGImageMetadataTagCopyValue($0) as? String }.first }
        if let d = v as? [String: Any] { return (d["x-default"] ?? d.values.first) as? String }
        return nil
    }

    /// Parole chiave, gerarchia e didascalia presenti in un file immagine o in un .xmp.
    public static func leggi(_ u: URL) -> (parole: [String], gerarchia: [String], didascalia: String?) {
        guard let m = metadati(u) else { return ([], [], nil) }
        return (lista(m, "dc:subject"), lista(m, "lr:hierarchicalSubject"), didascalia(m))
    }

    static func metadati(_ u: URL) -> CGImageMetadata? {
        if u.pathExtension.lowercased() == "xmp" {
            guard let d = try? Data(contentsOf: u) else { return nil }
            return CGImageMetadataCreateFromXMPData(d as CFData)
        }
        guard let src = CGImageSourceCreateWithURL(u as CFURL, nil) else { return nil }
        return CGImageSourceCopyMetadataAtIndex(src, 0, nil)
    }

    // MARK: scrittura

    static func unisci(esistenti: [String], giaScritte: [String], nuove: [String]) -> (finali: [String], altrui: [String]) {
        let altrui = esistenti.filter { !giaScritte.contains($0) && !nuove.contains($0) }
        var finali = altrui
        for n in nuove where !finali.contains(n) { finali.append(n) }
        return (finali, altrui)
    }

    static func impostaLista(_ m: CGMutableImageMetadata, _ ns: CFString, _ prefisso: String, _ nome: String, _ v: [String]) {
        let percorso = "\(prefisso):\(nome)" as CFString
        CGImageMetadataRemoveTagWithPath(m, nil, percorso)
        guard !v.isEmpty, let tag = CGImageMetadataTagCreate(ns, prefisso as CFString, nome as CFString, .arrayUnordered, v as CFArray)
        else { return }
        CGImageMetadataSetTagWithPath(m, nil, percorso, tag)
    }

    /// Prepara i metadati da scrivere, partendo da quelli esistenti.
    static func prepara(_ esistenti: CGImageMetadata?, _ r: Richiesta, esito: inout Esito) -> CGMutableImageMetadata {
        let m = esistenti.flatMap { CGImageMetadataCreateMutableCopy($0) } ?? CGImageMetadataCreateMutable()
        CGImageMetadataRegisterNamespaceForPrefix(m, nsLR, "lr" as CFString, nil)
        let (parole, altrui) = unisci(esistenti: esistenti.map { lista($0, "dc:subject") } ?? [],
                                      giaScritte: r.paroleGiaScritte, nuove: r.parole)
        let (gerarchia, _) = unisci(esistenti: esistenti.map { lista($0, "lr:hierarchicalSubject") } ?? [],
                                    giaScritte: r.gerarchiaGiaScritta, nuove: r.gerarchia)
        impostaLista(m, nsDC, "dc", "subject", parole)
        impostaLista(m, nsLR, "lr", "hierarchicalSubject", gerarchia)
        esito.parole = parole
        esito.paroleAltrui = altrui
        let attuale = esistente(esistenti.flatMap { didascalia($0) })
        let nuova = r.didascalia.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nuova.isEmpty {
            if attuale.isEmpty || attuale == nuova || attuale == r.didascaliaGiaScritta {
                // dc:description (testo alternativo) e IPTC Caption-Abstract restano allineati;
                // la vecchia va tolta prima, altrimenti ImageIO lascia un rdf:Alt vuoto
                CGImageMetadataRemoveTagWithPath(m, nil, "dc:description" as CFString)
                CGImageMetadataSetValueMatchingImageProperty(m, kCGImagePropertyIPTCDictionary,
                                                             kCGImagePropertyIPTCCaptionAbstract, nuova as CFString)
                esito.didascaliaScritta = nuova
            } else {
                esito.avvisi.append(String(localized: "\(r.file.lastPathComponent): c'era già una didascalia diversa, l'ho lasciata"))
            }
        }
        return m
    }

    /// File che `scrivi` legge: sul disco in cloud vanno riportati sul Mac prima. Il RAW no, si tocca solo il sidecar.
    public static func daPortareSulMac(_ r: Richiesta, nomeSidecar: NomeSidecar) -> [URL] {
        guard let originale = r.raw ?? rawAccanto(r.file) else { return [r.file] }
        return [r.file] + (eRAW(originale) ? sidecars(di: originale, nome: nomeSidecar) : [originale])
    }

    /// Scrive una foto (e il sidecar del RAW accanto, se c'è). `copiaDiSicurezza`: cartella dove copiare
    /// gli originali prima di modificarli (nil = nessuna copia).
    public static func scrivi(_ r: Richiesta, copiaDiSicurezza: URL? = nil, nomeSidecar: NomeSidecar = .lightroom) throws -> Esito {
        var esito = Esito()
        let fm = FileManager.default
        if eRAW(r.file) { throw errore(String(localized: "\(r.file.lastPathComponent): i RAW non si modificano, si scrive solo il .xmp")) }

        // 1. immagine: metadati nel file, pixel invariati
        guard let src = CGImageSourceCreateWithURL(r.file as CFURL, nil), let tipo = CGImageSourceGetType(src) else {
            throw errore(String(localized: "\(r.file.lastPathComponent): file illeggibile"))
        }
        let m = prepara(CGImageSourceCopyMetadataAtIndex(src, 0, nil), r, esito: &esito)
        if let copia = copiaDiSicurezza { try copiaPrima(r.file, in: copia) }
        let tmp = r.file.deletingLastPathComponent().appendingPathComponent(".fototag-\(UUID().uuidString).\(r.file.pathExtension)")
        guard let dest = CGImageDestinationCreateWithURL(tmp as CFURL, tipo, CGImageSourceGetCount(src), nil) else {
            throw errore(String(localized: "\(r.file.lastPathComponent): impossibile creare il file temporaneo (cartella in sola lettura?)"))
        }
        var err: Unmanaged<CFError>?
        let opzioni = [kCGImageDestinationMetadata: m, kCGImageDestinationMergeMetadata: true] as CFDictionary
        guard CGImageDestinationCopyImageSource(dest, src, opzioni, &err) else {
            try? fm.removeItem(at: tmp)
            let dettaglio = err.map { "\($0.takeRetainedValue())" } ?? ""
            throw errore(String(localized: "\(r.file.lastPathComponent): scrittura non riuscita \(dettaglio)"))
        }
        if tipo as String == UTType.jpeg.identifier { try correggiAPP13(tmp) }
        guard pixelUguali(r.file, tmp, jpeg: tipo as String == UTType.jpeg.identifier) else {
            try? fm.removeItem(at: tmp)
            throw errore(String(localized: "\(r.file.lastPathComponent): la scrittura avrebbe cambiato l'immagine, il file non è stato modificato"))
        }
        try verifica(tmp, esito, nome: r.file.lastPathComponent, eliminaSeSbagliato: true)
        if let permessi = try? fm.attributesOfItem(atPath: r.file.path)[.posixPermissions] {
            try? fm.setAttributes([.posixPermissions: permessi], ofItemAtPath: tmp.path)
        }
        _ = try fm.replaceItemAt(r.file, withItemAt: tmp)
        try verifica(r.file, esito, nome: r.file.lastPathComponent, eliminaSeSbagliato: false)
        esito.fileScritti.append(r.file)
        aggiornaSpotlight(r.file)

        // 2. RAW accanto con lo stesso nome: solo il sidecar .xmp
        let originale = r.raw ?? rawAccanto(r.file)
        // una scansione TIFF/JPG collegata come originale riceve i tag dentro il file, non in un sidecar
        if let o = originale, !eRAW(o) {
            var r2 = r; r2.file = o; r2.raw = nil
            if o.standardizedFileURL != r.file.standardizedFileURL, rawAccanto(o) == nil {
                let e2 = try scrivi(r2, copiaDiSicurezza: copiaDiSicurezza, nomeSidecar: nomeSidecar)
                esito.fileScritti += e2.fileScritti; esito.avvisi += e2.avvisi
            }
            return esito
        }
        for xmp in originale.map({ sidecars(di: $0, nome: nomeSidecar) }) ?? [] {
            let c = try aggiornaSidecar(xmp, r, copiaDiSicurezza: copiaDiSicurezza)
            esito.fileScritti.append(xmp)
            esito.avvisi += c
        }
        return esito
    }

    /// Aggiorna (o crea) un sidecar .xmp toccando solo parole chiave, gerarchia e didascalia.
    static func aggiornaSidecar(_ xmp: URL, _ r: Richiesta, copiaDiSicurezza: URL?) throws -> [String] {
        let fm = FileManager.default
        let dati = fm.fileExists(atPath: xmp.path) ? try Data(contentsOf: xmp) : nil
        let attuale: SidecarXMP.Contenuto
        do { attuale = try SidecarXMP.leggi(dati) } catch {
            return [String(localized: "\(xmp.lastPathComponent): sidecar esistente non leggibile, non l'ho toccato")]
        }
        var avvisi: [String] = []
        let parole = unisci(esistenti: attuale.parole, giaScritte: r.paroleGiaScritte, nuove: r.parole).finali
        let gerarchia = unisci(esistenti: attuale.gerarchia, giaScritte: r.gerarchiaGiaScritta, nuove: r.gerarchia).finali
        var didascalia: String?
        let vecchia = esistente(attuale.didascalia)
        let nuova = r.didascalia.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nuova.isEmpty {
            if vecchia.isEmpty || vecchia == nuova || vecchia == r.didascaliaGiaScritta { didascalia = nuova }
            else { avvisi.append(String(localized: "\(xmp.lastPathComponent): c'era già una didascalia diversa, l'ho lasciata")) }
        }
        let nuovo = try SidecarXMP.scrivi(dati, .init(parole: parole, gerarchia: gerarchia, didascalia: didascalia))
        if dati != nil, let copia = copiaDiSicurezza { try copiaPrima(xmp, in: copia) }
        try nuovo.write(to: xmp, options: .atomic)
        let letto = try SidecarXMP.leggi(try Data(contentsOf: xmp))
        let mancano = parole.filter { !letto.parole.contains($0) }
        if !mancano.isEmpty || (didascalia != nil && letto.didascalia != didascalia) {
            if let dati { try dati.write(to: xmp, options: .atomic) }  // rimette com'era
            throw errore(String(localized: "\(xmp.lastPathComponent): verifica fallita"))
        }
        return avvisi
    }

    /// ImageIO scrive le risorse Photoshop (APP13, dove sta l'IPTC) senza il byte di riempimento quando la
    /// lunghezza è dispari: gli altri programmi le leggono come rovinate. Qui si aggiunge il byte mancante.
    static func correggiAPP13(_ u: URL) throws {
        var d = try Data(contentsOf: u)
        var cambiato = false
        var i = 2
        while i + 4 <= d.count, d[i] == 0xFF {
            let marcatore = d[i + 1]
            if marcatore == 0xDA || marcatore == 0xD9 { break }  // inizio dei dati immagine
            let lunghezza = Int(d[i + 2]) << 8 | Int(d[i + 3])
            if marcatore == 0xED, let nuovo = correggiRisorse(d.subdata(in: (i + 4)..<(i + 2 + lunghezza))) {
                guard nuovo.count + 2 <= 0xFFFF else { break }
                d.replaceSubrange((i + 4)..<(i + 2 + lunghezza), with: nuovo)
                d[i + 2] = UInt8((nuovo.count + 2) >> 8)
                d[i + 3] = UInt8((nuovo.count + 2) & 0xFF)
                cambiato = true
                i += 2 + nuovo.count + 2
                continue
            }
            i += 2 + lunghezza
        }
        if cambiato { try d.write(to: u, options: .atomic) }
    }

    /// Contenuto di un APP13 corretto, o nil se era già a posto (o non è un blocco Photoshop).
    static func correggiRisorse(_ seg: Data) -> Data? {
        let intestazione = Data("Photoshop 3.0\0".utf8)
        guard seg.starts(with: intestazione) else { return nil }
        let b = [UInt8](seg)
        var out = [UInt8](intestazione)
        var j = intestazione.count
        var cambiato = false
        while j + 12 <= b.count, b[j..<(j + 4)].elementsEqual(Array("8BIM".utf8)) {
            let n = Int(b[j + 6])
            var k = j + 7 + n
            if (1 + n) % 2 == 1 { k += 1 }
            guard k + 4 <= b.count else { return nil }
            let size = Int(b[k]) << 24 | Int(b[k + 1]) << 16 | Int(b[k + 2]) << 8 | Int(b[k + 3])
            let fine = k + 4 + size
            guard fine <= b.count else { return nil }
            out += b[j..<fine]
            j = fine
            if size % 2 == 1 {
                if j < b.count && b[j] == 0 && (j + 1 == b.count || b[(j + 1)...].starts(with: Array("8BIM".utf8))) {
                    out.append(0); j += 1  // riempimento già presente
                } else {
                    out.append(0); cambiato = true  // riempimento mancante: lo aggiunge
                }
            }
        }
        out += b[j...]
        return cambiato ? Data(out) : nil
    }

    /// Vero se l'immagine di `b` è identica a quella di `a`. JPEG: dati compressi (da SOS a EOI) byte per byte;
    /// altri formati: pixel decodificati di ogni immagine del file.
    static func pixelUguali(_ a: URL, _ b: URL, jpeg: Bool) -> Bool {
        if jpeg {
            guard let da = try? Data(contentsOf: a, options: .mappedIfSafe), let db = try? Data(contentsOf: b, options: .mappedIfSafe),
                  let sa = scansioneJPEG(da), let sb = scansioneJPEG(db) else { return false }
            return da[sa] == db[sb]
        }
        guard let sa = CGImageSourceCreateWithURL(a as CFURL, nil), let sb = CGImageSourceCreateWithURL(b as CFURL, nil),
              CGImageSourceGetCount(sa) == CGImageSourceGetCount(sb) else { return false }
        for i in 0..<CGImageSourceGetCount(sa) {
            guard let ia = CGImageSourceCreateImageAtIndex(sa, i, nil), let ib = CGImageSourceCreateImageAtIndex(sb, i, nil),
                  ia.width == ib.width, ia.height == ib.height, ia.bitsPerPixel == ib.bitsPerPixel, ia.bytesPerRow == ib.bytesPerRow,
                  let pa = ia.dataProvider?.data, let pb = ib.dataProvider?.data, pa as Data == pb as Data else { return false }
        }
        return true
    }

    /// Posizione dei dati immagine di un JPEG: dal primo SOS (FFDA) al primo EOI (FFD9) che lo segue, incluso.
    static func scansioneJPEG(_ d: Data) -> Range<Int>? {
        let b = d.startIndex
        guard d.count > 4, d[b] == 0xFF, d[b + 1] == 0xD8 else { return nil }
        var i = b + 2
        while i + 4 <= d.endIndex, d[i] == 0xFF {
            let marcatore = d[i + 1]
            if marcatore == 0xFF { i += 1; continue }  // byte di riempimento
            if marcatore == 0xDA { break }
            i += 2 + (Int(d[i + 2]) << 8 | Int(d[i + 3]))
        }
        guard i + 1 < d.endIndex, d[i] == 0xFF, d[i + 1] == 0xDA,
              let eoi = d[i...].firstRange(of: Data([0xFF, 0xD9])) else { return nil }
        return i..<eoi.upperBound
    }

    static func verifica(_ u: URL, _ e: Esito, nome: String, eliminaSeSbagliato: Bool) throws {
        let letto = leggi(u)
        let mancano = e.parole.filter { !letto.parole.contains($0) }
        let didascaliaOK = e.didascaliaScritta == nil || letto.didascalia == e.didascaliaScritta
        if !mancano.isEmpty || !didascaliaOK {
            if eliminaSeSbagliato { try? FileManager.default.removeItem(at: u) }
            let elenco = mancano.joined(separator: ", ")
            throw errore(didascaliaOK ? String(localized: "\(nome): verifica fallita, mancano \(elenco)")
                         : String(localized: "\(nome): verifica fallita, mancano \(elenco) e la didascalia"))
        }
    }

    /// Una cartella per ogni scrittura, con il nome della data e ora. Fino all'8/11/2026 si chiamava «Copie di sicurezza»:
    /// al primo uso la vecchia cartella prende il nome nuovo, così le copie restano e la pulizia dei 5 giorni le trova.
    /// shortcut: se esistono già tutte e due la vecchia resta dov'è, a mano; succede solo con due versioni di FotoTag usate insieme.
    public static let cartellaCopie: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FotoTag")
        let nuova = base.appendingPathComponent("Backups"), vecchia = base.appendingPathComponent("Copie di sicurezza")
        if FileManager.default.fileExists(atPath: vecchia.path), !FileManager.default.fileExists(atPath: nuova.path) {
            do { try FileManager.default.moveItem(at: vecchia, to: nuova); Diario.info("copie di sicurezza: cartella rinominata in Backups") }
            catch { Diario.errore("copie di sicurezza: cartella non rinominata: \(error.localizedDescription)") }
        }
        return nuova
    }()
    public static let giorniCopie = 5.0

    /// Elimina le copie di sicurezza delle scritture più vecchie di `giorni` (D61). Restituisce quante cartelle ha tolto.
    @discardableResult
    public static func pulisciCopie(in radice: URL = cartellaCopie, giorni: Double = giorniCopie, ora: Date = Date()) -> Int {
        let fm = FileManager.default
        guard let cartelle = try? fm.contentsOfDirectory(at: radice, includingPropertiesForKeys: [.creationDateKey]) else { return 0 }
        var tolte = 0
        for c in cartelle {
            guard let d = try? c.resourceValues(forKeys: [.creationDateKey]).creationDate,
                  ora.timeIntervalSince(d) > giorni * 86_400 else { continue }
            do { try fm.removeItem(at: c); tolte += 1 } catch { Diario.errore("copie di sicurezza: \(c.lastPathComponent) non eliminata: \(error.localizedDescription)") }
        }
        if tolte > 0 { Diario.info("copie di sicurezza: eliminate \(tolte) scritture più vecchie di \(Int(giorni)) giorni") }
        return tolte
    }

    static func copiaPrima(_ u: URL, in cartella: URL) throws {
        // il percorso intero: due foto possono avere lo stesso nome in cartelle diverse
        let dest = cartella.appendingPathComponent(u.path)
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.copyItem(at: u, to: dest) }
    }

    static func aggiornaSpotlight(_ u: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/mdimport")
        p.arguments = [u.path]
        try? p.run()
    }

    static func errore(_ s: String) -> NSError { NSError(domain: "FotoTag.Scrittura", code: 1, userInfo: [NSLocalizedDescriptionKey: s]) }
}
