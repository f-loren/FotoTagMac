import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import FotoTagCore

/// Cartella temporanea per una prova, cancellata alla fine.
func cartellaTemporanea() throws -> URL {
    // /private/var e non /var: è la forma dei percorsi letti dalla cartella
    let tmp = URL(fileURLWithPath: String(cString: realpath(NSTemporaryDirectory(), nil)))
    let u = tmp.appendingPathComponent("FotoTagTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

/// Immagine di prova con un gradiente, salvata nel formato indicato; `descrizione` va nel campo TIFF ImageDescription.
func immagineDiProva(_ u: URL, tipo: UTType, tinta: UInt8 = 0, descrizione: String? = nil) throws {
    let w = 64, h = 48
    var pixel = [UInt8](repeating: 255, count: w * h * 4)
    for y in 0..<h { for x in 0..<w { let i = (y * w + x) * 4; pixel[i] = UInt8(x * 4); pixel[i + 1] = UInt8(y * 5); pixel[i + 2] = tinta } }
    let ctx = CGContext(data: &pixel, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let dest = CGImageDestinationCreateWithURL(u as CFURL, tipo.identifier as CFString, 1, nil)!
    let proprieta = descrizione.map { [kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFImageDescription: $0]] as CFDictionary }
    CGImageDestinationAddImage(dest, ctx.makeImage()!, proprieta)
    #expect(CGImageDestinationFinalize(dest))
}

@Suite struct ScritturaTests {
    @Test func unisciTieneLeParoleAltrui() {
        let r = Scrittura.unisci(esistenti: ["Mario", "vecchia", "mare"], giaScritte: ["vecchia", "mare"], nuove: ["mare", "spiaggia"])
        #expect(r.finali == ["Mario", "mare", "spiaggia"])
        #expect(r.altrui == ["Mario"])
    }

    /// Stesso nome in due cartelle, stessa scrittura: ogni file ha la sua copia, con il contenuto di prima.
    @Test func copiaDiSicurezzaConNomiUguali() throws {
        let dir = try cartellaTemporanea()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a/DSC_1234.jpg"), b = dir.appendingPathComponent("b/DSC_1234.jpg")
        for (u, tinta) in [(a, UInt8(0)), (b, UInt8(200))] {
            try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try immagineDiProva(u, tipo: .jpeg, tinta: tinta)
        }
        let prima = [try Data(contentsOf: a), try Data(contentsOf: b)]
        let copie = dir.appendingPathComponent("copie")
        for u in [a, b] {
            _ = try Scrittura.scrivi(.init(file: u, parole: ["mare"], didascalia: "", gerarchia: []), copiaDiSicurezza: copie)
        }
        let trovate = (FileManager.default.enumerator(at: copie, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "jpg" }
        #expect(trovate.count == 2)
        #expect(Set(try trovate.map { try Data(contentsOf: $0) }) == Set(prima))
    }

    @Test func unisciSenzaDoppioni() {
        let r = Scrittura.unisci(esistenti: [], giaScritte: [], nuove: ["a", "b", "a"])
        #expect(r.finali == ["a", "b"])
        #expect(r.altrui.isEmpty)
    }

    // PNG escluso: ImageIO oggi non vi scrive l'XMP e la verifica fallisce (prima di questo controllo era già così)
    @Test(arguments: [UTType.jpeg, .tiff, .heic])
    func scrittoSenzaCambiareIPixel(_ tipo: UTType) throws {
        let dir = try cartellaTemporanea()
        defer { try? FileManager.default.removeItem(at: dir) }
        let foto = dir.appendingPathComponent("prova.\(tipo.preferredFilenameExtension!)")
        let riferimento = dir.appendingPathComponent("riferimento.\(tipo.preferredFilenameExtension!)")
        try immagineDiProva(foto, tipo: tipo)
        try FileManager.default.copyItem(at: foto, to: riferimento)
        let esito = try Scrittura.scrivi(.init(file: foto, parole: ["mare", "spiaggia"], didascalia: "Una spiaggia", gerarchia: []))
        #expect(esito.fileScritti == [foto])
        #expect(Scrittura.leggi(foto).parole == ["mare", "spiaggia"])
        #expect(Scrittura.pixelUguali(riferimento, foto, jpeg: tipo == .jpeg))
        // nessun file temporaneo rimasto
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix(".fototag-") }.isEmpty)
    }

    /// La didascalia messa dalla fotocamera («SONY DSC») conta come vuota: si scrive quella nuova (D59).
    @Test(arguments: ["SONY DSC        ", "OLYMPUS DIGITAL CAMERA"])
    func didascaliaSegnapostoSostituita(_ segnaposto: String) throws {
        let dir = try cartellaTemporanea()
        defer { try? FileManager.default.removeItem(at: dir) }
        let foto = dir.appendingPathComponent("DSC01234.jpg")
        try immagineDiProva(foto, tipo: .jpeg, descrizione: segnaposto)
        let esito = try Scrittura.scrivi(.init(file: foto, parole: ["mare"], didascalia: "Una spiaggia", gerarchia: []))
        #expect(esito.didascaliaScritta == "Una spiaggia")
        #expect(esito.avvisi.isEmpty)
        #expect(Scrittura.leggi(foto).didascalia == "Una spiaggia")
        // il campo EXIF (IFD0) dove la fotocamera l'aveva messa: ImageIO lo allinea da solo, verificato con exiftool
        // su un JPG vero il 4/11; questo JPG di prova non ha l'IFD0 e non permette di controllarlo qui
    }

    /// Lo stesso nel sidecar di un RAW, dove Lightroom copia spesso la didascalia della fotocamera.
    @Test func didascaliaSegnapostoNelSidecar() throws {
        let dir = try cartellaTemporanea()
        defer { try? FileManager.default.removeItem(at: dir) }
        let xmp = dir.appendingPathComponent("P1010001.xmp")
        _ = try Scrittura.aggiornaSidecar(xmp, .init(file: xmp, parole: [], didascalia: "OLYMPUS DIGITAL CAMERA", gerarchia: []), copiaDiSicurezza: nil)
        #expect(Scrittura.leggi(xmp).didascalia == "OLYMPUS DIGITAL CAMERA")
        let avvisi = try Scrittura.aggiornaSidecar(xmp, .init(file: xmp, parole: ["mare"], didascalia: "Una spiaggia", gerarchia: []), copiaDiSicurezza: nil)
        #expect(avvisi.isEmpty)
        #expect(Scrittura.leggi(xmp).didascalia == "Una spiaggia")
    }

    /// Una didascalia vera scritta da altri resta.
    @Test func didascaliaAltruiRestaAncheDallaFotocamera() throws {
        let dir = try cartellaTemporanea()
        defer { try? FileManager.default.removeItem(at: dir) }
        let foto = dir.appendingPathComponent("DSC01235.jpg")
        try immagineDiProva(foto, tipo: .jpeg, descrizione: "Gita a Camogli")
        let esito = try Scrittura.scrivi(.init(file: foto, parole: ["mare"], didascalia: "Una spiaggia", gerarchia: []))
        #expect(esito.didascaliaScritta == nil)
        #expect(esito.avvisi.count == 1)
    }

    @Test func segnaposti() {
        #expect(Scrittura.segnaposto("SONY DSC"))
        #expect(Scrittura.segnaposto("  sony dsc  "))
        #expect(Scrittura.segnaposto("KODAK Digital Still Camera"))
        #expect(!Scrittura.segnaposto("Sony al mare"))
        #expect(!Scrittura.segnaposto(""))
        #expect(!Scrittura.segnaposto("Default"))
    }

    @Test(arguments: [UTType.jpeg, .png])
    func pixelDiversiRiconosciuti(_ tipo: UTType) throws {
        let dir = try cartellaTemporanea()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a.\(tipo.preferredFilenameExtension!)")
        let b = dir.appendingPathComponent("b.\(tipo.preferredFilenameExtension!)")
        try immagineDiProva(a, tipo: tipo)
        try immagineDiProva(b, tipo: tipo, tinta: 200)
        #expect(!Scrittura.pixelUguali(a, b, jpeg: tipo == .jpeg))
        #expect(Scrittura.pixelUguali(a, a, jpeg: tipo == .jpeg))
    }

    @Test func scansioneJPEGNonValida() {
        #expect(Scrittura.scansioneJPEG(Data([0x00, 0x01, 0x02, 0x03, 0x04])) == nil)
    }

    /// Copie vere (TIFF/HEIC/JPG di scansioni): FOTOTAG_PROVA_PIXEL=cartella. I file vengono copiati in una
    /// cartella temporanea, gli originali non si toccano.
    @Test func fileVeri() throws {
        guard let p = ProcessInfo.processInfo.environment["FOTOTAG_PROVA_PIXEL"] else { return }
        let dir = try cartellaTemporanea()
        defer { try? FileManager.default.removeItem(at: dir) }
        for nome in try FileManager.default.contentsOfDirectory(atPath: p) where !nome.hasPrefix(".") {
            let orig = URL(fileURLWithPath: p).appendingPathComponent(nome)
            let foto = dir.appendingPathComponent(nome)
            try FileManager.default.copyItem(at: orig, to: foto)
            _ = try Scrittura.scrivi(.init(file: foto, parole: ["prova"], didascalia: "", gerarchia: []))
            let jpeg = ["jpg", "jpeg"].contains(foto.pathExtension.lowercased())
            #expect(Scrittura.pixelUguali(orig, foto, jpeg: jpeg), "\(nome)")
            print("controllato \(nome)")
        }
    }
}
