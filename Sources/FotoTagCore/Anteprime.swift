import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Anteprime JPEG salvate durante l'analisi, per vedere le foto del disco in cloud (BeeStation) senza
/// scaricarle. Chiave: l'impronta del file, non il percorso (sopravvive a spostamenti e nuovi nomi).
/// File: <cartella>/<2 lettere>/<sha256 dell'impronta>_<lato>.jpg
public enum Anteprime {
    public static let lati = [640, 1024, 1600]
    public static let latoPredefinito = 1024

    public static func cartellaPredefinita() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FotoTag/Anteprime", isDirectory: true)
    }

    static func chiave(_ impronta: String) -> String {
        SHA256.hash(data: Data(impronta.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static func file(impronta: String, lato: Int, in cartella: URL) -> URL {
        let k = chiave(impronta)
        return cartella.appendingPathComponent(String(k.prefix(2)), isDirectory: true).appendingPathComponent("\(k)_\(lato).jpg")
    }

    /// L'anteprima più grande che c'è per questa impronta.
    public static func trova(impronta: String?, in cartella: URL) -> URL? {
        guard let impronta else { return nil }
        return lati.reversed().map { file(impronta: impronta, lato: $0, in: cartella) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Salva l'anteprima di una foto già sul Mac (lato lungo `lato`, JPEG 80%) e toglie quelle di altre misure.
    /// Da chiamare fuori dal thread principale.
    public static func salva(da foto: URL, impronta: String, lato: Int, in cartella: URL) throws {
        guard let img = Immagini.miniatura(foto, lato: lato) else {
            throw NSError(domain: "FotoTag", code: 5, userInfo: [NSLocalizedDescriptionKey: String(localized: "immagine illeggibile: \(foto.path)")])
        }
        let dest = file(impronta: impronta, lato: lato, in: cartella)
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tmp = dest.appendingPathExtension("tmp")
        guard let out = CGImageDestinationCreateWithURL(tmp as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw NSError(domain: "FotoTag", code: 6, userInfo: [NSLocalizedDescriptionKey: String(localized: "impossibile scrivere \(dest.path)")])
        }
        CGImageDestinationAddImage(out, img, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(out) else {
            throw NSError(domain: "FotoTag", code: 6, userInfo: [NSLocalizedDescriptionKey: String(localized: "impossibile scrivere \(dest.path)")])
        }
        _ = try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        for l in lati where l != lato { try? FileManager.default.removeItem(at: file(impronta: impronta, lato: l, in: cartella)) }
    }

    /// Peso e lato delle anteprime già salvate (dal nome «…_1024.jpg»).
    public struct Campione: Sendable, Equatable {
        public let byte: Int
        public let lato: Int
        public init(byte: Int, lato: Int) { (self.byte, self.lato) = (byte, lato) }
    }

    public static func campioni(in cartella: URL) -> [Campione] {
        let e = FileManager.default.enumerator(at: cartella, includingPropertiesForKeys: [.fileSizeKey])
        var out: [Campione] = []
        while let u = e?.nextObject() as? URL {
            guard u.pathExtension == "jpg", let l = Int(u.deletingPathExtension().lastPathComponent.split(separator: "_").last ?? ""),
                  let b = try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize else { continue }
            out.append(Campione(byte: b, lato: l))
        }
        return out
    }

    /// Stima dello spazio dal peso medio vero delle anteprime già salvate, riportato al lato scelto
    /// (il peso cresce col quadrato del lato). Senza anteprime: circa 120 KB a 1024 px.
    public static func stima(_ campioni: [Campione], lato: Int, foto: Int) -> (kbAFoto: Int, totaleMB: Int) {
        let perPixel: Double
        if campioni.isEmpty {
            perPixel = 120_000 / Double(1024 * 1024)
        } else {
            perPixel = campioni.map { Double($0.byte) / Double($0.lato * $0.lato) }.reduce(0, +) / Double(campioni.count)
        }
        let byte = perPixel * Double(lato * lato)
        return (Int((byte / 1000).rounded()), Int((byte * Double(foto) / 1_000_000).rounded()))
    }
}
