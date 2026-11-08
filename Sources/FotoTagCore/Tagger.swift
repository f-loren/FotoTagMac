import Foundation
import MLX
import MLXGuidedGeneration
import MLXHuggingFace
import MLXLMCommon
import MLXVLM
import Tokenizers
import HuggingFace
import os

/// Come il modello deve rispondere in JSON.
public enum ModoJSON: String, Sendable {
    /// genera liberamente, poi legge/ripara il JSON; se fallisce riprova una volta, poi usa il vincolo
    case libero
    /// grammatica JSON imposta token per token (sicuro ma più lento in Swift)
    case vincolato
}

public struct Analisi: Sendable {
    public var risposta: Risposta
    public var testo: String
    public var secondi: Double
    public var tokenPrompt: Int
    public var tokenGenerati: Int
    /// "libero", "libero+riprova", "vincolato", eventualmente "+invito" se la risposta era povera
    public var percorso: String
    public var piccoMemoriaGB: Double
}

/// Errore di MLX (es. «GPU Timeout» di Metal): diventa un errore Swift invece di chiudere l'app.
public struct ErroreMLX: LocalizedError, Sendable {
    public let messaggio: String
    public var errorDescription: String? { String(localized: "errore della GPU (\(messaggio))") }
}

/// Qwen3-VL caricato una volta e usato per una foto alla volta. Non è thread-safe:
/// l'app lo usa da un solo Task di analisi.
public final class Tagger: @unchecked Sendable {
    public let lingua: Lingua
    let context: ModelContext
    let grammarTokenizer: GrammarTokenizer
    public let secondiCaricamento: Double

    /// Errore arrivato al gestore globale di MLX (fuori dal Task che ha chiamato `withError`).
    static let ultimoErrore = OSAllocatedUnfairLock<String?>(initialState: nil)

    /// Senza gestore MLX chiama fatalError e l'app si chiude: qui l'errore si registra e si segnala.
    /// shortcut: dopo un errore MLX il calcolo prosegue su dati non validi fino al controllo; un processo
    /// separato per l'analisi isolerebbe del tutto i crash della GPU.
    static let gestoreGlobale: Void = {
        setErrorHandler { messaggio, _ in
            let s = messaggio.map { String(cString: $0) } ?? "errore sconosciuto"
            Tagger.ultimoErrore.withLock { $0 = $0 ?? s }
            Diario.errore("MLX: \(s)")
            Diario.attendi()
        }
    }()

    /// Esegue `corpo` trasformando gli errori di MLX in `ErroreMLX`.
    static func protetto<R>(_ corpo: () async throws -> R) async throws -> R {
        _ = gestoreGlobale
        ultimoErrore.withLock { $0 = nil }
        let r: R
        do { r = try await withError { try await corpo() } } catch MLXError.caught(let m) {
            Diario.errore("MLX: \(m)")
            throw ErroreMLX(messaggio: m)
        }
        if let m = ultimoErrore.withLock({ $0 }) { throw ErroreMLX(messaggio: m) }
        return r
    }

    /// Esegue `corpo`; se fallisce con un errore della GPU aspetta `pausa`, chiama `ricarica` (il modello
    /// dopo un errore Metal può non essere più affidabile) e riprova una volta sola. Il secondo errore passa
    /// al chiamante, come ogni errore che non viene dalla GPU.
    public static func conUnaRiprova<R>(pausa: Duration = .seconds(3), ricarica: () async throws -> Void,
                                        _ corpo: () async throws -> R) async throws -> R {
        do {
            return try await corpo()
        } catch let e as ErroreMLX {
            Diario.info("errore della GPU (\(e.messaggio)): ricarico il modello e riprovo una volta")
            try await Task.sleep(for: pausa)
            try await ricarica()
            return try await corpo()
        }
    }

    /// Libera la memoria della GPU tenuta in cache da MLX (dopo aver lasciato andare il Tagger).
    public static func liberaMemoria() { Memory.clearCache() }

    public init(cartellaModello: URL, lingua: Lingua = .italiano) async throws {
        let t0 = Date()
        Memory.cacheLimit = Memoria.limiteCache(ramGB: Modelli.ramGB)
        context = try await Tagger.protetto {
            try await VLMModelFactory.shared.load(from: cartellaModello, using: #huggingFaceTokenizerLoader())
        }
        let vocab = TokenizerVocabExtractor.extractForGrammar(from: context.tokenizer)
        grammarTokenizer = try GrammarTokenizer(
            vocab: vocab.vocab, vocabType: vocab.vocabType, eosTokenId: Int32(context.tokenizer.eosTokenId ?? 0))
        self.lingua = lingua
        secondiCaricamento = Date().timeIntervalSince(t0)
    }

    /// Cartella del modello Qwen3-VL 8B 4bit già scaricato nella cache di Hugging Face, se c'è.
    public static func modelloInCache(_ repo: String = "mlx-community/Qwen3-VL-8B-Instruct-4bit") -> URL? {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub/models--" + repo.replacingOccurrences(of: "/", with: "--"))
            .appendingPathComponent("snapshots")
        let snap = (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? []
        return snap.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("config.json").path) }
    }

    func prepara(_ immagine: URL, prompt: String) async throws -> LMInput {
        try await context.processor.prepare(input: UserInput(chat: [.user(prompt, images: [.url(immagine)])]))
    }

    func generaLibero(_ immagine: URL, prompt: String, temperatura: Float, penalita: Float?) async throws -> (String, Int, Int) {
        let input = try await prepara(immagine, prompt: prompt + lingua.soloJSON)
        var p = GenerateParameters(maxTokens: 400, temperature: temperatura)
        p.repetitionPenalty = penalita
        let r = try generate(input: input, parameters: p, context: context) { (_: [Int]) in .more }
        return (r.output, input.text.tokens.size, r.tokenIds.count)
    }

    func generaVincolato(_ immagine: URL, prompt: String, minimi: [String: Int]) async throws -> (String, Int, Int) {
        // grammatica compatta con le chiavi in ordine; fastForward spento: acceso porta il modello a ripetersi
        let constraint = try GrammarConstraint(
            tokenizer: grammarTokenizer, grammar: grammaticaJSON(minimi: minimi),
            fastForward: false, hostTokenizer: context.tokenizer)
        let input = try await prepara(immagine, prompt: prompt)
        var testo = ""
        var n = 0
        do {
            n = try GuidedGenerationLoop.run(
                input: input, context: context, constraint: constraint,
                maxTokens: 400, vocabSize: grammarTokenizer.vocabSize
            ) { delta in
                testo += delta
                return true
            }
        } catch GuidedGenerationError.incompleteOutput {
            // limite di token raggiunto: si tiene quello che c'è, leggiRisposta proverà a salvarlo
        }
        return (testo, input.text.tokens.size, n)
    }

    /// `diversa`: nil per l'analisi normale; per «Rianalizza» le parole già scartate (anche vuota), e allora
    /// più varietà (temperatura 0,6, penalità 1,3) e un prompt che chiede dettagli diversi.
    func chiedi(_ immagine: URL, modo: ModoJSON, riprova: Bool, diversa: [String]? = nil) async throws -> (Risposta, String, Int, Int, String) {
        let prompt = lingua.prompt + (riprova || diversa != nil ? lingua.promptRiprova : "") + (diversa.map(lingua.richiestaDiversa) ?? "")
        let minimi = riprova ? ["oggetti": 2, "atmosfera": 2] : [:]
        if modo == .libero {
            // stessi tentativi del prototipo: prima deterministico, poi più varietà e penalità sulle ripetizioni
            let tentativi: [(Float, Float?)] = diversa == nil ? [(0, nil), (0.4, 1.3)] : [(0.6, 1.3), (0.6, 1.3)]
            for (i, (temp, pen)) in tentativi.enumerated() {
                let (testo, pt, gt) = try await generaLibero(immagine, prompt: prompt, temperatura: temp, penalita: pen)
                if let r = leggiRisposta(testo) { return (r, testo, pt, gt, i == 0 ? "libero" : "libero+riprova") }
            }
        }
        let (testo, pt, gt) = try await generaVincolato(immagine, prompt: prompt, minimi: minimi)
        return (leggiRisposta(testo) ?? .vuota, testo, pt, gt, modo == .libero ? "libero→vincolato" : "vincolato")
    }

    /// Analizza una foto (solo lettura dell'originale). Un errore della GPU arriva come `ErroreMLX`.
    /// `diversa`: per «Rianalizza», le parole già scartate da evitare (vedi `chiedi`).
    public func analizza(_ foto: URL, modo: ModoJSON = .libero, diversa: [String]? = nil) async throws -> Analisi {
        try await Tagger.protetto { try await analizzaSenzaProtezione(foto, modo: modo, diversa: diversa) }
    }

    func analizzaSenzaProtezione(_ foto: URL, modo: ModoJSON, diversa: [String]? = nil) async throws -> Analisi {
        let ridotta = try Immagini.copiaPerModello(foto)
        defer { try? FileManager.default.removeItem(at: ridotta) }
        Memory.peakMemory = 0  // azzera il picco
        let t = Date()
        var (r, testo, pt, gt, percorso) = try await chiedi(ridotta, modo: modo, riprova: false, diversa: diversa)
        if diversa != nil { percorso = "diversa:" + percorso }
        if r.numeroVoci < 3 {  // risposta povera: invito a descrivere di più, come nel prototipo
            let secondo = try await chiedi(ridotta, modo: modo, riprova: true, diversa: diversa)
            if secondo.0.numeroVoci >= r.numeroVoci {
                (r, testo, pt, gt) = (secondo.0, secondo.1, secondo.2, secondo.3)
                percorso = secondo.4 + "+invito"
            }
        }
        return Analisi(risposta: r, testo: testo, secondi: Date().timeIntervalSince(t), tokenPrompt: pt,
                       tokenGenerati: gt, percorso: percorso,
                       piccoMemoriaGB: Double(Memory.peakMemory) / 1_073_741_824)
    }
}
