import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import os
import UniformTypeIdentifiers

public enum Immagini {
    /// Tutto quello che l'app sa leggere con ImageIO, RAW compresi.
    public static let estensioni: Set<String> = Set(["jpg", "jpeg", "tif", "tiff", "heic"]).union(Scrittura.estensioniRAW)

    /// Miniatura con orientamento EXIF applicato.
    public static func miniatura(_ url: URL, lato: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        // RAW: l'anteprima incorporata basta e non si decodifica tutto il file; negli altri formati la miniatura
        // incorporata può essere minuscola e si rifà dall'immagine
        let daImmagine = Scrittura.eRAW(url) ? kCGImageSourceCreateThumbnailFromImageIfAbsent : kCGImageSourceCreateThumbnailFromImageAlways
        return CGImageSourceCreateThumbnailAtIndex(
            src, 0,
            [
                daImmagine: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: lato,
            ] as CFDictionary)
    }

    /// Copia ridotta a 1024 px in JPEG 90% (come b64() nel prototipo), in una cartella temporanea.
    /// L'originale viene solo letto.
    public static func copiaPerModello(_ url: URL, lato: Int = 1024) throws -> URL {
        guard let img = miniatura(url, lato: lato) else {
            throw NSError(domain: "FotoTag", code: 1, userInfo: [NSLocalizedDescriptionKey: String(localized: "immagine illeggibile: \(url.path)")])
        }
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("fototag-\(UUID().uuidString).jpg")
        guard let out = CGImageDestinationCreateWithURL(dest as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw NSError(domain: "FotoTag", code: 2, userInfo: [NSLocalizedDescriptionKey: String(localized: "impossibile scrivere \(dest.path)")])
        }
        CGImageDestinationAddImage(out, img, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        CGImageDestinationFinalize(out)
        return dest
    }

    /// Vero se il file è solo un segnaposto di un disco in cloud (BeeStation, iCloud…): il contenuto non è sul Mac.
    /// Leggerlo blocca finché non è scaricato.
    public static func daScaricare(_ url: URL) -> Bool {
        if richieste.withLock({ $0.provaSoloInCloud.contains(url.path) }) { return true }
        var st = stat()
        guard stat(url.path, &st) == 0 else { return false }
        return st.st_flags & UInt32(SF_DATALESS) != 0
    }

    /// Chiamata di sistema che chiede il file al disco in cloud (sostituibile nelle prove).
    nonisolated(unsafe) public static var avviaScaricamento: (URL) throws -> Void = {
        try FileManager.default.startDownloadingUbiquitousItem(at: $0)
    }

    struct Richieste {
        var inCorso: [String: Date] = [:]   // percorso → quando è stata accodata
        var segnalato = false               // riga «non risponde» già scritta per questo blocco
        var provaSoloInCloud: Set<String> = []  // nelle prove: file trattati come solo in cloud
    }
    static let richieste = OSAllocatedUnfairLock(initialState: Richieste())
    /// startDownloadingUbiquitousItem fa una chiamata sincrona al FileProvider che può non tornare mai
    /// (BeeStation): gira qui, mai sul pool di Swift, e nessuno la aspetta.
    static let codaCloud = DispatchQueue(label: "fototag.cloud", qos: .utility)
    /// A parte: un download fermo non deve impedire di liberare spazio.
    static let codaLibera = DispatchQueue(label: "fototag.cloud.libera", qos: .utility)
    static let massimoInCoda = 8

    /// Chiede di scaricare il file e aspetta al massimo `attesa` secondi. Vero se ora è sul Mac.
    public static func scarica(_ url: URL, attesa: TimeInterval) async -> Bool {
        guard daScaricare(url) else { return true }
        chiedi(url)
        let fine = Date().addingTimeInterval(attesa)
        while Date() < fine {
            do { try await Task.sleep(nanoseconds: 500_000_000) } catch { return false }  // annullato: si smette di aspettare
            if !daScaricare(url) { return true }
            segnalaSeFermo()
        }
        return false
    }

    /// Toglie dal Mac la copia scaricata di un file del disco in cloud (resta sul disco in cloud). Come il download,
    /// gira sulla coda dedicata e nessuno la aspetta.
    public static func libera(_ url: URL) {
        codaLibera.async {
            do { try FileManager.default.evictUbiquitousItem(at: url) } catch {
                Diario.errore("non ho potuto togliere dal Mac \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    /// Chiamata di sistema che toglie dal Mac la copia scaricata (sostituibile nelle prove).
    nonisolated(unsafe) static var togliDalMac: (URL) throws -> Void = { try FileManager.default.evictUbiquitousItem(at: $0) }
    static let chiaveDaLiberare = "daLiberareQuandoCaricate"

    /// Foto riportate sul Mac per scriverci (D62): si tolgono di nuovo appena il disco in cloud le ha caricate.
    /// L'elenco resta fra un avvio e l'altro; ci pensa `liberaCaricate`, chiamata di tanto in tanto.
    public static func liberaQuandoCaricate(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        codaLibera.async {
            let d = UserDefaults.standard
            d.set(Array(Set((d.stringArray(forKey: chiaveDaLiberare) ?? []) + urls.map(\.path))).sorted(), forKey: chiaveDaLiberare)
        }
    }

    /// Un giro sulle foto in attesa: quelle caricate si tolgono dal Mac, le altre aspettano il giro dopo.
    /// Sulla coda dedicata, come `libera`: un disco in cloud che non risponde non ferma nessuno.
    public static func liberaCaricate() {
        codaLibera.async {
            let d = UserDefaults.standard
            guard let attesa = d.stringArray(forKey: chiaveDaLiberare), !attesa.isEmpty else { return }
            var restano: [String] = []
            for p in attesa {
                let u = URL(fileURLWithPath: p)
                // sparita, o già tolta dal Mac (dal sistema o a mano): niente da fare
                guard FileManager.default.fileExists(atPath: p), !daScaricare(u) else { continue }
                if (try? u.resourceValues(forKeys: [.ubiquitousItemIsUploadedKey]))?.ubiquitousItemIsUploaded == false {
                    restano.append(p); continue
                }
                // finché il disco in cloud non ha caricato la modifica, toglierla fallisce: si riprova dopo
                do { try togliDalMac(u) } catch { restano.append(p) }
            }
            d.set(restano, forKey: chiaveDaLiberare)
            if restano.count < attesa.count {
                Diario.info("disco in cloud: \(attesa.count - restano.count) foto scritte tolte dal Mac, \(restano.count) in attesa del caricamento")
            }
        }
    }

    /// Accoda la richiesta senza aspettarla: niente doppioni, al massimo `massimoInCoda` (oltre si sonda e basta).
    static func chiedi(_ url: URL) {
        let p = url.path
        let accoda = richieste.withLock { r -> Bool in
            guard r.inCorso[p] == nil, r.inCorso.count < massimoInCoda else { return false }
            r.inCorso[p] = Date()
            return true
        }
        guard accoda else { return }
        codaCloud.async {
            try? avviaScaricamento(url)
            richieste.withLock { r in
                r.inCorso[p] = nil
                if r.inCorso.isEmpty { r.segnalato = false }
            }
        }
    }

    /// Una sola riga nel registro quando il disco in cloud non risponde da più di 10 s.
    static func segnalaSeFermo() {
        let ferma = richieste.withLock { r -> String? in
            guard !r.segnalato, let primo = r.inCorso.min(by: { $0.value < $1.value }),
                  Date().timeIntervalSince(primo.value) > 10 else { return nil }
            r.segnalato = true
            return primo.key
        }
        if let ferma { Diario.info("avviso: il disco in cloud non risponde (\(ferma))") }
    }

    /// Impronta del file per riconoscerlo dopo uno spostamento o un cambio di nome: dimensione e sha256
    /// dei primi e degli ultimi 64 KB. Nil se il file è solo in cloud (non lo si scarica per questo) o illeggibile.
    public static func impronta(_ url: URL) -> String? {
        guard !daScaricare(url), let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        let blocco: UInt64 = 65_536
        guard let n = try? h.seekToEnd(), n > 0, (try? h.seek(toOffset: 0)) != nil,
              let inizio = try? h.read(upToCount: Int(blocco)),
              (try? h.seek(toOffset: n > blocco ? n - blocco : 0)) != nil,
              let fine = try? h.read(upToCount: Int(blocco)) else { return nil }
        let hex = { (d: Data) in SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined() }
        return "\(n)-\(hex(inizio))-\(hex(fine))"
    }

    /// JPG della cartella e, se richiesto, delle sottocartelle (senza file nascosti né pacchetti), in ordine di percorso.
    /// Le sottocartelle con il nome in `saltate` (minuscolo) non si aprono.
    public static func fotoNellaCartella(_ cartella: URL, sottocartelle: Bool = true, saltate: [String] = []) -> [URL] {
        let fm = FileManager.default
        var elementi: [URL] = []
        if sottocartelle {
            let e = fm.enumerator(at: cartella, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                                  options: [.skipsHiddenFiles, .skipsPackageDescendants])
            while let u = e?.nextObject() as? URL {
                if saltate.contains(u.lastPathComponent.lowercased()),
                   (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    e?.skipDescendants()
                } else {
                    elementi.append(u)
                }
            }
        } else {
            elementi = (try? fm.contentsOfDirectory(at: cartella, includingPropertiesForKeys: [.isRegularFileKey],
                                                    options: [.skipsHiddenFiles])) ?? []
        }
        return elementi.filter { estensioni.contains($0.pathExtension.lowercased()) }.sorted(by: primaNelPercorso)
    }

    /// Ordine naturale per cartella e poi per nome («Rullino 2» prima di «Rullino 10», le foto di una cartella insieme).
    public static func primaNelPercorso(_ a: URL, _ b: URL) -> Bool {
        let da = a.deletingLastPathComponent().path, db = b.deletingLastPathComponent().path
        if da != db { return da.localizedStandardCompare(db) == .orderedAscending }
        return a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
    }
}
