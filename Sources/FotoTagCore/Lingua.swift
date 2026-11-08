import Foundation

/// Testi che dipendono dalla lingua dei tag (D69): prompt, controllo ortografico, parole da scartare,
/// parole dei tag fissi e della gerarchia. Altre lingue si aggiungono qui.
public struct Lingua: Sendable {
    public let codice: String
    public let prompt: String
    public let promptRiprova: String
    /// Aggiunto al prompt quando il modello genera senza vincolo: chiede solo il JSON, con le chiavi in ordine.
    public let soloJSON: String
    /// Parole sulla tecnica o sul supporto: le gestiscono i tag fissi (STOP nel prototipo).
    public let paroleEscluse: Set<String>
    /// «Rianalizza»: chiede dettagli diversi; `evita` è seguito dalle parole già scartate.
    public let promptDiverso: String
    public let evita: String
    /// Tag fissi e gerarchia: parola italiana → parola in questa lingua (vuoto in italiano).
    public var traduzioni: [String: String] = [:]
    public var mesi: [String] = Contesto.mesi

    public func t(_ s: String) -> String { traduzioni[s] ?? s }
    /// «22 settembre 2025» (come lo salva il calcolo dei tag fissi) con il mese in questa lingua.
    func data(_ s: String) -> String {
        s.split(separator: " ").map { w in Contesto.mesi.firstIndex(of: String(w)).map { mesi[$0] } ?? String(w) }.joined(separator: " ")
    }

    func richiestaDiversa(_ scartate: [String]) -> String {
        promptDiverso + (scartate.isEmpty ? "" : evita + scartate.joined(separator: ", ") + ".")
    }

    /// Stesso testo di PROMPT / RETRY in fototag/fototag.py: i risultati devono restare confrontabili.
    public static let italiano = Lingua(
        codice: "it",
        prompt: """
            Analizza questa fotografia e compila il JSON richiesto.
            Regole:
            - solo parole italiane, minuscole, al singolare, da 1 a 3 parole per voce;
            - includi SOLO ciò che è chiaramente visibile: se hai un dubbio, ometti;
            - nessuna ripetizione; niente parole sulla tecnica o sul formato (fotografia, bianco e nero, analogica, grana, sfocatura);
            - un luogo famoso (città, monumento) solo se lo riconosci con certezza.
            Campi:
            - soggetti: chi o cosa è il soggetto principale (es. donna, coppia, gruppo, cane, albero);
            - luogo: ambiente o luogo (es. spiaggia, bosco, cucina, piazza, montagna, venezia);
            - oggetti: oggetti importanti visibili;
            - azioni: cosa sta succedendo (es. camminare, ballare, matrimonio, festa);
            - atmosfera: luce, momento del giorno, stagione, emozione;
            - didascalia: una frase breve e fattuale in italiano.
            """,
        promptRiprova: """

            Questa immagine può essere astratta o poco chiara: descrivi comunque almeno 5 elementi \
            (forme, architettura, luce, materiali, ambiente) che vedi.
            """,
        soloJSON: """

            Rispondi solo con un oggetto JSON con le chiavi "soggetti", "luogo", "oggetti", "azioni", \
            "atmosfera" (liste di stringhe) e "didascalia" (stringa), in quest'ordine, su una sola riga, senza altro testo.
            """,
        paroleEscluse: [
            "fotografia", "foto", "immagine", "analogica", "analogico", "pellicola", "archivio", "bianco", "nero",
            "grigio", "bianco e nero", "colore", "colori", "sfondo", "fondo", "dettaglio", "composizione", "tema",
            "stato", "essere", "stare", "sfocatura", "grana", "fondo sfocato", "vintage", "scansione", "nessuno", "nessuna",
        ],
        promptDiverso: """

            È una seconda analisi: guarda dettagli diversi da quelli più evidenti (sfondo, oggetti piccoli, gesti, \
            materiali, luce) e proponi parole diverse dalle solite.
            """,
        evita: "\nEvita questi tag già scartati: ")

    /// Stesse regole del prompt italiano, in inglese.
    public static let inglese = Lingua(
        codice: "en",
        prompt: """
            Analyze this photograph and fill in the requested JSON.
            Rules:
            - English words only, lowercase, singular, 1 to 3 words per entry;
            - include ONLY what is clearly visible: if in doubt, leave it out;
            - no repetitions; no words about technique or format (photograph, black and white, analog, grain, blur);
            - a famous place (city, monument) only if you recognize it with certainty.
            Fields:
            - soggetti: who or what is the main subject (e.g. woman, couple, group, dog, tree);
            - luogo: setting or place (e.g. beach, forest, kitchen, square, mountain, venice);
            - oggetti: important visible objects;
            - azioni: what is happening (e.g. walking, dancing, wedding, party);
            - atmosfera: light, time of day, season, emotion;
            - didascalia: a short, factual sentence in English.
            """,
        promptRiprova: """

            This image may be abstract or unclear: still describe at least 5 elements \
            (shapes, architecture, light, materials, setting) that you see.
            """,
        soloJSON: """

            Reply only with a JSON object with the keys "soggetti", "luogo", "oggetti", "azioni", \
            "atmosfera" (lists of strings) and "didascalia" (string), in this order, on a single line, with no other text.
            """,
        paroleEscluse: [
            "photograph", "photo", "picture", "image", "analog", "analogue", "film", "archive", "black", "white",
            "grey", "gray", "black and white", "color", "colour", "colors", "background", "detail", "composition", "theme",
            "blur", "grain", "blurred background", "vintage", "scan", "none", "nothing", "monochrome",
        ],
        promptDiverso: """

            This is a second analysis: look at details other than the most obvious ones (background, small objects, gestures, \
            materials, light) and suggest words different from the usual ones.
            """,
        evita: "\nAvoid these tags, already rejected: ",
        traduzioni: [
            "origine sconosciuta": "unknown origin", "analogica": "analog", "digitale": "digital",
            "bianco e nero": "black and white", "colore": "color", "digitalizzata il": "digitized on",
            "rullino": "roll", "pellicola": "film", "esposta a": "exposed at",
            "Origine": "Origin", "Tono": "Tone", "Data": "Date", "Rullino": "Roll", "Pellicola": "Film",
            "Esposta a": "Exposed at", "Contesto": "Context", "Contenuto": "Content", "manuale": "manual",
            "soggetti": "subjects", "luogo": "place", "oggetti": "objects", "azioni": "actions", "atmosfera": "mood",
        ],
        mesi: ["january", "february", "march", "april", "may", "june", "july", "august",
               "september", "october", "november", "december"])

    public static let disponibili: [Lingua] = [.italiano, .inglese]
    public static func con(codice: String) -> Lingua { disponibili.first { $0.codice == codice } ?? .italiano }
}

/// Campi della risposta: uguali allo SCHEMA del prototipo.
public let categorie = ["soggetti", "luogo", "oggetti", "azioni", "atmosfera"]

/// Grammatica JSON compatta con le chiavi nell'ordine dello SCHEMA del prototipo
/// (soggetti … atmosfera, didascalia per ultima) e separatori ", " / ": " come llguidance in Python:
/// lo schema JSON di xgrammar lascia al modello a capo e indentazione, che costano token.
public func grammaticaJSON(minimi: [String: Int] = [:]) -> String {
    var campi: [String] = []
    for c in categorie {
        let m = minimi[c] ?? 0
        campi.append("\"\\\"\(c)\\\": \" " + (m >= 2 ? "lista2" : "lista"))
    }
    campi.append("\"\\\"didascalia\\\": \" stringa")
    return #"""
        root ::= "{" \#(campi.joined(separator: " \", \" ")) "}"
        lista ::= "[]" | "[" stringa (", " stringa)* "]"
        lista2 ::= "[" stringa ", " stringa (", " stringa)* "]"
        stringa ::= "\"" carattere* "\""
        carattere ::= [^"\\\x00-\x1f] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F])
        """#
}
