import AppKit
import FotoTagCore
import SwiftUI
import UserNotifications

/// Icona nel Dock (avanzamento, foto da rivedere) e notifica di fine analisi. Si spengono in Impostazioni ▸
/// Generali ▸ Avvisi.
extension Stato {
    static let notificaMostra = Notification.Name("FotoTagMostraDaRivedere")

    var dockAvanzamento: Bool { UserDefaults.standard.object(forKey: "dockAvanzamento") as? Bool ?? true }
    var dockDistintivo: Bool { UserDefaults.standard.object(forKey: "dockDistintivo") as? Bool ?? true }
    var notificaFine: Bool {
        Bundle.main.bundleIdentifier != nil && UserDefaults.standard.object(forKey: "notificaFine") as? Bool ?? true
    }

    /// Barra sull'icona durante l'analisi, al massimo ogni 2 s; nil la toglie.
    func aggiornaDock(forza: Bool = false) {
        let tile = NSApp.dockTile
        guard inCorso, dockAvanzamento else {
            if tile.contentView != nil { tile.contentView = nil; tile.display() }
            return
        }
        guard forza || Date().timeIntervalSince(ultimoDock) >= 2 else { return }
        ultimoDock = Date()
        let v = NSHostingView(rootView: IconaDock(progresso: Double(fatte) / Double(max(totale, 1))))
        v.frame = NSRect(origin: .zero, size: tile.size)
        tile.contentView = v
        tile.display()
    }

    /// Numero di foto da rivedere in tutte le cartelle, sull'icona (vuoto a zero).
    func aggiornaDistintivo() {
        let n = dockDistintivo ? conteggi.values.reduce(0) { $0 + $1.daRivedere } : 0
        NSApp.dockTile.badgeLabel = Avvisi.distintivo(n)
    }

    /// Il permesso si chiede alla prima analisi, non all'avvio.
    func chiediPermessoNotifiche() {
        guard notificaFine else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notificaFineAnalisi(cartella c: Cartella?, analizzate: Int, errori: Int, interrotta: Bool) {
        guard notificaFine, let c else { return }
        let (titolo, testo) = interrotta ? Avvisi.interrotta(cartella: c.nome, dopo: fatte)
            : Avvisi.fine(cartella: c.nome, analizzate: analizzate, daRivedere: conteggi[c.id]?.daRivedere ?? 0, errori: errori)
        let n = UNMutableNotificationContent()
        n.title = titolo
        n.body = testo
        n.categoryIdentifier = "fineAnalisi"
        n.userInfo = ["cartella": c.id]
        let centro = UNUserNotificationCenter.current()
        centro.setNotificationCategories([UNNotificationCategory(
            identifier: "fineAnalisi",
            actions: [UNNotificationAction(identifier: "mostra", title: String(localized: "Mostra le foto da rivedere"), options: [.foreground])],
            intentIdentifiers: [])])
        centro.add(UNNotificationRequest(identifier: UUID().uuidString, content: n, trigger: nil))
    }

    /// Dalla notifica: la finestra in primo piano sulla cartella, filtro «Da rivedere».
    func mostraDaRivedere(cartella id: Int64) {
        NSApp.activate(ignoringOtherApps: true)
        if inRisultati { ricerca.frase = ""; esciDaiRisultati() }
        schermata = .tagga
        cartellaScelta = id
        filtro = .daRivedere
    }
}

/// Icona dell'app con la barra di avanzamento in basso (bianca su fondo scuro).
struct IconaDock: View {
    let progresso: Double

    var body: some View {
        ZStack(alignment: .bottom) {
            Image(nsImage: NSApp.applicationIconImage).resizable()
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.black.opacity(0.65))
                    Capsule().fill(.white).padding(2).frame(width: max(8, g.size.width * progresso))
                }
            }
            .frame(height: 14)
            .padding(.horizontal, 14).padding(.bottom, 10)
        }
    }
}
