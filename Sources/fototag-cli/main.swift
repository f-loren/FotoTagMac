import FotoTagCore
import Foundation

// Uso: fototag-cli [--modo libero|vincolato] [--modello <cartella>] <uscita.jsonl> <foto>...
// Tagga le foto con Qwen3-VL e scrive una riga JSON per foto (tempi, memoria, risposta, tag puliti).

var args = Array(CommandLine.arguments.dropFirst())

// prova della ricerca: fototag-cli siglip <frase> [foto...] — token, embedding e confronto
if args.first == "siglip", args.count >= 2 {
    let s = try await SigLIP()
    print("token:", Array(s.token(args[1]).prefix(12)))
    let t = try s.embedding(frase: args[1])
    for f in args.dropFirst(2) {
        let e = try s.embedding(foto: URL(fileURLWithPath: f))
        let dot = zip(e, t).map(*).reduce(0, +)
        print(String(format: "%.4f  p=%.4f  %@  %@", dot, 1 / (1 + exp(-(dot * s.scala + s.bias))), f.split(separator: "/").last.map(String.init) ?? f,
                     e.prefix(4).map { String(format: "%.4f", $0) }.joined(separator: " ")))
        if let dump = ProcessInfo.processInfo.environment["SIGLIP_DUMP"] {
            try e.map { String($0) }.joined(separator: "\n").write(toFile: dump + "/" + (f.split(separator: "/").last.map(String.init) ?? "x") + ".txt", atomically: true, encoding: .utf8)
        }
    }
    exit(0)
}

// regressione dei tag fissi: fototag-cli fissi <profilo.json> < righe JSON {"path","source","bw"} → tag piatti
// (origine e B/N presi dal prototipo, per confrontare solo la lettura del percorso e la composizione dei tag)
if args.first == "fissi", args.count >= 2 {
    let profilo = try Profilo.importa(URL(fileURLWithPath: args[1]))
    let pell = profilo.tabella
    while let riga = readLine() {
        guard let o = try? JSONSerialization.jsonObject(with: Data(riga.utf8)) as? [String: Any], let p = o["path"] as? String else { continue }
        let c = Contesto.leggi(p, profilo: profilo, pellicole: pell)
        var t = CalcoloFissi.calcola(percorso: p, profilo: profilo, pellicole: pell, exif: .init(), saturazione: (o["bw"] as? Int) == 1 ? 0 : 100)
        t.origine = o["source"] as? String
        if t.origine == "analogica" && !c.dataImportazione { t.anno = c.anno; t.mese = c.mese; t.giorno = c.giorno; t.digitalizzata = nil }
        if t.origine != "analogica" { t.anno = c.anno; t.mese = c.mese; t.giorno = c.giorno }
        let out: [String: Any] = ["path": p, "tags": t.parole()]
        print(String(decoding: try JSONSerialization.data(withJSONObject: out), as: UTF8.self))
    }
    exit(0)
}

// regressione del collegamento all'originale: fototag-cli originali <db del prototipo (copia)> <profilo.json> < righe {"path","taken"}
if args.first == "originali", args.count >= 3 {
    let profilo = try Profilo.importa(URL(fileURLWithPath: args[2]))
    var indice: [String: [Originali.Voce]] = [:]
    let db = try Archivio(url: URL(fileURLWithPath: args[1]), soloLettura: true)
    for v in try db.vociOriginaliPrototipo() { indice[v.radice, default: []].append(v) }
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"; f.locale = Locale(identifier: "en_US_POSIX")
    while let riga = readLine() {
        guard let o = try? JSONSerialization.jsonObject(with: Data(riga.utf8)) as? [String: Any], let p = o["path"] as? String else { continue }
        let scatto = (o["taken"] as? String).flatMap { f.date(from: $0) }
        let (raw, livello) = Originali.trova(p, scatto: scatto, candidati: indice[Originali.radice((p as NSString).lastPathComponent)] ?? [],
                                             profilo: profilo, pellicole: profilo.tabella)
        let out: [String: Any] = ["path": p, "raw": raw ?? NSNull(), "conf": livello == .nessuno ? NSNull() : livello.rawValue]
        print(String(decoding: try JSONSerialization.data(withJSONObject: out), as: UTF8.self))
    }
    exit(0)
}

// download: fototag-cli scarica <qwen4b|qwen8b> <cartella> [--completo] (senza: solo i file piccoli, per provare)
if args.first == "scarica", args.count >= 3, let m = Modelli.con(id: args[1]) {
    let d = try await Modelli.scarica(m, in: URL(fileURLWithPath: args[2]), filtro: { args.contains("--completo") || !$0.hasSuffix(".safetensors") }) { n, t in
        print(String(format: "\r%.1f/%.1f MB", Double(n) / 1e6, Double(t) / 1e6), terminator: "")
    }
    print("\nscaricato in", d.path, try FileManager.default.contentsOfDirectory(atPath: d.path).sorted())
    print("RAM", Modelli.ramGB, "consigliato", Modelli.consigliato.nome, "8B in", Modelli.posizione(Modelli.qwen8b)?.path ?? "-")
    exit(0)
}

// prova del modello di ricerca pubblicato: fototag-cli prova-siglip <cartella> <foto>
if args.first == "prova-siglip", args.count >= 3 {
    let dest = URL(fileURLWithPath: args[1])
    _ = try await Modelli.scarica(Modelli.siglip, esattamenteIn: dest) { n, t in
        print(String(format: "\r%.0f/%.0f MB", Double(n) / 1e6, Double(t) / 1e6), terminator: "")
    }
    print()
    let scaricato = try await SigLIP(cartella: dest), locale = try await SigLIP()
    let f = URL(fileURLWithPath: args[2])
    let a = try scaricato.embedding(foto: f), b = try locale.embedding(foto: f)
    let ta = try scaricato.embedding(frase: "persone in piazza"), tb = try locale.embedding(frase: "persone in piazza")
    print("coseno foto:", zip(a, b).map(*).reduce(0, +), "coseno frase:", zip(ta, tb).map(*).reduce(0, +))
    exit(0)
}

// prova della scrittura: fototag-cli scrivi <file> <parole,separate,da,virgola> <didascalia> [già,scritte]
if args.first == "scrivi", args.count >= 4 {
    let parole = args[2].split(separator: ",").map(String.init)
    let r = Scrittura.Richiesta(file: URL(fileURLWithPath: args[1]), parole: parole, didascalia: args[3],
                                gerarchia: parole.map { "Contenuto|prova|\($0)" },
                                paroleGiaScritte: args.count > 4 ? args[4].split(separator: ",").map(String.init) : [],
                                gerarchiaGiaScritta: args.count > 4 ? args[4].split(separator: ",").map { "Contenuto|prova|\($0)" } : [])
    do {
        let e = try Scrittura.scrivi(r)
        print("scritti:", e.fileScritti.map(\.lastPathComponent), "parole:", e.parole, "altrui:", e.paroleAltrui,
              "didascalia:", e.didascaliaScritta ?? "(lasciata)", "avvisi:", e.avvisi)
    } catch { print("ERRORE:", error.localizedDescription); exit(1) }
    exit(0)
}
func opzione(_ nome: String) -> String? {
    guard let i = args.firstIndex(of: nome), i + 1 < args.count else { return nil }
    let v = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return v
}
let modo = ModoJSON(rawValue: opzione("--modo") ?? "libero") ?? .libero
guard let cartellaModello = opzione("--modello").map({ URL(fileURLWithPath: $0) }) ?? Tagger.modelloInCache() else {
    print("modello non trovato: passa --modello <cartella>")
    exit(2)
}
guard args.count >= 2 else {
    print("uso: fototag-cli [--modo libero|vincolato] [--modello <cartella>] <uscita.jsonl> <foto>...")
    exit(2)
}
let uscita = URL(fileURLWithPath: args[0])
let foto = args.dropFirst().map { URL(fileURLWithPath: $0) }

let tagger = try await Tagger(cartellaModello: cartellaModello)
print(String(format: "modello caricato in %.1f s, modo %@", tagger.secondiCaricamento, modo.rawValue))

FileManager.default.createFile(atPath: uscita.path, contents: nil)
let file = try FileHandle(forWritingTo: uscita)
for (i, url) in foto.enumerated() {
    let a = try await tagger.analizza(url, modo: modo)
    let (parole, scartate) = Pulizia.paroleChiave(a.risposta, lingua: tagger.lingua)
    let riga: [String: Any] = [
        "path": url.path, "sec": (a.secondi * 100).rounded() / 100, "percorso": a.percorso,
        "raw": a.risposta.campi.merging(["didascalia": [a.risposta.didascalia]]) { x, _ in x },
        "didascalia": a.risposta.didascalia, "kws": parole, "rej": scartate, "testo": a.testo,
        "prompt_tokens": a.tokenPrompt, "gen_tokens": a.tokenGenerati,
        "peak_gb": (a.piccoMemoriaGB * 100).rounded() / 100,
    ]
    file.write(try JSONSerialization.data(withJSONObject: riga, options: [.sortedKeys]))
    file.write(Data("\n".utf8))
    print(String(format: "[%d/%d] %5.1fs %@ %@: %@ — %@", i + 1, foto.count, a.secondi, a.percorso,
                 url.lastPathComponent, parole.joined(separator: ", "), a.risposta.didascalia))
}
try file.close()
