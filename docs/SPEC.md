# FotoTag: specifica

Scritta a ritroso il 31/10/2026 dal codice al commit `7c31111` (build 88, quella installata). L'app non è stata aperta per scriverla: schermate e flusso sono ricostruiti dal codice, le dimensioni vere sono da controllare sugli screenshot. I numeri tipo «D13» rimandano alla tabella Decisioni in [INTENZIONI.md](INTENZIONI.md), «A1» alle sue Aperte.

## 1. Obiettivo e perimetro

**Cosa fa.** FotoTag riconosce il contenuto delle foto sul Mac, propone tag e didascalia in locale, li fa controllare, li scrive nei file e permette di cercare a parole (D1, D2).

**Chi la usa.** Un fotografo su un solo Mac: oggi Lorenzo, poi 2-5 colleghi (D5, D15). L'app non deve dipendere dal suo archivio (D38).

**Carico.**
- Un utente alla volta, nessun server.
- Mac con chip Apple e macOS 14 o successivo; 16 GB per l'8B, 8 GB per il 4B.
- Decine di migliaia di foto. Riferimento reale: 87.791 foto in 3.557 cartelle, compresi disco esterno e disco in cloud.

**Fuori perimetro.** Vedi «Fuori perimetro» in INTENZIONI.md.

## 2. Flusso utente

Il flusso approvato è D34: Importa (facoltativo) → **Cartelle** → **Analizza** → **Rivedi** → **Scrivi** → Cerca.

1. **Cartelle.** Al primo avvio la griglia chiede «Dove sono le tue foto?» con un solo pulsante, che apre il pannello di macOS. Da lì l'indice si costruisce da solo, a ogni apertura e con ⌘R, senza scaricare i file in cloud (vedi §3 bis).
2. **Analizza.** Sulle foto della cartella o su quelle scelte. Prima si controlla la memoria. Si può fermare e riprendere; le foto in cloud si scaricano una per volta e dopo l'analisi si tolgono di nuovo dal Mac.
3. **Rivedi.** Griglia, filtro per stato, foto grande, pannello con didascalia, tag, tag fissi e originale. «Conferma tag» passa alla prossima da rivedere e non scrive nulla (D28). ⌘Z annulla.
4. **Scrivi.** «Scrivi nei file» (⌘S) vale per le foto confermate della vista aperta, dopo un foglio di conferma.
5. **Cerca.** ⌘F, in tutte le cartelle o in quella aperta. Esc torna alla cartella di prima.

Importa da scheda non è più in FotoTag: vivrà nell'app FotoOrdina (D57, D60).

## 3. Schermate

| Schermata | Contenuto | Codice |
|---|---|---|
| Tagga | Barra con l'albero e l'avanzamento, griglia o foto grande, pannello di revisione | `Viste.swift`, `FotoGrande.swift` |
| Risultati | La griglia raggruppata per cartella | `StatoCerca.swift` |
| Foglio di scrittura | Riepilogo e conferma | `VisteScrittura.swift` |
| Importa | Scheda, gruppi dalle miniature, riepilogo, copia | `Importa.swift` |
| Impostazioni | Generali (con Cartelle: accessi, regole, nascoste), Pellicole, Originali, Modelli | `FotoTagApp.swift`, `VisteFissi.swift`, `StatoOriginali.swift`, `VisteModelli.swift` |

## 3 bis. Cartelle

Regole del modulo (D33, D36, D40, D48-D51). Analisi: `../note/2026-10-31_analisi_cartelle.md`. Mockup: https://claude.ai/artifact/Bn62HZ4vJL35hdmc7jQNCP

- **Accesso:** si dà dalla directory più alta, una volta. Una cartella già compresa in un accesso non ne crea un altro; un accesso nuovo che ne contiene uno vecchio lo assorbe, con le sue regole.
- **Foto:** RAW, HEIC, JPG e TIFF, ovunque sotto un accesso. I PNG non entrano; quelli già nell'indice escono se mai analizzati.
- **Elenco:** una radice per accesso (cartella utente, dischi, dischi in cloud, nell'ordine), sotto il percorso vero, un livello per riga. Compaiono le cartelle con foto e quelle che le contengono.
- **Nascondere:** a mano, dal menu della cartella; si annulla dalle Impostazioni.
- **Disco staccato:** la radice resta, spenta e con «non collegato»; foto, tag e analisi restano. L'elenco si aggiorna quando il disco si collega o si stacca.
- **Copie:** l'app non confronta le foto tra disco e backup: sono foto a sé (D49). Solo una foto scomparsa da un disco collegato si ricollega con l'impronta.
- **Regole del profilo:** una per accesso, nelle Impostazioni; le foto seguono l'accesso più specifico che le contiene.

## 4. Dati

Tutto sta in `~/Library/Application Support/FotoTag/`: database `fototag.db` (SQLite, WAL), `Modelli/`, `pellicole.json`, `Backups/` (fino all'8/11/2026 `Copie di sicurezza/`), anteprime e `log.txt`. Nessun dato esce dal Mac (D2); l'unico traffico di rete è il download dei modelli.

| Tabella | Cosa tiene |
|---|---|
| `accessi` | Radici a cui l'utente ha dato accesso, con segnalibro e profilo |
| `cartelle` | Ogni cartella indicizzata, con ultimo uso e numero di foto |
| `foto` | Stato, tag, didascalia, tag fissi, embedding, RAW collegato, impronta, ciò che è stato scritto |
| `radici_originali`, `originali` | Indice dei RAW, costruito da nomi e date dei file |
| `importati` | Registro dei file già importati |

**Stato di una foto:** `da analizzare` → `proposta` («da rivedere») → `rivista` («confermata»), oppure `errore`. L'identità è l'impronta: dimensione più sha256 dei primi e degli ultimi 64 KB. Serve a non perdere il lavoro se una foto viene spostata.

## 5. Analisi

- Modelli: Qwen3-VL 8B (5,8 GB) dai 16 GB di RAM, altrimenti 4B (3,1 GB), a revisione fissata con controllo dei file scaricati (D13).
- Una foto alla volta, in italiano (D14). Risposta JSON con soggetti, luogo, oggetti, azioni, atmosfera, didascalia; se non è leggibile si riprova una volta, poi si usa la grammatica vincolata.
- Pulizia: niente doppioni, parole tecniche o fuori dal dizionario.
- Errore GPU: una riprova con il modello ricaricato, poi la foto va in errore e l'analisi si ferma (D30).
- Misure: 8-11 s a foto e circa 6,4 GB su M2 Pro 16 GB. Con altri lavori pesanti sul Mac la GPU va in timeout.

**Tag fissi** (non dal modello): origine, tono, data, rullino, pellicola, tiraggio, contesto. Vengono da EXIF, saturazione media (sotto 12 è bianco e nero) e nomi delle cartelle, secondo il profilo. I valori incerti sono «da verificare»; le correzioni a mano si conservano.

**Profili** (D44, D51, D54). Un profilo dice come leggere i nomi delle cartelle: nome della cartella come tag oppure struttura anno/mese/rullino, cartelle da non usare come tag, cartelle che indicano pellicola, sottocartelle da non elencare, giorno della scansione, sigle delle pellicole, ordine delle importazioni. Stanno in `~/Library/Application Support/FotoTag/profili.json`; «Generico» c'è sempre ed è il predefinito. Si scelgono per accesso (Generali ▸ Cartelle) e per cartella di originali, si modificano in Impostazioni ▸ Profili, si scambiano come file JSON. Un profilo tolto vale come Generico finché non lo si reimporta. Il profilo di Lorenzo è `profili/esempio-pellicola.json`, non è nell'app. Cambiare un profilo ricalcola i tag fissi delle foto aperte (le correzioni a mano restano) e rifà l'indice.

## 6. Scrittura nei file

Le regole sono vincolanti: è l'unica funzione che tocca i file dell'utente (D4).

- Solo foto confermate, dopo il foglio di conferma, e mai da sola.
- JPG, TIFF, HEIC: metadati nel file senza ricodificare. Il file temporaneo sostituisce l'originale solo se i pixel sono identici e la rilettura torna.
- RAW: mai modificati. Si scrive il `.xmp` accanto (D18), toccando solo parole chiave, gerarchia e didascalia.
- Campi: `dc:subject`, `dc:description`, `lr:hierarchicalSubject`, IPTC Keywords e Caption-Abstract.
- Le parole chiave altrui restano; si tolgono solo quelle scritte prima da FotoTag.
- Copia di sicurezza accesa di base, disattivabile nelle Impostazioni; ogni scrittura si tiene 5 giorni, poi si elimina da sola all'avvio (D61).
- Non annullabile.

## 7. Collegamento JPG → RAW

Dalle cartelle in Impostazioni ▸ Originali, senza scaricare nulla. Stesso nome nella stessa cartella: sicuro. Altrimenti nome più data di scatto: ± 2 ore sicuro, entro 36 ore probabile, oltre incerto. Il nome da solo non basta: nell'archivio reale circa 5.500 nomi di RAW si ripetono. Si può cambiare o scollegare a mano.

## 8. Ricerca

SigLIP 2 in Core ML (0,75 GB da scaricare, 1,5 sul disco con la copia compilata, D20), scaricato da `f-loren/fototag-siglip2-coreml`. Gli embedding stanno nel database. Dall'8/11 (D65) si calcolano da soli in sottofondo dopo l'indice delle cartelle e dopo il download del modello, prima la cartella aperta, in pausa durante l'analisi e a batteria, con «Ferma» nella barra laterale; Impostazioni ▸ Generali ▸ Ricerca permette «Solo quando cerco» (allora partono al primo carattere nel campo). Dal file se è sul Mac, dall'anteprima salvata se è solo in cloud, senza scaricare; le foto solo in cloud senza anteprima entrano con «Includi…», che le scarica una alla volta, salva anteprima ed embedding e le libera. Le voci restano in memoria fra una ricerca e l'altra e si rileggono solo se il database è cambiato; i risultati non si ricaricano da soli («Aggiorna»). SigLIP si toglie dalla memoria a fine lavoro e in pausa. Il risultato combina somiglianza e parole trovate in tag e didascalia, con soglie 1% (il prototipo usava 2%, A10) e metà delle parole, a forza bruta in memoria.

## 9. Importa da scheda

Tolta da FotoTag l'8/11 (D60): vivrà nell'app FotoOrdina (D57). Il codice di prima è nella storia git fino al commit f663205; anche Riordina non è più nel codice.

## 10. Architettura

**La decisione che conta** è D13: tutto gira nel processo dell'app, con i modelli sul Mac. Da lì vengono privacy, DMG unico e assenza di Python, ma anche il limite: un errore grave della GPU avviene nello stesso processo.

```
Interfaccia (FotoTag, SwiftUI)  ──  Stato*.swift
              │
FotoTagCore (senza SwiftUI)
  Tagger, Pulizia, Lingua        analisi (MLX)
  Contesto, TagFissi             regole e profili
  Indicizzatore, Albero          cartelle
  Archivio                       SQLite
  Scrittura, SidecarXMP          file dell'utente
  Originali, Ricerca, Importazione
              │
fototag-cli                      comando di prova
```

Avvio: `./crea_app.sh`. Prove: `xcodebuild test -scheme FotoTagMac-Package -destination 'platform=macOS'` (96 superate il 31/10).

## 11. Versioni

### v0.1, stato attuale

Tutto ciò che è descritto sopra.

### v0.2, beta per 2-5 fotografi (D42)

| # | Voluto | Com'è oggi | Scarto |
|---|---|---|---|
| 1 | Niente schermata Inizio (D33) | Tolta il 31/10: il primo avvio è la domanda nella griglia | Fatto, da provare nell'app |
| 2 | Revisione: pannello come ispettore, Conferma fisso in alto, fine coda che propone di scrivere (D34.4) | Fatto il 2/11 (build 110): ispettore ⌥⌘I, parte alta fissa, Rianalizza nel menu «…», avviso a fine coda. Tab e ⌫ sui tag non fatti | Da provare nell'app |
| 3 | Menu Foto, barra uguale in ogni vista, filtro in un menu, modale solo per le scelte (D34.6) | Fatto il 2/11 (build 110): menu Foto, barra unica, filtro a menu; notizie in fondo alla barra laterale, gli errori restano avvisi modali | Da provare nell'app |
| 4 | Sezione «Da fare» su tutto l'archivio (D34.2) | Fatto il 3/11: Da rivedere, Da scrivere, Con errore in cima alla barra laterale; la coda si apre nella griglia come i risultati e resta ferma mentre si lavora. La notifica porta ancora alla cartella analizzata | Da provare nell'app |
| 5 | «Scarica e analizza» dove si è (D34.3) | Fatto il 3/11: foglio con il modello e la dimensione, download con avanzamento e «Ferma» in fondo alla barra laterale, poi l'analisi; alla fine la prima foto da rivedere | Da provare nell'app |
| 6 | Foto grande su fondo scuro, zoom al 100% (D34.5) | Fatto il 3/11: grigio neutro, Z o clic per il 100% sul punto cliccato (Esc torna), striscia con le proporzioni vere; il 100% non scarica dal disco in cloud | Da provare nell'app |
| 7 | Generica e personalizzabile (D38, D44, D54) | Fatto il 3/11: scheda Profili, profili come file, Profilo Lorenzo fuori dall'app, `fototag-cli fissi` legge un file di profilo. Restano gli argomenti di prova nell'app | Da provare nell'app |
| 8 | Uso sull'archivio vero e installazione da zero su un Mac pulito (D25, D56) | Mai fatto il secondo, il primo solo per dicembre 2025 (333 foto). Senza DMG (D56, D64): si compila dal repository seguendo il README | Da fare |
| 9 | Copia di sicurezza di ogni file toccato (D25) | Corretto il 31/10: la copia tiene il percorso intero | Fatto, da provare nell'app |
| 10 | Dal disco in cloud non si scarica nulla senza che serva, e ciò che si scarica si libera (D36) | Corretto il 31/10: l'indice di ricerca non scarica, l'analisi libera la foto dopo anteprima ed embedding, la scrittura la riporta sul Mac con una scadenza e dall'8/11 la libera appena il disco in cloud l'ha caricata, con un giro ogni 2 minuti (D62) | Fatto, da provare su un disco in cloud vero; resta A8 per l'analisi |

**Criteri di accettazione.**
1. Su un Mac senza FotoTag né modelli, chi compila dal repository seguendo il README arriva alla prima foto analizzata senza aprire le Impostazioni (D56, D64).
2. Dopo l'accesso a una cartella, ogni sottocartella con foto compare nell'albero. Vale anche su una struttura inventata, senza anni né mesi nei nomi.
3. L'archivio di prova con il profilo Generico non produce tag che dipendano dai nomi di Lorenzo.
4. «Conferma tag» resta nello stesso punto dello schermo passando tra 20 foto con testi di lunghezza diversa.
5. Confermata l'ultima foto da rivedere, l'app propone «Scrivi nei file».
6. Da ogni comando di Foto nel menu parte la stessa azione del pulsante.
7. Dopo la scrittura su 20 JPG, un programma terzo legge le parole chiave e i dati compressi dell'immagine sono identici. Ogni file toccato ha la sua copia di sicurezza, anche con nomi uguali in cartelle diverse.
8. Un `.xmp` di darktable aggiornato conserva storia e valutazioni.
9. Spostando una cartella analizzata di 100 foto, dopo ⌘R analisi e tag sono ancora lì.
10. Una ricerca su 80.000 foto risponde in meno di 2 secondi dopo la prima.
11. Con 500 foto in analisi, un errore GPU lascia l'app aperta e nessuna foto persa.

### Dopo

Firma e notarizzazione, aggiornamenti, SigLIP dentro l'app, altre lingue, Swift 6 stretto, DigitalDarkroom. Voce di menu «Importa con FotoOrdina…» che apre l'app FotoOrdina (D57).

**Sfoglia** (D45-D47): modalità dell'app con campo di ricerca nella colonna e ricerche fissate, senza spostare nulla nel Finder. La pagina «In arrivo» di Riordina va tolta quando si fa.

## 12. Aperte e fonti

**Da verificare sull'app vera:** larghezze, modalità scura, allineamento delle icone dell'albero, schermate della tabella al §3.

**Limiti noti del modulo Cartelle:** disco rinominato: l'accesso resta sul vecchio nome e va ridato. Accesso a «/»: la radice non si apre nella griglia. Togliendo un accesso le sue foto spariscono dall'elenco ma restano nel database. Con nessun accesso la griglia mostra solo la domanda iniziale.

**Documenti da riallineare:** `README.md` descrive ancora «Aggiungi cartella…», il percorso `../fototag` e SigLIP da convertire a mano. `TODO.md` segna da fare il collegamento JPG → RAW, già fatto, e dà Riordina come «nel codice». `CLAUDE.md` dice Decisioni «da creare».

**Fonti.** Codice; `../note/2026-10-11_prova_uso_reale.md`, `2026-10-11_risposte_suite.md`, `2026-10-12_ergonomia_estetica.md`, `2026-10-12_specifica_interfaccia_A.md`, `2026-10-19_specifica_interfaccia_P2.md`, `2026-10-25_revisione_flusso.md`; revisione critica dell'11/10; [piano del progetto](https://claude.ai/code/artifact/0ad81a8b-d8f8-4ec5-b047-29c8db79c062); chat e thread del progetto.
