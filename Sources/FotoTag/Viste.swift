import FotoTagCore
import SwiftUI

struct Principale: View {
    @EnvironmentObject var stato: Stato
    @Environment(\.openWindow) private var apriFinestra
    @Environment(\.undoManager) private var annulla

    var body: some View {
        Group {
            switch stato.schermata {
            case .tagga: SchermataTagga()
            }
        }
        .alert("FotoTag", isPresented: Binding(get: { stato.messaggio != nil }, set: { if !$0 { stato.messaggio = nil } })) {
            Button("OK") { stato.messaggio = nil }
        } message: { Text(stato.messaggio ?? "") }
        .onAppear {
            stato.annulla = annulla
            if CommandLine.arguments.contains("--riconoscimenti") { apriFinestra(id: "riconoscimenti") }  // per le prove
        }
        .onChange(of: annulla) { _, a in stato.annulla = a }
    }
}

/// Pulsante per tornare alle foto da un'altra schermata.
struct TornaAlleFoto: ToolbarContent {
    @EnvironmentObject var stato: Stato
    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { stato.schermata = .tagga } label: { Label("Foto", systemImage: "photo.on.rectangle") }
                .help("Torna alle foto")
        }
    }
}

struct SchermataTagga: View {
    @EnvironmentObject var stato: Stato

    var body: some View {
        NavigationSplitView {
            ElencoCartelle()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        } detail: {
            Group {
                if stato.fotoGrande, stato.fotoScelta != nil { FotoGrande() } else { GrigliaFoto() }
            }
            .frame(minWidth: 320)
            // barra e titolo sopra le due viste: cambiandole a ogni vista la barra lasciava pulsanti doppi o fuori posto
            .navigationTitle(stato.raccolta?.nome ?? (stato.inRisultati ? String(localized: "Risultati") : stato.cartellaCorrente?.nome ?? "FotoTag"))
            .navigationSubtitle(sottotitolo)
            .toolbar { BarraFoto() }
            .inspector(isPresented: $stato.ispettore) { pannello.inspectorColumnWidth(min: 320, ideal: 360, max: 460) }
        }
        .modifier(CampoCerca(ricerca: stato.ricerca))
        .sheet(item: $stato.scrittura) { FoglioScrittura(lavoro: $0) }
        .sheet(isPresented: Binding(get: { stato.attesaModello != nil }, set: { if !$0 { stato.attesaModello = nil } })) { FoglioScaricaModello() }
        .alert(titoloFineCoda, isPresented: $stato.fineCoda) {
            if !stato.daScrivere.isEmpty { Button("Scrivi nei file…") { stato.chiediScrittura(stato.daScrivere) } }
            if let c = stato.prossimaDaRivedere { Button("Vai a «\(c.nome)»") { stato.apriCartella(c.percorso) } }
            Button("Più tardi", role: .cancel) {}
        } message: {
            let n = stato.daScrivere.count
            Text(n == 0 ? String(localized: "Le foto confermate sono già scritte nei file.")
                 : n == 1 ? String(localized: "1 foto confermata aspetta di essere scritta nei file.") : String(localized: "\(n) foto confermate aspettano di essere scritte nei file."))
        }
    }

    var sottotitolo: String {
        let v = stato.fotoVisibili
        if stato.fotoGrande, let i = v.firstIndex(where: { $0.id == stato.fotoScelta }) {
            let p = stato.foto.filter { $0.stato == .proposta }.count
            return String(localized: "\(i + 1) di \(v.count), \(p) da rivedere")
        }
        if stato.inRisultati {
            let n = stato.foto.count, g = stato.gruppiRisultati.count
            return String(localized: "\(n) foto in \(g) cartelle")
        }
        let n = stato.foto.count
        let p = stato.foto.filter { $0.stato == .proposta }.count
        let e = stato.foto.filter { $0.stato == .errore }.count
        let w = stato.daScrivere.count
        return String(localized: "\(n) foto, \(p) da rivedere") + (w > 0 ? String(localized: ", \(w) da scrivere") : "") + (e > 0 ? String(localized: ", \(e) con errore") : "")
    }

    var titoloFineCoda: String {
        stato.raccolta != nil ? String(localized: "Niente più da rivedere qui") : stato.inRisultati ? String(localized: "Nessun risultato da rivedere")
            : String(localized: "«\(stato.cartellaCorrente?.nome ?? String(localized: "Cartella"))» è tutta rivista")
    }

    /// Revisione a destra, come ispettore richiudibile.
    var pannello: some View {
            Group {
                if stato.selezione.count > 1 {
                    RevisioneMultipla()
                } else if let id = stato.fotoScelta, let f = stato.foto.first(where: { $0.id == id }) {
                    Revisione(foto: f).id(f.id)
                } else if stato.inRisultati {
                    ContentUnavailableView("Nessuna foto scelta", systemImage: "photo",
                                           description: Text("Scegli un risultato per rivederlo e confermarne i tag."))
                } else {
                    ContentUnavailableView("Nessuna foto", systemImage: "photo", description: Text("Scegli una foto nella griglia."))
                }
            }
    }
}

/// Barra laterale: un solo albero, una radice per accesso, selezione di sistema;
/// in fondo l'avanzamento.
struct ElencoCartelle: View {
    @EnvironmentObject var stato: Stato
    @Environment(\.accessibilityReduceMotion) private var riduci

    var body: some View {
        List(selection: Binding(get: { stato.raccolta.map { RigaDaFare.prefisso + $0.rawValue } ?? stato.cartellaCorrente?.percorso },
                                set: { scegli($0) })) {
            let code = Archivio.DaFare.allCases.filter { (stato.daFare[$0] ?? 0) > 0 || stato.raccolta == $0 }
            if !code.isEmpty {
                Section("Da fare") { ForEach(code, id: \.self) { RigaDaFare(coda: $0) } }
            }
            Section("Cartelle") {
                // lista piatta: i rami annidati lasciavano righe fuori posto mentre l'albero cresceva (D52)
                ForEach(righe) { RigaCartella(nodo: $0.nodo, livello: $0.livello, aperto: $0.aperto) }
            }
        }
        .listStyle(.sidebar)
        .onKeyPress(keys: [.rightArrow, .leftArrow]) { k in k.modifiers.isEmpty ? apriRamo(k.key == .rightArrow) : .ignored }
        .safeAreaInset(edge: .bottom) { RiquadroRicerca(ricerca: stato.ricerca) }
        .safeAreaInset(edge: .bottom) {
            // fuori dalla lista: come riga della lista si sovrapponeva ai nodi aperti dell'albero
            let indici = [stato.indiceInCorso, stato.indicizzazione].compactMap { $0 }
            let entra = Movimento.dal(.bottom, riduci: riduci)
            // entrano dal basso ed escono dalla stessa parte (D67); il testo dell'indice cambia di continuo e non si anima
            let presenti = [stato.notizia != nil, stato.volumeNuovo != nil, stato.inCorso || stato.faseModello != nil, !indici.isEmpty]
            Group {
            if presenti.contains(true) {
                VStack(alignment: .leading, spacing: 10) {
                    if let n = stato.notizia {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "info.circle").foregroundStyle(.secondary)
                            Text(n).font(.callout).lineLimit(3)
                            Spacer(minLength: 4)
                            Button { stato.notizia = nil } label: { Image(systemName: "xmark") }
                                .buttonStyle(.plain).foregroundStyle(.secondary)
                                .help("Chiudi").accessibilityLabel("Chiudi la notizia")
                        }
                        .accessibilityElement(children: .combine)
                        .transition(entra)
                    }
                    if let v = stato.volumeNuovo {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Nuovo disco: \(v.lastPathComponent)").font(.callout.weight(.semibold))
                                .lineLimit(1).truncationMode(.middle).help(v.lastPathComponent)
                            HStack {
                                Button("Aggiungi") { stato.aggiungiVolumeNuovo() }.buttonStyle(.borderedProminent)
                                Button("Ignora") { stato.ignoraVolumeNuovo() }.buttonStyle(.bordered)
                            }
                            .controlSize(.small)
                        }
                        .transition(entra)
                    }
                    if stato.inCorso || stato.faseModello != nil { RiquadroAvanzamento().transition(entra) }
                    ForEach(indici, id: \.self) { i in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(i).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)  // l'albero scorre qui sotto: senza fondo le righe si leggevano attraverso il testo
                .overlay(alignment: .top) { Divider() }
                .transition(entra)
            }
            }
            .animation(Movimento.standard, value: presenti)
        }
    }

    var righe: [RigaAlbero] {
        let corrente = stato.cartellaCorrente?.percorso
        return Albero.righe(stato.albero) { stato.ramoAperto($0, livello: $1, corrente: corrente) }
    }

    /// Ogni cartella si apre nella griglia con le foto sue e delle sottocartelle; il triangolino apre il ramo.
    func scegli(_ percorso: String?) {
        guard let percorso else { return }
        if percorso.hasPrefix(RigaDaFare.prefisso) {
            if let d = Archivio.DaFare(rawValue: String(percorso.dropFirst(RigaDaFare.prefisso.count))) { stato.apriDaFare(d) }
        } else if stato.inRisultati, percorso == stato.cartellaCorrente?.percorso {
            stato.ricerca.frase = ""
            stato.esciDaiRisultati()  // la stessa cartella di prima: la selezione non cambia, si torna indietro a mano
        } else {
            stato.apriCartella(percorso)
        }
    }

    /// Frecce destra e sinistra sulla riga scelta, come nel Finder.
    func apriRamo(_ apri: Bool) -> KeyPress.Result {
        guard let r = righe.first(where: { $0.nodo.percorso == stato.cartellaCorrente?.percorso }), !r.nodo.figli.isEmpty else { return .ignored }
        stato.ramiScelti[r.nodo.percorso] = apri
        return .handled
    }
}

/// Una coda di lavoro di tutto l'archivio, in cima alla barra laterale (D34.2).
struct RigaDaFare: View {
    static let prefisso = "dafare:"  // nella selezione della lista, accanto ai percorsi delle cartelle
    @EnvironmentObject var stato: Stato
    let coda: Archivio.DaFare

    var body: some View {
        let n = stato.daFare[coda] ?? 0
        HStack(spacing: 4) {
            Label(coda.nome, systemImage: coda.icona)
            Spacer(minLength: 4)
            Text(n, format: .number).font(.caption).monospacedDigit()
                .foregroundStyle(coda == .daRivedere && n > 0 ? Color.accentColor : .secondary)
                .fontWeight(coda == .daRivedere && n > 0 ? .semibold : .regular)
        }
        .help("\(coda.nome) in tutte le cartelle")
        .tag(Self.prefisso + coda.rawValue)
    }
}

extension Archivio.DaFare {
    var nome: String {
        switch self {
        case .daRivedere: return String(localized: "Da rivedere")
        case .daScrivere: return String(localized: "Da scrivere")
        case .errori: return String(localized: "Con errore")
        }
    }
    var icona: String {
        switch self {
        case .daRivedere: return "eye"
        case .daScrivere: return "square.and.arrow.down"
        case .errori: return "exclamationmark.triangle"
        }
    }
}

/// Una riga dell'albero: una radice (accesso) o una cartella.
struct RigaCartella: View {
    @EnvironmentObject var stato: Stato
    let nodo: NodoAlbero
    let livello: Int
    let aperto: Bool
    var radice: Bool { livello == 0 }

    var body: some View {
        let c = stato.cartellePerPercorso[nodo.percorso]
        HStack(spacing: 4) {
            triangolo
            Label(nodo.nome, systemImage: icona)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            if radice, !nodo.collegata {
                Text("non collegato").font(.caption)
            } else if let c, c.nFoto != 0 { Conteggio(cartella: c) }
        }
        .padding(.leading, CGFloat(livello) * 14)
        .opacity(nodo.collegata ? 1 : 0.5)
        .help(nodo.percorso)
        .contextMenu { menu(c) }
        .tag(nodo.percorso)
    }

    /// Spazio fisso anche senza sottocartelle: le icone dello stesso livello restano in colonna.
    @ViewBuilder
    var triangolo: some View {
        Group {
            if nodo.figli.isEmpty {
                Color.clear
            } else {
                Button { stato.ramiScelti[nodo.percorso] = !aperto } label: {
                    Image(systemName: aperto ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(aperto ? String(localized: "Chiudi \(nodo.nome)") : String(localized: "Apri \(nodo.nome)"))
                .accessibilityValue(aperto ? String(localized: "aperta") : String(localized: "chiusa"))
            }
        }
        .frame(width: 16, height: 20)
    }

    /// Ogni riga ha la sua icona, con o senza sottocartelle (solo simboli che esistono su macOS 14).
    var icona: String {
        if !radice { return "folder" }
        if nodo.percorso.contains("/Library/CloudStorage/") { return "icloud" }
        if nodo.percorso.hasPrefix("/Volumes/") { return "externaldrive" }
        return nodo.percorso == FileManager.default.homeDirectoryForCurrentUser.path ? "house" : "folder"
    }

    @ViewBuilder
    func menu(_ c: Cartella?) -> some View {
        Button("Mostra nel Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: nodo.percorso)]) }
        if let c {
            Button("Crea anteprime mancanti") { stato.creaAnteprimeMancanti(c) }
                .disabled(stato.indiceInCorso != nil)
            if !FileManager.default.fileExists(atPath: c.percorso) { Button("Riconnetti cartella…") { stato.riconnetti(c) } }
        }
        Button("Aggiorna") { stato.indicizza() }.disabled(stato.indicizzazione != nil)
        Button("Nascondi dall'elenco") { stato.nascondi(nodo.percorso) }
            .help("Non cancella nulla: si rimette da Impostazioni ▸ Generali ▸ Cartelle")
    }
}

/// Numero a destra di una cartella registrata: avanzamento dell'analisi, oppure le foto da rivedere.
/// shortcut: solo sulle cartelle registrate, non la somma sulle cartelle madri (anni, mesi); da aggiungere in P2.
struct Conteggio: View {
    @EnvironmentObject var stato: Stato
    let cartella: Cartella

    var body: some View {
        Group {
            if stato.inCorso && stato.cartellaInAnalisi == cartella.id {
                Text("\(stato.fatte)/\(stato.totale)").foregroundStyle(.secondary)
            } else if let n = stato.conteggi[cartella.id]?.daRivedere, n > 0 {
                Text("\(n)").foregroundStyle(Color.accentColor).fontWeight(.semibold)
            } else if let n = cartella.nFoto, n > 0 {
                Text("\(n)").foregroundStyle(.secondary)
            }
        }
        .font(.caption).monospacedDigit()
    }
}

/// In fondo alla barra laterale, solo durante l'analisi: si vede da qualunque cartella.
struct RiquadroAvanzamento: View {
    @EnvironmentObject var stato: Stato

    var body: some View {
        let c = stato.cartelle.first { $0.id == stato.cartellaInAnalisi }
        VStack(alignment: .leading, spacing: 6) {
            Button { if let c { stato.cartellaScelta = c.id } } label: {
                Text("Analisi di \(c?.nome ?? "foto")").font(.callout.weight(.semibold))
                    .lineLimit(1).truncationMode(.middle).help(c?.nome ?? "")
            }
            .buttonStyle(.plain)
            if let fase = stato.faseModello {
                if let s = stato.scaricamento, s.id == stato.modelloAnalisi.id {
                    ProgressView(value: Double(s.fatti), total: Double(max(s.totale, 1))).controlSize(.small)
                } else {
                    ProgressView().progressViewStyle(.linear).controlSize(.small)
                }
                HStack {
                    Text(fase).font(.callout).foregroundStyle(.secondary).monospacedDigit().lineLimit(2)
                    Spacer(minLength: 4)
                    if stato.scaricamento != nil {
                        Button("Ferma") { stato.ferma() }
                            .buttonStyle(.bordered).controlSize(.small).fixedSize()
                            .help("Ferma il download: i file già scaricati restano e la prossima volta si riparte da lì")
                    }
                }
            } else {
                ProgressView(value: Double(stato.fatte), total: Double(max(stato.totale, 1))).controlSize(.small)
                    .animation(Movimento.standard, value: stato.fatte)  // la barra scivola invece di saltare (D67)
                HStack {
                    Text(testo).font(.callout).foregroundStyle(.secondary).monospacedDigit().lineLimit(2)
                        .contentTransition(.numericText(value: Double(stato.fatte)))
                        .animation(Movimento.standard, value: stato.fatte)
                    Spacer(minLength: 4)
                    Button("Ferma") { stato.ferma() }
                        .buttonStyle(.bordered).controlSize(.small).fixedSize()
                        .help("Ferma dopo la foto in corso")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var testo: String {
        var t = String(localized: "\(stato.fatte) di \(stato.totale)")
        if let s = stato.secondiMedi, stato.totale > stato.fatte {
            let ora = Date().addingTimeInterval(Double(stato.totale - stato.fatte) * s).formatted(date: .omitted, time: .shortened)
            t += String(localized: ", fine verso le \(ora)")
        }
        return t
    }
}

struct GrigliaFoto: View {
    @EnvironmentObject var stato: Stato
    @Environment(\.accessibilityReduceMotion) private var riduci
    @FocusState private var attiva: Bool
    @AppStorage("latoMiniatura") private var lato = 132
    @State private var larghezza: CGFloat = 600
    @State private var altezza: CGFloat = 400
    @State private var cornici = RegistroCornici()                // caselle visibili, per la selezione a rettangolo
    @State private var rettangolo: CGRect?
    @State private var base: Set<FotoRecord.ID> = []             // selezione all'inizio del trascinamento (con ⌘)

    /// Colonne della griglia adattiva (padding 16 per lato, spaziatura 10): serve alle frecce su e giù.
    var colonne: Int { max(1, Int((larghezza - 32 + 10) / (CGFloat(lato) + 10))) }

    var body: some View {
        ScrollViewReader { scorri in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: CGFloat(lato)), spacing: 10)], alignment: .leading, spacing: 10) {
                    let gruppi = stato.gruppiFoto
                    ForEach(gruppi) { g in
                        Section {
                            ForEach(g.foto) { f in
                                Casella(foto: f, scelta: stato.selezione.contains(f.id), lato: lato, inAnalisi: stato.fotoInAnalisi == f.id)
                                    .id(f.id)
                                    .background(GeometryReader { g in
                                        let r = g.frame(in: .named("griglia"))
                                        Color.clear
                                            .onAppear { cornici.cornici[f.id] = r }
                                            .onChange(of: r) { _, n in cornici.cornici[f.id] = n }
                                            .onDisappear { cornici.cornici[f.id] = nil }
                                    })
                                    // ⌘ e ⇧ con gesti propri: non dipendono da NSEvent.modifierFlags al momento del tocco
                                    .highPriorityGesture(TapGesture().modifiers(.command).onEnded {
                                        stato.clic(f.id, comando: true, maiuscolo: false); attiva = true
                                    })
                                    .highPriorityGesture(TapGesture().modifiers(.shift).onEnded {
                                        stato.clic(f.id, comando: false, maiuscolo: true); attiva = true
                                    })
                                    .onTapGesture {
                                        let m = NSEvent.modifierFlags
                                        stato.clic(f.id, comando: m.contains(.command), maiuscolo: m.contains(.shift))
                                        attiva = true
                                    }
                                    // il primo clic ha già scelto la foto: il secondo apre la foto grande
                                    .simultaneousGesture(TapGesture(count: 2).onEnded { stato.fotoGrande = true })
                                    .contextMenu { MenuFoto(quali: stato.bersaglio(f)) }
                            }
                        } header: {
                            // con le sottocartelle si vede da dove viene ogni foto
                            if gruppi.count > 1 || stato.inRisultati {
                                HStack(spacing: 8) {
                                    Text(g.nome).font(.headline).lineLimit(1).truncationMode(.middle).layoutPriority(1)
                                    Text("\(g.foto.count)").foregroundStyle(.secondary).monospacedDigit()
                                    if let m = g.madre { Text(m).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head) }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                            }
                        }
                    }
                }
                .padding(16)
                // tutta l'area visibile, anche sotto e tra le miniature
                .frame(maxWidth: .infinity, minHeight: altezza, alignment: .topLeading)
                // il rettangolo parte dallo spazio vuoto (come nel Finder) ed è gestito da AppKit: i gesti SwiftUI
                // dentro la ScrollView non ricevevano il trascinamento dallo spazio vuoto
                .background(AreaRettangolo(
                    inizio: { comando in base = comando ? stato.selezione : []; attiva = true },
                    trascina: { r in
                        rettangolo = r
                        stato.selezionaRettangolo(Set(cornici.cornici.filter { $0.value.intersects(r) }.keys), base: base)
                    },
                    fine: { rettangolo = nil }))
                .coordinateSpace(name: "griglia")
                .overlay(alignment: .topLeading) {
                    if let r = rettangolo {
                        Rectangle().fill(Color.accentColor.opacity(0.15))
                            .overlay(Rectangle().strokeBorder(Color.accentColor, lineWidth: 1))
                            .frame(width: r.width, height: r.height)
                            .offset(x: r.minX, y: r.minY)
                            .allowsHitTesting(false)
                    }
                }
            }
            .background(GeometryReader { g in
                Color(nsColor: .underPageBackgroundColor)
                    .onAppear { larghezza = g.size.width; altezza = g.size.height }
                    .onChange(of: g.size) { _, s in larghezza = s.width; altezza = s.height }
            })
            // si scorre solo con la tastiera: ⌘-clic, ⇧-clic e rettangolo cambiano la foto scelta (anche verso una
            // più in alto) e prima la griglia la inseguiva, tornando su mentre si scorreva con la rotellina
            .onChange(of: stato.scorriA) { _, id in if let id { withAnimation { scorri.scrollTo(id) } } }
            // tornando dalla foto grande si riparte dalla foto vista lì
            .onAppear { if let id = stato.fotoScelta { scorri.scrollTo(id, anchor: .center) } }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($attiva)
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { k in
            let passo: Int
            switch k.key {
            case .leftArrow: passo = -1
            case .rightArrow: passo = 1
            case .upArrow: passo = -colonne
            default: passo = colonne
            }
            // shortcut: su/giù contano le colonne sull'elenco intero, non saltano le intestazioni dei gruppi
            stato.sposta(di: passo, estendi: k.modifiers.contains(.shift))
            return .handled
        }
        .onKeyPress(.return) { stato.rivistaEProssima(); return .handled }
        .onKeyPress(.escape) {
            guard stato.inRisultati else { return .ignored }
            stato.ricerca.frase = ""  // il campo vuoto riporta alla cartella
            stato.esciDaiRisultati()
            return .handled
        }
        .onKeyPress(.space) {
            if stato.fotoScelta != nil { stato.fotoGrande = true }
            return .handled
        }
        .onKeyPress(characters: ["t"]) { k in
            guard k.modifiers.isEmpty else { return .ignored }
            stato.fuocoTag = true
            return .handled
        }
        .overlay {
            if let d = stato.raccolta, stato.foto.isEmpty {
                ContentUnavailableView(d == .daRivedere ? String(localized: "Nessuna foto da rivedere") : d == .daScrivere ? String(localized: "Nessuna foto da scrivere")
                                       : String(localized: "Nessuna foto con errore"), systemImage: "checkmark.circle",
                                       description: Text("In tutte le cartelle non c'è altro da fare qui."))
            } else if stato.inRisultati && stato.raccolta == nil && !SigLIP.disponibile {
                ContentUnavailableView {
                    Label("Modello di ricerca da scaricare", systemImage: "arrow.down.circle")
                } description: {
                    Text("Per cercare nelle foto serve il modello SigLIP 2: si scarica una volta sola (0,75 GB) e occupa 1,5 GB sul disco.")
                } actions: {
                    if let s = stato.scaricamento, s.id == Modelli.siglip.id {
                        ProgressView(value: Double(s.fatti), total: Double(max(s.totale, 1))).frame(width: 220)
                    } else {
                        Button("Scarica il modello di ricerca") { stato.scaricaModello(Modelli.siglip) }
                    }
                }
            } else if stato.inRisultati && stato.foto.isEmpty {
                ContentUnavailableView("Nessuna foto trovata", systemImage: "photo.on.rectangle.angled",
                                       description: Text("Prova con altre parole, ad esempio un luogo, un oggetto o un momento della giornata."))
            } else if stato.radiciAccesso.isEmpty {
                ContentUnavailableView {
                    Label("Dove sono le tue foto?", systemImage: "folder")
                } description: {
                    Text("Scegli la cartella che contiene tutte le tue foto, ad esempio Immagini o un disco esterno. FotoTag trova da solo RAW, HEIC, JPG e TIFF nelle sottocartelle e non modifica nulla.")
                } actions: {
                    Button("Scegli cartella o disco…") { stato.chiediAccesso() }.buttonStyle(.borderedProminent)
                }
            } else if stato.cartellaScelta == nil {
                ContentUnavailableView("Nessuna cartella", systemImage: "folder.badge.plus",
                                       description: Text("Scegli una cartella nella barra laterale, o dai accesso a un disco con File ▸ Aggiungi disco o cartella… (⌘O)."))
            } else if stato.foto.isEmpty {
                ContentUnavailableView("Nessuna foto", systemImage: "photo.on.rectangle",
                                       description: Text(stato.includiSottocartelle ? String(localized: "La cartella e le sue sottocartelle non contengono foto.")
                                                         : String(localized: "Questa cartella non ha foto proprie. Le sottocartelle si vedono con Vista ▸ Includi le sottocartelle.")))
            } else if stato.fotoVisibili.isEmpty {
                ContentUnavailableView {
                    Label(["daRivedere": String(localized: "Nessuna foto da rivedere"), "riviste": String(localized: "Nessuna foto confermata"),
                           "errori": String(localized: "Nessuna foto con errore")][stato.filtro.rawValue, default: String(localized: "Nessuna foto")],
                          systemImage: "line.3.horizontal.decrease.circle")
                } actions: {
                    Button("Mostra tutte") { stato.filtro = .tutte }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            // scende quando si entra nei risultati e risale con Esc (D67); la griglia non si anima
            Group {
                if stato.inRisultati && stato.raccolta == nil {
                    StrisciaRicerca(ricerca: stato.ricerca).transition(Movimento.dal(.top, riduci: riduci))
                }
            }
            .animation(Movimento.standard, value: stato.inRisultati && stato.raccolta == nil)
        }
    }
}

/// Barra della finestra, uguale in griglia e in foto grande: etichette fisse, i numeri nel sottotitolo e negli aiuti.
struct BarraFoto: ToolbarContent {
    @EnvironmentObject var stato: Stato

    var body: some ToolbarContent {
        // sempre gli stessi elementi, con larghezze fisse: cambia solo il loro stato
        ToolbarItem(placement: .navigation) {
            Toggle(isOn: $stato.fotoGrande) { Label("Foto grande", systemImage: "photo") }
            .toggleStyle(.button)
            .disabled(stato.fotoScelta == nil)
            .help(stato.fotoGrande ? String(localized: "Torna alla griglia (spazio o Esc)") : String(localized: "Apri la foto grande (spazio)"))
        }
        ToolbarItemGroup {
            FiltroGriglia()
            Toggle(isOn: $stato.includiSottocartelle) { Label("Includi le sottocartelle", systemImage: "rectangle.stack") }
                .toggleStyle(.button)
                .labelStyle(.iconOnly)
                .disabled(stato.inRisultati)
                .help("Includi le sottocartelle (⌥⌘S)")
            DimensioneMiniature().disabled(stato.fotoGrande)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            let quali = stato.daAnalizzareOra
            Button { stato.analizza(quali) } label: { Label("Analizza", systemImage: "sparkles") }
                .labelStyle(.titleAndIcon)
                .disabled(quali.isEmpty || stato.inCorso || stato.inRisultati)
                .help(quali.isEmpty ? String(localized: "Nessuna foto da analizzare")
                      : stato.selezione.count > 1 ? String(localized: "Analizza \(quali.count) foto non ancora analizzate tra le selezionate")
                      : String(localized: "Analizza \(quali.count) foto non ancora analizzate"))
            // la conferma non scrive nei file: quante foto aspettano la scrittura lo dice il sottotitolo
            let n = stato.daScrivere.count
            Button { stato.chiediScrittura(stato.daScrivere) } label: { Label("Scrivi nei file", systemImage: "square.and.arrow.down") }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.borderedProminent)
                .disabled(n == 0 || stato.inCorso)
                .help(n == 0 ? String(localized: "Nessuna foto confermata da scrivere")
                      : String(localized: "\(n) foto confermate da scrivere: tag e didascalie nei file, dopo una conferma con l'elenco (⌘S)"))
            Button { stato.ispettore.toggle() } label: { Label("Revisione", systemImage: "sidebar.trailing") }
                .help(stato.ispettore ? String(localized: "Nascondi la revisione (⌥⌘I)") : String(localized: "Mostra la revisione (⌥⌘I)"))
        }
    }
}

/// Posizione delle caselle visibili nella griglia (spazio «griglia»). Classe e non @State di valore:
/// si aggiorna a ogni scorrimento senza ridisegnare la griglia.
final class RegistroCornici {
    var cornici: [FotoRecord.ID: CGRect] = [:]
}

/// Area AppKit sotto le miniature: riceve il mouse dove non c'è una casella e disegna la selezione a
/// rettangolo (coordinate dall'alto a sinistra, come lo spazio «griglia» della vista che la contiene).
struct AreaRettangolo: NSViewRepresentable {
    var inizio: (_ comando: Bool) -> Void
    var trascina: (CGRect) -> Void
    var fine: () -> Void

    func makeNSView(context: Context) -> Vista {
        let v = Vista()
        v.azioni = self
        return v
    }

    func updateNSView(_ v: Vista, context: Context) { v.azioni = self }

    final class Vista: NSView {
        var azioni: AreaRettangolo?
        private var partenza: CGPoint?
        override var isFlipped: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with e: NSEvent) {
            partenza = convert(e.locationInWindow, from: nil)
            azioni?.inizio(e.modifierFlags.contains(.command))
        }

        override func mouseDragged(with e: NSEvent) {
            guard let a = partenza else { return }
            // oltre il bordo della griglia la vista scorre da sola (le coordinate restano quelle del contenuto)
            autoscroll(with: e)
            let b = convert(e.locationInWindow, from: nil)
            azioni?.trascina(CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y)))
        }

        override func mouseUp(with e: NSEvent) {
            partenza = nil
            azioni?.fine()
        }
    }
}

/// Tutte / Da rivedere / Confermate / Errori, con i conteggi della cartella.
struct FiltroGriglia: View {
    @EnvironmentObject var stato: Stato

    var body: some View {
        let conta = { (s: StatoFoto) in stato.foto.filter { $0.stato == s }.count }
        let errori = conta(.errore)
        Picker("Mostra", selection: $stato.filtro) {
            Text("Tutte").tag(FiltroStato.tutte)
            Text("Da rivedere \(conta(.proposta))").tag(FiltroStato.daRivedere)
            Text("Confermate \(conta(.rivista))").tag(FiltroStato.riviste)
            if errori > 0 || stato.filtro == .errori { Text("Errori \(errori)").tag(FiltroStato.errori) }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(width: 150)  // larghezza fissa: con il numero che cambia la barra si ricomponeva male
        .disabled(stato.raccolta != nil)
        .help("Mostra solo le foto in questo stato")
    }
}

/// Dimensione delle miniature in 5 passi (anche ⌘+ e ⌘− nel menu Vista).
struct DimensioneMiniature: View {
    static let lati = [90, 110, 132, 170, 220]
    @AppStorage("latoMiniatura") private var lato = 132

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "square.grid.3x3").foregroundStyle(.secondary)
            Slider(value: Binding(get: { Double(Self.lati.firstIndex(of: lato) ?? 2) },
                                  set: { lato = Self.lati[Int($0.rounded())] }),
                   in: 0...Double(Self.lati.count - 1), step: 1)
                .frame(width: 80)
            Image(systemName: "square.grid.2x2").foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Dimensione miniature")
    }
}

/// Menu contestuale di una miniatura (o della selezione di cui fa parte).
struct MenuFoto: View {
    @EnvironmentObject var stato: Stato
    let quali: [FotoRecord]

    var body: some View {
        let n = quali.count
        let suffisso = n > 1 ? " (\(n))" : ""
        let nuove = quali.filter { ($0.stato == .daAnalizzare || $0.stato == .errore) && stato.analizzabile($0) }
        let analizzate = quali.filter { $0.stato == .proposta || $0.stato == .rivista }
        Button(String(localized: "Analizza") + (nuove.count > 1 ? " (\(nuove.count))" : "")) { stato.analizza(nuove) }
            .disabled(nuove.isEmpty || stato.inCorso)
        Button(String(localized: "Rianalizza") + suffisso) { stato.analizza(quali, diversa: true) }
            .disabled(analizzate.isEmpty || stato.inCorso)
        Divider()
        Button(String(localized: "Conferma tag") + suffisso) { stato.segna(quali, .rivista) }
            .disabled(!quali.contains { $0.stato == .proposta })
        Button(String(localized: "Segna da rivedere") + suffisso) { stato.segna(quali, .proposta) }
            .disabled(!quali.contains { $0.stato == .rivista })
        Divider()
        let riviste = quali.filter { $0.stato == .rivista }
        Button(String(localized: "Scrivi nei file…") + (riviste.count > 1 ? " (\(riviste.count))" : "")) { stato.chiediScrittura(riviste) }
            .disabled(riviste.isEmpty || stato.inCorso)
        Button("Mostra nel Finder") { NSWorkspace.shared.activateFileViewerSelecting(quali.map(\.url)) }
        if let f = quali.first { Button("Apri con Quick Look") { AnteprimaRapida.condivisa.mostra(f.url) } }
    }
}

/// Menu Foto della barra dei menu: le stesse azioni dei pulsanti della barra e del pannello.
struct MenuComandiFoto: View {
    @EnvironmentObject var stato: Stato

    var body: some View {
        let scelte = stato.selezione.count > 1 ? stato.selezionate : stato.foto.filter { $0.id == stato.fotoScelta }
        Button("Analizza") { stato.analizza(stato.daAnalizzareOra) }
            .disabled(stato.daAnalizzareOra.isEmpty || stato.inCorso || stato.inRisultati)
        Button("Rianalizza") { stato.analizza(scelte, diversa: true) }
            .disabled(!scelte.contains { $0.stato != .daAnalizzare } || stato.inCorso)
        Divider()
        Button("Conferma tag") { stato.confermaSelezione() }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(stato.fotoScelta == nil)
        Button("Riapri") { stato.riapriSelezione() }
            .disabled(!scelte.contains { $0.stato == .rivista })
        Divider()
        Button("Scrivi nei file…") { stato.chiediScrittura(stato.daScrivere) }
            .keyboardShortcut("s")
            .disabled(stato.daScrivere.isEmpty || stato.inCorso)
        Divider()
        Toggle("Foto grande", isOn: $stato.fotoGrande).disabled(stato.fotoScelta == nil)
        // senza scorciatoia nel menu: una Z senza modificatori ruberebbe la lettera ai campi di testo
        Toggle("Foto al 100%", isOn: Binding(get: { stato.zoom != nil }, set: { _ in stato.cambiaZoom() }))
            .disabled(stato.fotoScelta == nil)
        Picker("Mostra", selection: $stato.filtro) {
            Text("Tutte").tag(FiltroStato.tutte)
            Text("Da rivedere").tag(FiltroStato.daRivedere)
            Text("Confermate").tag(FiltroStato.riviste)
            Text("Errori").tag(FiltroStato.errori)
        }
        Divider()
        Button("Mostra la foto nel Finder") { NSWorkspace.shared.activateFileViewerSelecting(scelte.map(\.url)) }
            .disabled(scelte.isEmpty)
        Button("Apri con Quick Look") { if let f = scelte.first { AnteprimaRapida.condivisa.mostra(f.url) } }
            .disabled(scelte.isEmpty)
    }
}

/// Revisione di più foto insieme: tag in comune da togliere, tag da aggiungere a tutte, stato.
struct RevisioneMultipla: View {
    @EnvironmentObject var stato: Stato
    @FocusState private var campoTag: Bool

    var body: some View {
        let sel = stato.selezionate
        let analizzate = sel.filter { $0.stato == .proposta || $0.stato == .rivista }
        // quante foto selezionate hanno ciascun tag, dal più frequente
        let frequenze = Dictionary(analizzate.flatMap(\.parole).map { ($0, 1) }, uniquingKeysWith: +)
        let tag = frequenze.keys.sorted { (frequenze[$0]!, $1) > (frequenze[$1]!, $0) }

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("\(sel.count) foto selezionate").font(.title2.bold())
                Text("\(analizzate.count) analizzate · \(sel.filter { $0.stato == .proposta }.count) da rivedere · \(sel.filter { $0.stato == .rivista }.count) confermate")
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(sel.prefix(30)) { f in
                            Miniatura(url: f.url, lato: 160, impronta: f.impronta).frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }

                Fila(spaziatura: 8) {
                    let nuove = sel.filter { ($0.stato == .daAnalizzare || $0.stato == .errore) && stato.analizzabile($0) }
                    if !nuove.isEmpty {
                        Button { stato.analizza(nuove) } label: { Label("Analizza (\(nuove.count))", systemImage: "sparkles") }
                    }
                    if !analizzate.isEmpty {
                        Button { stato.analizza(sel, diversa: true) } label: { Label("Rianalizza (\(sel.count))", systemImage: "arrow.clockwise") }
                            .help("Chiede al modello una proposta diversa; i tag aggiunti a mano restano")
                        Button { stato.segna(sel, .rivista) } label: { Label("Conferma tag", systemImage: "checkmark") }
                    }
                }
                .disabled(stato.inCorso)

                if !analizzate.isEmpty {
                    Text("Tag delle foto selezionate").font(.subheadline).foregroundStyle(.secondary)
                    Text("Il numero indica in quante foto compare; × lo toglie da tutte.").font(.caption).foregroundStyle(.secondary)
                    Fila(spaziatura: 6) {
                        ForEach(tag, id: \.self) { t in
                            CapsulaTag(testo: t, aiuto: String(localized: "Togli «\(t)» da tutte le foto selezionate"),
                                       voce: String(localized: "Togli \(t) da tutte le foto selezionate")) {
                                Text("\(frequenze[t]!)").font(.caption).foregroundStyle(.secondary)
                            } togli: { stato.togliTag(t, da: analizzate) }
                        }
                    }
                    // presenti: solo i tag che hanno già tutte; vicini: dalle foto della cartella fuori dalla selezione
                    let tutte = Set(tag.filter { frequenze[$0] == analizzate.count })
                    CampoTag(suggerimento: String(localized: "Aggiungi un tag a tutte (T)"), presenti: tutte,
                             vicini: Suggerimenti.frequenti(Suggerimenti.conta(stato.foto.filter { !stato.selezione.contains($0.id) }.map(\.parole)),
                                                            esclusi: tutte, massimo: 5),
                             fuoco: $campoTag) { t in stato.aggiungiTag(t, a: analizzate) }
                }
                SezioneFissiMultipla(quali: analizzate)
                Text("⌘-clic aggiunge o toglie una foto, ⇧-clic seleziona un intervallo, ⌘A le seleziona tutte.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .onChange(of: stato.fuocoTag) { _, v in if v { campoTag = true; stato.fuocoTag = false } }
    }
}

struct Casella: View {
    let foto: FotoRecord
    let scelta: Bool
    var lato: Int = 132
    var inAnalisi = false

    /// Originale non scaricato ma con l'anteprima salvata.
    var soloAnteprima: Bool {
        Immagini.daScaricare(foto.url) && Anteprime.trova(impronta: foto.impronta, in: Stato.cartellaAnteprimeImpostata) != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // casella quadrata: la foto la riempie e si taglia ai bordi
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                // la foto riempie il quadrato e ne esce: clipShape taglia il disegno ma non i clic, quindi
                // la parte che esce non deve ricevere il mouse (prendeva i clic della casella accanto)
                .overlay { Miniatura(url: foto.url, lato: max(260, lato * 2), riempi: true, impronta: foto.impronta, dissolvenza: true).allowsHitTesting(false) }
                .overlay { if inAnalisi { LineaScanner() } }
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .contentShape(RoundedRectangle(cornerRadius: 5))
                .overlay(alignment: .topTrailing) { Distintivo(foto: foto).padding(6) }
                .overlay(alignment: .bottomLeading) {
                    if soloAnteprima {
                        Image(systemName: "icloud").font(.system(size: 9, weight: .semibold))
                            .frame(width: 18, height: 18)
                            .background(.regularMaterial, in: Circle())
                            .padding(6)
                            .help("Originale solo sul disco in cloud: qui si vede l'anteprima salvata")
                    }
                }
            Text(foto.nome).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                .padding(.top, 5)
        }
        .padding(4)
        .background {
            if scelta {
                RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.2))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 2))
            }
        }
        .help(foto.scrittaIl == nil ? "" : foto.modificataDopo ? String(localized: "Tag cambiati dopo l'ultima scrittura nei file") : String(localized: "Tag scritti nei file"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(foto.nome), \(inAnalisi ? String(localized: "in analisi") : foto.stato.etichetta)" + (soloAnteprima ? String(localized: ", originale solo sul disco in cloud") : ""))
        .accessibilityAddTraits(scelta ? [.isButton, .isSelected] : .isButton)
    }
}

/// Un solo distintivo per casella, in alto a destra; le foto da analizzare non ne hanno.
struct Distintivo: View {
    let foto: FotoRecord
    @Environment(\.accessibilityReduceMotion) private var riduci
    var body: some View {
        segno  // ogni distintivo entra a fine analisi invece di comparire (D67)
    }

    @ViewBuilder var segno: some View {
        switch foto.stato {
        case .daAnalizzare: EmptyView()
        case .proposta: capsula("da rivedere", Color.accentColor)
        case .errore: capsula("errore", .red)
        case .rivista:
            if foto.scrittaIl != nil && foto.modificataDopo {
                capsula("da riscrivere", .orange)
            } else {
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.green)
                    .frame(width: 18, height: 18)
                    .background(.regularMaterial, in: Circle())
                    .transition(Movimento.comparsa(riduci: riduci))
            }
        }
    }

    func capsula(_ testo: LocalizedStringKey, _ colore: Color) -> some View {
        Text(testo).font(.caption2.weight(.semibold)).foregroundStyle(.white)
            .padding(.vertical, 2).padding(.horizontal, 7)
            .background(colore, in: Capsule())
            .transition(Movimento.comparsa(riduci: riduci))
    }
}

/// Miniatura caricata in background e tenuta in memoria.
struct Miniatura: View {
    let url: URL
    let lato: Int
    var riempi = false   // true: riempie la casella (scaledToFill), da tagliare con clipShape
    var impronta: String? = nil  // per l'anteprima salvata quando la foto è solo sul disco in cloud
    var proporzioni = false      // true: la casella prende le proporzioni della foto (3:2 finché non arriva)
    var dissolvenza = false      // griglia e striscia (D67): fondo fermo senza rotellina, la foto entra se arriva dal disco
    @State private var immagine: NSImage?
    @State private var inCloud = false
    static let cache = NSCache<NSString, NSImage>()

    var body: some View {
        Group {
            // solo su richiesta: un aspectRatio(nil) toglierebbe il riempimento alle caselle della griglia
            if proporzioni {
                casella.aspectRatio(immagine.map { $0.size.width / max($0.size.height, 1) } ?? 1.5, contentMode: .fit)
            } else {
                casella
            }
        }
        .task(id: url) { await carica() }
    }

    var casella: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let immagine {
                Group {
                    if riempi {
                        Image(nsImage: immagine).resizable().scaledToFill()
                    } else {
                        Image(nsImage: immagine).resizable().scaledToFit()
                    }
                }
                .transition(.opacity)
            } else if inCloud {
                Image(systemName: "icloud.and.arrow.down").font(.title2).foregroundStyle(.secondary)
                    .help("Foto non scaricata dal disco in cloud")
            } else if !dissolvenza {
                ProgressView().controlSize(.small)
            }
        }
    }

    func carica() async {
        let (u, l) = (url, lato)
        var sorgente = u
        if Immagini.daScaricare(u) {
            // con l'anteprima salvata non si scarica nulla; senza, si chiede il file (sulla coda dedicata)
            if let a = Anteprime.trova(impronta: impronta, in: Stato.cartellaAnteprimeImpostata) {
                sorgente = a
            } else if Scrittura.eRAW(u) {
                inCloud = true  // un RAW non scaricato non si scarica da solo: sono file enormi
                return
            } else {
                inCloud = true
                guard await Immagini.scarica(u, attesa: 120) else { return }
                inCloud = false
            }
        }
        let chiave = "\(sorgente.path)#\(l)" as NSString
        if let c = Miniatura.cache.object(forKey: chiave) { immagine = c; return }
        let s = sorgente
        let img = await Task.detached(priority: .utility) { () -> NSImage? in
            guard let cg = Immagini.miniatura(s, lato: l) else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }.value
        if let img { Miniatura.cache.setObject(img, forKey: chiave) }
        // dalla memoria compare subito (sopra); dal disco entra con una dissolvenza breve
        if dissolvenza { withAnimation(Movimento.rapida) { immagine = img } } else { immagine = img }
    }
}

struct Revisione: View {
    @EnvironmentObject var stato: Stato
    @Environment(\.accessibilityReduceMotion) private var riduci
    @State var foto: FotoRecord
    @State private var fissiAperti = false
    @FocusState private var campoTag: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // parte fissa: anteprima di altezza costante, così «Conferma tag» non si sposta da una foto all'altra
            VStack(alignment: .leading, spacing: 12) {
                // in foto grande l'anteprima sarebbe doppia
                if !stato.fotoGrande {
                    Miniatura(url: foto.url, lato: 1400, impronta: foto.impronta)
                        .frame(maxWidth: .infinity).frame(height: 240)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                        .onTapGesture { stato.fotoGrande = true }
                        .accessibilityLabel("Anteprima di \(foto.nome)")
                        .accessibilityAddTraits(.isButton)
                        .help("Apri la foto grande (spazio)")
                }

                HStack(alignment: .firstTextBaseline) {
                    Text(foto.nome).font(.headline).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(foto.stato.etichetta).font(.callout.weight(.semibold)).foregroundStyle(coloreStato)
                }
                .help(foto.secondi.map { String(localized: "Analizzata in \($0.formatted(.number.precision(.fractionLength(1)))) s") } ?? "")

                azioni.controlSize(.large)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if foto.stato != .daAnalizzare {
                        etichetta("Didascalia")
                        TextField("Didascalia", text: $foto.didascalia, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...4)
                            .onSubmit { salva(NomiAzioni.didascalia) }

                        etichetta("Tag")
                        Fila(spaziatura: 6) {
                            ForEach(foto.parole, id: \.self) { p in
                                CapsulaTag(testo: p, aiuto: String(localized: "Togli «\(p)»"), voce: String(localized: "Togli il tag \(p)"), togli: {
                                    // il tag si stringe e svanisce, gli altri scivolano al loro posto (D67)
                                    withAnimation(Movimento.standard) { foto.parole.removeAll { $0 == p } }
                                    salva(NomiAzioni.togliTag(p))
                                })
                                .transition(Movimento.comparsa(riduci: riduci))
                            }
                        }
                        let presenti = Set(foto.parole)
                        CampoTag(suggerimento: String(localized: "Aggiungi un tag (T)"), presenti: presenti,
                                 vicini: stato.tagVicini(a: foto, presenti: presenti), fuoco: $campoTag) { t in
                            withAnimation(Movimento.standard) { foto.parole.append(t) }
                            salva(NomiAzioni.aggiungiTag(t))
                        }
                        if !foto.scartate.isEmpty {
                            Text("Scartate dalla pulizia: \(foto.scartate.joined(separator: ", "))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    DisclosureGroup(isExpanded: $fissiAperti) {
                        VStack(alignment: .leading, spacing: 10) {
                            SezioneFissi(foto: $foto)
                            RigaOriginale(foto: foto)
                        }
                        .padding(.top, 6)
                    } label: {
                        HStack(spacing: 6) {
                            Text("Tag fissi").fontWeight(.semibold)
                            if let t = foto.fissi {
                                Text(riassunto(t)).foregroundStyle(.secondary).lineLimit(1)
                                if !t.daVerificare.isEmpty {
                                    Label { Text("da verificare").foregroundStyle(.secondary) } icon: {
                                        Image(systemName: "questionmark.circle.fill").foregroundStyle(.orange)
                                    }
                                    .fixedSize()
                                }
                            }
                        }
                    }

                    if foto.stato != .daAnalizzare {
                        Text(stato.fotoGrande ? String(localized: "↩ conferma e prossima, ← → cambia foto, spazio o Esc torna alla griglia, ⌘Z annulla")
                                              : String(localized: "↩ conferma e passa alla prossima, ← → cambia foto, spazio ingrandisce, ⌘Z annulla"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
        }
        .onAppear {
            fissiAperti = !(foto.fissi?.daVerificare.isEmpty ?? true)
            if stato.fuocoTag { campoTag = true; stato.fuocoTag = false }
        }
        .onChange(of: stato.fuocoTag) { _, v in if v { campoTag = true; stato.fuocoTag = false } }
        .onChange(of: stato.foto.first { $0.id == foto.id }) { _, nuova in
            // l'analisi in background (o la griglia) ha aggiornato questa foto
            if let nuova, nuova.stato != foto.stato || nuova.parole != foto.parole || nuova.fissi != foto.fissi
                || nuova.didascalia != foto.didascalia
                || nuova.raw != foto.raw || nuova.rawLivello != foto.rawLivello { foto = nuova }
        }
        .onDisappear { salvaTesti() }
    }

    /// Azione principale della foto, sempre nello stesso punto; Rianalizza nel menu «…».
    @ViewBuilder
    var azioni: some View {
        if foto.stato == .daAnalizzare, !stato.analizzabile(foto) {
            Label("RAW senza JPG: per ora solo da vedere", systemImage: "eye").foregroundStyle(.secondary)
        } else if foto.stato == .daAnalizzare {
            Button { stato.analizza([foto]) } label: { Label("Analizza questa foto", systemImage: "sparkles").frame(maxWidth: .infinity) }
                .disabled(stato.inCorso)
        } else {
            HStack(spacing: 8) {
                if foto.stato == .rivista {
                    Button { foto.stato = .proposta; salva(NomiAzioni.riapri(1)) } label: { Text("Riapri").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                } else {
                    Button { salvaTesti(); stato.rivistaEProssima() } label: {
                        Label("Conferma tag", systemImage: "checkmark").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Conferma i tag e passa alla prossima da rivedere (↩ nella griglia, ⌘↩ dai campi). Non scrive nei file.")
                }
                Menu {
                    Button("Rianalizza") { stato.analizza([foto], diversa: true) }
                        .disabled(stato.inCorso)
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Altre azioni: Rianalizza chiede al modello una proposta diversa, i tag aggiunti a mano restano")
                .accessibilityLabel("Altre azioni")
            }
        }
    }

    var coloreStato: Color {
        switch foto.stato {
        case .proposta: return .accentColor
        case .errore: return .red
        case .rivista, .daAnalizzare: return .secondary
        }
    }

    func etichetta(_ t: LocalizedStringKey) -> some View {
        Text(t).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
    }

    /// «2024, rullino 1315, analogica, bianco e nero»: i campi presenti.
    func riassunto(_ t: TagFissi) -> String {
        var p: [String] = []
        if let y = t.anno { p.append(String(y)) }
        p += t.rullini.map { String(localized: "rullino \($0)") }
        if let o = t.origine { p.append(o == "digitale" ? String(localized: "digitale") : String(localized: "analogica")) }
        if let bn = t.biancoNero { p.append(bn ? String(localized: "bianco e nero") : String(localized: "colore")) }
        return p.joined(separator: ", ")
    }

    func salva(_ azione: String) { stato.cambia([foto], azione: azione) }

    /// All'uscita salva solo la didascalia (l'unico campo che non si salva subito), sopra lo stato attuale:
    /// la griglia può aver appena segnato la foto come rivista e una copia vecchia non deve riportarla indietro.
    func salvaTesti() {
        guard var attuale = stato.foto.first(where: { $0.id == foto.id }), attuale.didascalia != foto.didascalia else { return }
        attuale.didascalia = foto.didascalia
        stato.cambia([attuale], azione: NomiAzioni.didascalia)
    }
}

/// Capsula di un tag con il pulsante × (22×22, facile da colpire).
struct CapsulaTag<Extra: View>: View {
    let testo: String
    let aiuto: String
    let voce: String
    let extra: Extra
    let togli: () -> Void

    init(testo: String, aiuto: String, voce: String, @ViewBuilder extra: () -> Extra, togli: @escaping () -> Void) {
        self.testo = testo
        self.aiuto = aiuto
        self.voce = voce
        self.extra = extra()
        self.togli = togli
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(testo)
            extra
            Button(action: togli) {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    .frame(width: 22, height: 22)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(aiuto)
            .accessibilityLabel(voce)
        }
        .frame(height: 26)
        .padding(.leading, 10).padding(.trailing, 2)
        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
    }
}

extension CapsulaTag where Extra == EmptyView {
    init(testo: String, aiuto: String, voce: String, togli: @escaping () -> Void) {
        self.init(testo: testo, aiuto: aiuto, voce: voce, extra: { EmptyView() }, togli: togli)
    }
}

/// Disposizione a capo automatico per i tag.
struct Fila: Layout {
    var spaziatura: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let larghezza = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, riga: CGFloat = 0
        for s in subviews {
            let d = s.sizeThatFits(.unspecified)
            if x + d.width > larghezza, x > 0 { x = 0; y += riga + spaziatura; riga = 0 }
            x += d.width + spaziatura
            riga = max(riga, d.height)
        }
        return CGSize(width: larghezza, height: y + riga)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, riga: CGFloat = 0
        for s in subviews {
            let d = s.sizeThatFits(.unspecified)
            if x + d.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += riga + spaziatura; riga = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(d))
            x += d.width + spaziatura
            riga = max(riga, d.height)
        }
    }
}
