import CoreML
import Foundation
import ImageIO
import Tokenizers
import Vision

/// SigLIP 2 in Core ML (convertito da strumenti/converti_siglip.py dallo stesso checkpoint del prototipo):
/// embedding delle foto e delle frasi di ricerca.
public final class SigLIP: @unchecked Sendable {
    struct Config: Decodable {
        let lato: Int
        let lunghezza_testo: Int
        let logit_scale: Float
        let logit_bias: Float
    }

    let immagine: MLModel
    let testo: MLModel
    let tokenizer: Tokenizer
    let config: Config
    public var scala: Float { config.logit_scale }
    public var bias: Float { config.logit_bias }

    public static func cartellaPredefinita() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FotoTag/Modelli/SigLIP2", isDirectory: true)
    }

    public static var disponibile: Bool {
        FileManager.default.fileExists(atPath: cartellaPredefinita().appendingPathComponent("siglip.json").path)
    }

    public init(cartella: URL = SigLIP.cartellaPredefinita()) async throws {
        config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: cartella.appendingPathComponent("siglip.json")))
        let c = MLModelConfiguration()
        c.computeUnits = .all
        immagine = try MLModel(contentsOf: try SigLIP.compilato(cartella, "ImageEncoder"), configuration: c)
        testo = try MLModel(contentsOf: try SigLIP.compilato(cartella, "TextEncoder"), configuration: c)
        tokenizer = try await AutoTokenizer.from(modelFolder: cartella.appendingPathComponent("tokenizer"), strict: false)
    }

    /// Compila il .mlpackage la prima volta e tiene il risultato accanto (.mlmodelc).
    static func compilato(_ cartella: URL, _ nome: String) throws -> URL {
        let dest = cartella.appendingPathComponent("\(nome).mlmodelc")
        let sorgente = cartella.appendingPathComponent("\(nome).mlpackage")
        let fm = FileManager.default
        let dataSorgente = (try? fm.attributesOfItem(atPath: sorgente.path)[.modificationDate] as? Date) ?? .distantPast
        let dataDest = (try? fm.attributesOfItem(atPath: dest.path)[.modificationDate] as? Date) ?? .distantPast
        if fm.fileExists(atPath: dest.path) && dataDest >= dataSorgente { return dest }
        let tmp = try MLModel.compileModel(at: sorgente)
        try? fm.removeItem(at: dest)
        try fm.moveItem(at: tmp, to: dest)
        return dest
    }

    static func vettore(_ a: MLMultiArray) -> [Float] {
        let n = a.count
        var out = [Float](repeating: 0, count: n)
        if a.dataType == .float16 {
            let p = a.dataPointer.bindMemory(to: Float16.self, capacity: n)
            for i in 0..<n { out[i] = Float(p[i]) }
        } else if a.dataType == .float32 {
            let p = a.dataPointer.bindMemory(to: Float.self, capacity: n)
            for i in 0..<n { out[i] = p[i] }
        } else {
            for i in 0..<n { out[i] = a[i].floatValue }
        }
        // normalizzato di nuovo per sicurezza (float16)
        let norma = sqrt(out.reduce(0) { $0 + $1 * $1 })
        return norma > 0 ? out.map { $0 / norma } : out
    }

    /// Embedding di una foto: ridotta a lato×lato (senza mantenere le proporzioni, come il processore di SigLIP).
    public func embedding(foto: URL) throws -> [Float] {
        guard let grande = Immagini.miniatura(foto, lato: 1024), let cg = SigLIP.quadrato(grande, lato: config.lato) else {
            throw Scrittura.errore(String(localized: "immagine illeggibile: \(foto.path)"))
        }
        guard let vincolo = immagine.modelDescription.inputDescriptionsByName["immagine"]?.imageConstraint else {
            throw Scrittura.errore(String(localized: "modello SigLIP senza ingresso immagine"))
        }
        let valore = try MLFeatureValue(cgImage: cg, constraint: vincolo,
                                        options: [.cropAndScale: VNImageCropAndScaleOption.scaleFill.rawValue])
        let out = try immagine.prediction(from: MLDictionaryFeatureProvider(dictionary: ["immagine": valore]))
        guard let e = out.featureValue(for: "embedding")?.multiArrayValue else { throw Scrittura.errore(String(localized: "SigLIP: nessun embedding")) }
        return SigLIP.vettore(e)
    }

    /// Riduce a lato×lato senza mantenere le proporzioni, con interpolazione di qualità
    /// (più vicina al ridimensionamento PIL del prototipo di quella di Vision).
    static func quadrato(_ img: CGImage, lato: Int) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: lato, height: lato, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: lato, height: lato))
        return ctx.makeImage()
    }

    /// Token della frase come nel prototipo: minuscolo, fine frase, completata con zeri fino a 64.
    public func token(_ frase: String) -> [Int] {
        var ids = tokenizer.encode(text: frase.lowercased())
        if ids.count > config.lunghezza_testo { ids = Array(ids.prefix(config.lunghezza_testo)) }
        return ids + [Int](repeating: 0, count: config.lunghezza_testo - ids.count)
    }

    public func embedding(frase: String) throws -> [Float] {
        let ids = token(frase)
        let a = try MLMultiArray(shape: [1, NSNumber(value: config.lunghezza_testo)], dataType: .int32)
        for (i, v) in ids.enumerated() { a[i] = NSNumber(value: v) }
        let out = try testo.prediction(from: MLDictionaryFeatureProvider(dictionary: ["input_ids": MLFeatureValue(multiArray: a)]))
        guard let e = out.featureValue(for: "embedding")?.multiArrayValue else { throw Scrittura.errore(String(localized: "SigLIP: nessun embedding")) }
        return SigLIP.vettore(e)
    }
}

/// Ricerca come search() nel prototipo: probabilità SigLIP + parole trovate in tag e didascalia.
public enum Ricerca {
    /// Da quale file calcolare l'embedding: la foto se è sul Mac, altrimenti l'anteprima salvata.
    /// L'indice di ricerca non scarica mai dal disco in cloud; nil = per ora si salta.
    public static func fileDaIndicizzare(_ foto: URL, anteprima: URL?) -> URL? {
        // solo in cloud o su un disco staccato: l'anteprima salvata, se c'è
        Immagini.daScaricare(foto) || !FileManager.default.fileExists(atPath: foto.path) ? anteprima : foto
    }

    /// Risultati di una cartella (quella che contiene le foto), per la griglia dei risultati.
    public struct Gruppo: Sendable, Equatable {
        public let cartella: String
        public var ids: [Int64]
        public let migliore: Float
        public init(cartella: String, ids: [Int64], migliore: Float = 0) { (self.cartella, self.ids, self.migliore) = (cartella, ids, migliore) }
        public var nome: String { (cartella as NSString).lastPathComponent }
        /// le due cartelle sopra, «2025 > dicembre»
        public var madre: String {
            let c = ((cartella as NSString).deletingLastPathComponent as NSString).pathComponents.filter { $0 != "/" }
            return c.suffix(2).joined(separator: " > ")
        }
    }

    /// Raggruppa per cartella; i gruppi in ordine di pertinenza del risultato migliore, dentro ogni gruppo
    /// i risultati per pertinenza.
    public static func raggruppa(_ risultati: [Risultato]) -> [Gruppo] {
        let perCartella = Dictionary(grouping: risultati) { ($0.percorso as NSString).deletingLastPathComponent }
        return perCartella.map { c, r in
            let ordinati = r.sorted { $0.punteggio > $1.punteggio }
            return Gruppo(cartella: c, ids: ordinati.map(\.id), migliore: ordinati[0].punteggio)
        }
        .sorted { ($0.migliore, $1.cartella) > ($1.migliore, $0.cartella) }
    }

    public struct Risultato: Identifiable, Sendable {
        public let id: Int64
        public let percorso: String
        public let didascalia: String
        public let punteggio: Float
        public let siglip: Float
        public let testo: Float

        public init(id: Int64, percorso: String, didascalia: String, punteggio: Float, siglip: Float, testo: Float) {
            (self.id, self.percorso, self.didascalia, self.punteggio, self.siglip, self.testo) = (id, percorso, didascalia, punteggio, siglip, testo)
        }
    }

    public struct Voce: Sendable {
        public let id: Int64
        public let percorso: String
        public let parole: [String]
        public let didascalia: String
        public let embedding: [Float]
        public init(id: Int64, percorso: String, parole: [String], didascalia: String, embedding: [Float]) {
            self.id = id; self.percorso = percorso; self.parole = parole; self.didascalia = didascalia; self.embedding = embedding
        }
    }

    /// Sotto l'1% di probabilità SigLIP e con meno di metà delle parole trovate, la foto non esce. Il prototipo usava il 2%:
    /// con «ritratto» ritratti evidenti restavano fra l'1,2 e l'1,3% (prova del 4/11, Aperta 10).
    public static let sogliaSigLIP: Float = 0.01
    public static let sogliaTesto: Float = 0.5

    static func parole(_ s: String) -> [String] {
        s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// Radice grezza come _word_hit: coppia/coppie, gondola/gondole.
    static func trovata(_ w: String, _ tokens: Set<String>) -> Bool {
        if w.count > 4 {
            let radice = String(w.dropLast())
            return tokens.contains { $0.hasPrefix(radice) }
        }
        return tokens.contains(w)
    }

    public static func cerca(_ frase: String, testo t: [Float], scala: Float, bias: Float, in voci: [Voce], limite: Int = 60) -> [Risultato] {
        let cercate = parole(frase).filter { $0.count > 2 }
        var out: [Risultato] = []
        for v in voci where v.embedding.count == t.count {
            var dot: Float = 0
            for i in 0..<t.count { dot += v.embedding[i] * t[i] }
            let p = 1 / (1 + exp(-(dot * scala + bias)))
            let tokens = Set(parole(v.parole.joined(separator: " ") + " " + v.didascalia))
            let colpi = cercate.isEmpty ? 0 : Float(cercate.filter { trovata($0, tokens) }.count) / Float(cercate.count)
            if p < sogliaSigLIP && colpi < sogliaTesto { continue }
            out.append(Risultato(id: v.id, percorso: v.percorso, didascalia: v.didascalia, punteggio: p + 0.5 * colpi, siglip: p, testo: colpi))
        }
        return Array(out.sorted { $0.punteggio > $1.punteggio }.prefix(limite))
    }
}
