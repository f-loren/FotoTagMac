import AppKit
import Quartz

/// Quick Look di sistema su una foto (Spazio o doppio clic), finché non c'è la foto grande dentro l'app.
/// Lo stesso tasto o un'altra foto con il pannello aperto: si chiude o si aggiorna.
@MainActor
final class AnteprimaRapida: NSObject, QLPreviewPanelDataSource {
    static let condivisa = AnteprimaRapida()
    private var url: URL?

    func mostra(_ u: URL) {
        guard let p = QLPreviewPanel.shared() else { return }
        if p.isVisible && url == u { p.orderOut(nil); return }
        url = u
        p.dataSource = self
        if p.isVisible { p.reloadData() } else { p.makeKeyAndOrderFront(nil) }
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { 1 }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        MainActor.assumeIsolated { url.map { $0 as NSURL } }
    }
}
