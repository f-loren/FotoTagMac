import AppKit
import FotoTagCore
import SwiftUI

/// Impostazioni ▸ Profili: come leggere i nomi delle cartelle (D44, D54). Mockup: docs/mockup/profili.html, variante A.
struct ImpostazioniProfili: View {
    @EnvironmentObject var stato: Stato
    @State private var scelto = Profilo.generico.id
    @State private var bozza = Profilo.generico
    @State private var prova = ""
    @State private var provaTag: [String] = []
    @State private var dalFile = false
    @State private var pellicoleAperte = false
    @State private var nuovoNome: String?
    @State private var eliminando = false
    @State private var daImportare: Profilo?   // stesso id di un profilo che c'è già: si chiede

    var body: some View {
        Form {
            Section {
                HStack {
                    Picker("Profilo", selection: $scelto) { ForEach(stato.profili) { Text($0.nomeVisto).tag($0.id) } }
                    menu
                }
                Text(usatoDa).font(.caption).foregroundStyle(.secondary)
            }
            Section("Come leggere le cartelle") {
                Picker("Come leggere le cartelle", selection: Binding(get: { bozza.leggiStrutturaAnno },
                                                                       set: { bozza.leggiStrutturaAnno = $0; bozza.cartellaComeContesto = !$0 })) {
                    Text("Il nome della cartella della foto diventa un tag (la data viene dallo scatto)").tag(false)
                    Text("Struttura anno ▸ mese ▸ rullino: data, rullino e pellicola dai nomi delle cartelle").tag(true)
                }
                .pickerStyle(.radioGroup).labelsHidden()
                Toggle("Nelle cartelle di pellicola, una data AAAAMMGG è il giorno della scansione (si tiene solo il mese)",
                       isOn: $bozza.giornoCartellaPellicolaEDigitalizzazione)
            }
            Section("Nomi di cartella") {
                riga(String(localized: "Da non usare come tag"), $bozza.cartelleIgnorate)
                riga(String(localized: "Dicono che è una scansione di pellicola"), $bozza.cartellePellicola)
                riga(String(localized: "Sottocartelle da non elencare"), $bozza.sottocartelleSaltate,
                     aiuto: String(localized: "Copie della stessa foto, per esempio con la cornice: le foto lì dentro non compaiono."))
            }
            Section("Pellicole") {
                HStack {
                    Text(riassuntoPellicole).foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                    Button("Modifica…") { pellicoleAperte = true }
                }
            }
            Section("Prova") {
                HStack {
                    TextField("Percorso di una foto", text: $prova).textFieldStyle(.roundedBorder)
                    Button("Scegli foto…", action: scegliFoto)
                }
                Text(provaTag.isEmpty ? String(localized: "Nessun tag dal percorso.") : provaTag.joined(separator: " · "))
                    .foregroundStyle(provaTag.isEmpty ? .secondary : .primary).textSelection(.enabled)
                if !provaTag.isEmpty && !dalFile {
                    Text("Solo dal percorso: data di scatto, origine e bianco e nero si leggono dal file, che qui non è sul Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .task(id: [AnyHashable(prova), AnyHashable(bozza)]) { await calcolaProva() }
        }
        .formStyle(.grouped)
        .onAppear {
            scelto = stato.idValido(stato.profiloPredefinito)
            bozza = stato.profilo(id: scelto)
            if prova.isEmpty { prova = stato.foto.first?.percorso ?? "" }
        }
        .onChange(of: scelto) { _, id in chiudiModifica(); bozza = stato.profilo(id: id) }
        .onChange(of: bozza) { _, p in salva(p) }
        .sheet(isPresented: $pellicoleAperte) { FoglioPellicole(nomi: $bozza.pellicole) }
        .alert("Nome del profilo", isPresented: Binding(get: { nuovoNome != nil }, set: { if !$0 { nuovoNome = nil } })) {
            TextField("Nome", text: Binding(get: { nuovoNome ?? "" }, set: { nuovoNome = $0 }))
            Button("Annulla", role: .cancel) {}
            Button("Rinomina") {
                let n = (nuovoNome ?? "").trimmingCharacters(in: .whitespaces)
                if !n.isEmpty { bozza.nome = n }
            }
        }
        .confirmationDialog("Eliminare «\(bozza.nome)»?", isPresented: $eliminando) {
            Button("Elimina", role: .destructive) {
                stato.salvaProfili(stato.profili.filter { $0.id != scelto })
                scelto = Profilo.generico.id
            }
        } message: { Text("Le cartelle che lo usano tornano a Generico. Reimportandolo dal file tornano a questo profilo.") }
        .confirmationDialog("«\(daImportare?.nome ?? "")» c'è già", isPresented: Binding(get: { daImportare != nil }, set: { if !$0 { daImportare = nil } })) {
            Button("Sostituisci") { if let p = daImportare { metti(p) } }
            Button("Aggiungi come copia") {
                if var p = daImportare { p.id = UUID().uuidString; p.nome += String(localized: " (importato)"); metti(p) }
            }
        } message: { Text("Sostituendolo si perdono le modifiche fatte qui dopo l'esportazione. Le cartelle che lo usano restano a lui.") }
    }

    private var menu: some View {
        Menu {
            Button("Nuovo profilo da Generico") { chiudiModifica(); aggiungi(stato.profili[0], nome: String(localized: "Nuovo profilo")) }
            Button("Duplica «\(bozza.nomeVisto)»") { chiudiModifica(); aggiungi(bozza, nome: bozza.nomeVisto + String(localized: " (copia)")) }
            Button("Rinomina…") { chiudiModifica(); nuovoNome = bozza.nome }
            Divider()
            Button("Importa da un file…", action: importa)
            Button("Esporta in un file…", action: esporta)
            Divider()
            Button("Elimina…") { chiudiModifica(); eliminando = true }.disabled(scelto == Profilo.generico.id)
        } label: { Text("…") }
        .menuStyle(.borderlessButton).fixedSize()
    }

    private func riga(_ titolo: String, _ parole: Binding<[String]>, aiuto: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titolo)
            if let aiuto { Text(aiuto).font(.caption).foregroundStyle(.secondary) }
            CampoGettoni(parole: parole, titolo: titolo)
        }
    }

    private var usatoDa: String {
        let accessi = stato.radiciAccesso.filter { stato.idValido(stato.profiloAccesso($0)) == scelto }
        let originali = stato.radiciOriginali.filter { stato.idValido($0.profilo) == scelto }.map(\.percorso)
        let nomi = (accessi + originali).map { ($0 as NSString).lastPathComponent }
        return nomi.isEmpty ? String(localized: "Non usato da nessuna cartella. Si sceglie in Generali ▸ Cartelle.")
            : String(localized: "Usato da: \(nomi.joined(separator: ", ")). Si cambia in Generali ▸ Cartelle.")
    }

    private var riassuntoPellicole: String {
        let s = bozza.pellicole.keys.sorted()
        return s.isEmpty ? String(localized: "Nessuna sigla.") : String(localized: "\(s.count) sigle: ") + s.prefix(4).joined(separator: ", ") + (s.count > 4 ? "…" : "")
    }

    /// Come l'analisi: con EXIF e colore se il file è sul Mac; dal solo percorso se manca o è solo nel cloud (non si scarica).
    private func calcolaProva() async {
        let p = prova.trimmingCharacters(in: .whitespaces), profilo = bozza, lingua = stato.lingua
        guard !p.isEmpty else { provaTag = []; return }
        let u = URL(fileURLWithPath: p)
        dalFile = FileManager.default.fileExists(atPath: p) && !Immagini.daScaricare(u)
        if dalFile {
            provaTag = await Task.detached(priority: .userInitiated) {
                Stato.calcolaFissi(u, profilo: profilo, pellicole: profilo.tabella, saturazioneNota: nil, originale: nil).0.parole(lingua)
            }.value
        } else {
            provaTag = CalcoloFissi.calcola(percorso: p, profilo: profilo, pellicole: profilo.tabella, exif: .init(), saturazione: nil).parole(lingua)
        }
    }

    /// Chiude il campo a gettoni in modifica prima di cambiare profilo: le parole scritte vanno al profilo giusto.
    private func chiudiModifica() {
        NSApp.keyWindow?.makeFirstResponder(nil)
        salva(bozza)
    }

    private func salva(_ p: Profilo) {
        guard let i = stato.profili.firstIndex(where: { $0.id == p.id }) else { return }
        var tutti = stato.profili
        tutti[i] = p
        stato.salvaProfili(tutti)
    }

    private func aggiungi(_ base: Profilo, nome: String) {
        var p = base
        p.id = UUID().uuidString
        p.nome = nome
        stato.salvaProfili(stato.profili + [p])
        scelto = p.id
        nuovoNome = nome
    }

    private func importa() {
        chiudiModifica()
        let pannello = NSOpenPanel()
        pannello.allowedContentTypes = [.json]
        pannello.message = String(localized: "Scegli un profilo esportato da FotoTag")
        guard pannello.runModal() == .OK, let u = pannello.url else { return }
        do {
            let p = try Profilo.importa(u)
            if let c = stato.profili.first(where: { $0.id == p.id }), c != p { daImportare = p } else { metti(p) }
        } catch {
            stato.messaggio = String(localized: "«\(u.lastPathComponent)» non è un profilo di FotoTag: \(error.localizedDescription)")
        }
    }

    /// Stesso id: sostituisce, così le cartelle che lo usavano tornano a lui; altrimenti si aggiunge.
    private func metti(_ p: Profilo) {
        var tutti = stato.profili
        if let i = tutti.firstIndex(where: { $0.id == p.id }) { tutti[i] = p } else { tutti.append(p) }
        stato.salvaProfili(tutti)
        scelto = p.id
        bozza = p
    }

    private func esporta() {
        let pannello = NSSavePanel()
        pannello.allowedContentTypes = [.json]
        pannello.nameFieldStringValue = bozza.nome + ".json"
        guard pannello.runModal() == .OK, let u = pannello.url else { return }
        do { try bozza.esporta(u) } catch { stato.messaggio = String(localized: "Profilo non esportato: \(error.localizedDescription)") }
    }

    private func scegliFoto() {
        let pannello = NSOpenPanel()
        pannello.canChooseDirectories = false
        if !prova.isEmpty { pannello.directoryURL = URL(fileURLWithPath: prova).deletingLastPathComponent() }
        if pannello.runModal() == .OK, let u = pannello.url { prova = u.path }
    }
}

/// Elenco di parole come gettoni (NSTokenField): virgola o Invio per aggiungere, ⌫ per togliere.
struct CampoGettoni: NSViewRepresentable {
    @Binding var parole: [String]
    let titolo: String

    func makeNSView(context: Context) -> NSTokenField {
        let t = NSTokenField()
        t.delegate = context.coordinator
        t.objectValue = parole
        t.placeholderString = String(localized: "nessuna")
        t.setAccessibilityLabel(titolo)
        t.cell?.wraps = true
        t.cell?.isScrollable = false
        t.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return t
    }

    func updateNSView(_ t: NSTokenField, context: Context) {
        context.coordinator.padre = self
        if t.currentEditor() == nil, (t.objectValue as? [String]) != parole { t.objectValue = parole }
    }

    func sizeThatFits(_ proposta: ProposedViewSize, nsView t: NSTokenField, context: Context) -> CGSize? {
        let larghezza = proposta.width ?? 300
        let h = t.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: larghezza, height: .greatestFiniteMagnitude)).height ?? 22
        return CGSize(width: larghezza, height: max(22, h))
    }

    func makeCoordinator() -> Coordinatore { Coordinatore(self) }

    final class Coordinatore: NSObject, NSTokenFieldDelegate {
        var padre: CampoGettoni
        init(_ p: CampoGettoni) { padre = p }

        func controlTextDidEndEditing(_ n: Notification) {
            guard let t = n.object as? NSTokenField else { return }
            var visti = Set<String>()
            let nuove = ((t.objectValue as? [String]) ?? [])
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }   // i nomi delle cartelle si confrontano in minuscolo
                .filter { !$0.isEmpty && visti.insert($0).inserted }
            if nuove != padre.parole { padre.parole = nuove }
            t.objectValue = nuove
        }
    }
}

/// Sigle delle pellicole di un profilo: sigla nei nomi delle cartelle → nome completo nei tag.
struct FoglioPellicole: View {
    @Binding var nomi: [String: String]
    @Environment(\.dismiss) private var chiudi
    struct Riga: Identifiable { var sigla: String; var nome: String; var id: String { sigla } }
    @State private var righe: [Riga] = []
    @State private var nuovaSigla = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sigle delle pellicole nei nomi delle cartelle e nome completo da usare nei tag. Se il nome è vuoto resta la sigla.")
                .font(.caption).foregroundStyle(.secondary)
            List {
                ForEach($righe) { $r in
                    HStack {
                        Text(r.sigla).frame(width: 120, alignment: .leading).font(.body.monospaced())
                        TextField("nome completo", text: $r.nome).textFieldStyle(.roundedBorder)
                        Button { righe.removeAll { $0.id == r.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                            .accessibilityLabel("Togli \(r.sigla)")
                    }
                }
            }
            .frame(minHeight: 260)
            HStack {
                TextField("nuova sigla, es. portra 400", text: $nuovaSigla).textFieldStyle(.roundedBorder).onSubmit(aggiungi)
                Button("Aggiungi", action: aggiungi)
            }
            HStack {
                Spacer()
                Button("Annulla", role: .cancel) { chiudi() }.keyboardShortcut(.cancelAction)
                Button("Fine") {
                    nomi = Dictionary(righe.map { ($0.sigla, $0.nome) }, uniquingKeysWith: { a, _ in a })
                    chiudi()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 520)
        .onAppear { righe = nomi.map { Riga(sigla: $0.key, nome: $0.value) }.sorted { $0.sigla < $1.sigla } }
    }

    private func aggiungi() {
        let s = nuovaSigla.trimmingCharacters(in: .whitespaces).lowercased()
        if !s.isEmpty && !righe.contains(where: { $0.sigla == s }) { righe.append(Riga(sigla: s, nome: "")); righe.sort { $0.sigla < $1.sigla } }
        nuovaSigla = ""
    }
}
