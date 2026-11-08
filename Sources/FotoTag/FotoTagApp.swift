import AppKit
import FotoTagCore
import SwiftUI
import UserNotifications

@main
struct FotoTagApp: App {
    @NSApplicationDelegateAdaptor private var delegato: Delegato
    @StateObject private var stato = Stato()
    @Environment(\.openWindow) private var apriFinestra

    @AppStorage("latoMiniatura") private var latoMiniatura = 132

    func cambiaLato(_ passo: Int) {
        let l = DimensioneMiniature.lati
        let i = (l.firstIndex(of: latoMiniatura) ?? 2) + passo
        latoMiniatura = l[min(max(i, 0), l.count - 1)]
    }

    var body: some Scene {
        WindowGroup("FotoTag") {
            Principale()
                .environmentObject(stato)
                .frame(minWidth: 1000, minHeight: 620)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("Informazioni su FotoTag") { TestiApp.mostraInformazioni() }
                Button("Riconoscimenti…") { apriFinestra(id: "riconoscimenti") }
                Button("Esporta diagnostica…") { stato.esportaDiagnostica() }
            }
            CommandGroup(after: .newItem) {
                Button("Aggiungi disco o cartella…") { stato.chiediAccesso() }.keyboardShortcut("o")
                Button("Aggiorna l'indice") { stato.indicizza() }
                    .keyboardShortcut("r")
                    .disabled(stato.indicizzazione != nil)
                MenuRecenti().environmentObject(stato)
                Divider()
                Button("Mostra nel Finder") {
                    if let c = stato.cartellaCorrente { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: c.percorso)]) }
                }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(stato.cartellaCorrente == nil)
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Cerca") { Stato.fuocoNellaRicerca() }.keyboardShortcut("f")
            }
            CommandMenu("Foto") { MenuComandiFoto().environmentObject(stato) }
            CommandGroup(before: .toolbar) {
                Toggle("Includi le sottocartelle", isOn: $stato.includiSottocartelle)
                    .keyboardShortcut("s", modifiers: [.command, .option])
                    .disabled(stato.inRisultati)
                Button("Miniature più grandi") { cambiaLato(+1) }.keyboardShortcut("+")
                Button("Miniature più piccole") { cambiaLato(-1) }.keyboardShortcut("-")
                Toggle("Mostra la revisione", isOn: $stato.ispettore).keyboardShortcut("i", modifiers: [.command, .option])
                Divider()
            }
        }
        Window("Riconoscimenti", id: "riconoscimenti") { FinestraRiconoscimenti() }
            .defaultSize(width: 680, height: 620)
        Settings {
            TabView {
                // una sola misura per tutte le schede: la finestra non salta
                Impostazioni().environmentObject(stato).frame(width: 600, height: 460)
                    .tabItem { Label("Generali", systemImage: "gearshape") }
                ImpostazioniProfili().environmentObject(stato).frame(width: 600, height: 460)
                    .tabItem { Label("Profili", systemImage: "folder.badge.gearshape") }
                ImpostazioniOriginali().environmentObject(stato).frame(width: 600, height: 460)
                    .tabItem { Label("Originali", systemImage: "externaldrive") }
                ImpostazioniModelli().environmentObject(stato).frame(width: 600, height: 460)
                    .tabItem { Label("Modelli", systemImage: "cpu") }
            }
        }
    }
}

/// File ▸ Apri recente: le ultime 5 cartelle; a parità di nome si aggiunge la cartella madre.
struct MenuRecenti: View {
    @EnvironmentObject var stato: Stato

    var body: some View {
        Menu("Apri recente") {
            let r = stato.recenti
            ForEach(r) { c in
                let doppio = r.contains { $0.id != c.id && $0.nome == c.nome }
                let madre = ((c.percorso as NSString).deletingLastPathComponent as NSString).lastPathComponent
                Button(doppio ? "\(c.nome) (\(madre))" : c.nome) { stato.continua(c) }
                    .disabled(!FileManager.default.fileExists(atPath: c.percorso))
            }
            Divider()
            Button("Cancella menu") { stato.cancellaRecenti() }.disabled(r.isEmpty)
        }
    }
}

/// Avviato fuori da un pacchetto .app (es. da terminale) l'eseguibile deve diventare un'app normale.
final class Delegato: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // fuori da un pacchetto .app (eseguibile lanciato a mano) le notifiche non esistono e chiamarle chiude l'app
        if Bundle.main.bundleIdentifier != nil { UNUserNotificationCenter.current().delegate = self }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // per le prove: `--istantanea <file.png>` salva un'immagine della finestra dopo qualche secondo
        let a = CommandLine.arguments
        if let i = a.firstIndex(of: "--istantanea"), i + 1 < a.count {
            let dest = URL(fileURLWithPath: a[i + 1])
            let attesa = a.firstIndex(of: "--attesa").flatMap { Double(a[$0 + 1]) } ?? 6
            DispatchQueue.main.asyncAfter(deadline: .now() + attesa) {
                let w = NSApp.windows.first(where: { $0.isVisible && $0.title == String(localized: "Riconoscimenti") && a.contains("--riconoscimenti") })
                    ?? NSApp.windows.first(where: { $0.isVisible && $0.sheetParent == nil })
                guard let v = (w?.attachedSheet ?? w)?.contentView?.superview,
                      let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
                v.cacheDisplay(in: v.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: dest)
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // la notifica si vede anche con FotoTag in primo piano; il clic (o «Mostra le foto da rivedere») apre la cartella
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler fatto: @escaping (UNNotificationPresentationOptions) -> Void) {
        fatto([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive risposta: UNNotificationResponse,
                                withCompletionHandler fatto: @escaping () -> Void) {
        if let id = risposta.notification.request.content.userInfo["cartella"] as? Int64 {
            DispatchQueue.main.async { NotificationCenter.default.post(name: Stato.notificaMostra, object: nil, userInfo: ["cartella": id]) }
        }
        fatto()
    }
}

struct Impostazioni: View {
    @EnvironmentObject var stato: Stato
    @AppStorage("dockAvanzamento") private var dockAvanzamento = true
    @AppStorage("dockDistintivo") private var dockDistintivo = true
    @AppStorage("notificaFine") private var notificaFine = true
    @AppStorage("ricercaInSottofondo") private var ricercaInSottofondo = true
    var body: some View {
        Form {
            Section {
                Picker("Profilo per i nuovi accessi", selection: Binding(get: { stato.idValido(stato.profiloPredefinito) }, set: { stato.profiloPredefinito = $0 })) {
                    ForEach(stato.profili) { Text($0.nomeVisto).tag($0.id) }
                }
                Text(stato.profilo(id: stato.profiloPredefinito).descrizioneVista).font(.caption).foregroundStyle(.secondary)
            }
            Section("Scrittura") {
                Toggle("Copia di sicurezza prima di scrivere nei file", isOn: $stato.copiaDiSicurezza)
                    .help("Gli originali vengono copiati in ~/Library/Application Support/FotoTag/Copie di sicurezza e tenuti 5 giorni.")
                Picker("File .xmp accanto ai RAW", selection: $stato.nomeSidecar) {
                    ForEach(FotoTagCore.Scrittura.NomeSidecar.allCases, id: \.rawValue) { Text($0.descrizione).tag($0.rawValue) }
                }
                .help("Se esiste già un .xmp dell'altro tipo, viene aggiornato anch'esso.")
            }
            Section("Ricerca") {
                Picker("Prepara la ricerca", selection: $ricercaInSottofondo) {
                    Text("In sottofondo").tag(true)
                    Text("Solo quando cerco").tag(false)
                }
                Text("In sottofondo si ferma durante l'analisi e quando il Mac è a batteria. Le foto solo nel disco in cloud non si scaricano mai da sole.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            SezioneCartelle()
            SezioneAnteprime()
            Section("Avvisi") {
                Toggle("Mostra l'avanzamento sull'icona nel Dock", isOn: $dockAvanzamento)
                Toggle("Mostra il numero di foto da rivedere sull'icona", isOn: $dockDistintivo)
                    .onChange(of: dockDistintivo) { _, _ in stato.aggiornaDistintivo() }
                Toggle("Avvisa con una notifica quando un'analisi finisce", isOn: $notificaFine)
            }
            Section {
                Picker("Lingua dei tag", selection: $stato.codiceLingua) {
                    ForEach(Lingua.disponibili, id: \.codice) { l in
                        Text(Locale.current.localizedString(forLanguageCode: l.codice)?.capitalized ?? l.codice).tag(l.codice)
                    }
                }
                .help("Lingua dei tag scritti nei file e del prompt del modello. Le foto già analizzate restano nella lingua di prima: per cambiarle, rianalizzale. I tag fissi (origine, data, pellicola…) cambiano lingua alla prossima scrittura nei file.")
            }
        }
        .formStyle(.grouped)
    }
}
