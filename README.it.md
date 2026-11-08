# FotoTag

[English](README.md) · **Italiano**

**Tag e didascalie automatici per il tuo archivio fotografico, generati interamente sul tuo Mac.**

FotoTag guarda le tue foto e propone per ognuna dei tag e una breve didascalia. Tu controlli le proposte, e FotoTag scrive quelle che approvi nei file delle immagini, o nel file `.xmp` accanto ai RAW. Da lì puoi ritrovare qualsiasi foto descrivendola: «bambini al mare», «nebbia in collina», «bicicletta sotto la pioggia».

È pensata per fotografi con archivi grandi, anche di scansioni di pellicola, su un disco esterno, un NAS o una cartella in cloud. Non si carica niente in rete: i modelli di intelligenza artificiale girano sul chip Apple del Mac.

![Revisione dei tag e della didascalia proposti per una foto](docs/immagini/review.png)

| Ricerca a parole | I profili trasformano i nomi delle cartelle in tag |
|---|---|
| ![Ricerca «fog on the hills»](docs/immagini/search.png) | ![Prova di un profilo su un percorso](docs/immagini/profiles.png) |

## Cosa fa

- **Riservata per costruzione.** Un modello visione-linguaggio (Qwen3-VL, eseguito con [MLX](https://github.com/ml-explore/mlx-swift)) analizza le foto sul tuo Mac. Nessun servizio in cloud, nessun account, nessun abbonamento.
- **Decidi tu.** Non viene scritto niente finché non approvi.
- **Scritture sicure.** I metadati si aggiungono senza ricomprimere l'immagine, e FotoTag tiene una copia di sicurezza di ogni file che modifica. I RAW non vengono mai toccati: i loro tag vanno nel file `.xmp` accanto.
- **Ricerca a parole.** Un secondo modello (SigLIP 2) permette di cercare descrivendo la foto, anche fra quelle non ancora taggate.
- **Capisce come organizzi l'archivio.** I profili leggono la struttura delle cartelle (anno/mese/rullino, nomi di cartella da tenere come tag, sigle delle pellicole come «hp5» → «Ilford HP5 Plus 400»).
- **Italiano o inglese.** L'interfaccia segue la lingua del Mac, e i tag si possono scrivere in tutte e due le lingue.

## Cosa serve

- Un Mac con chip Apple (M1 o successivi) e macOS 14 Sonoma o successivo
- 16 GB di memoria per il modello normale (Qwen3-VL 8B, 5,8 GB da scaricare). Sui Mac con meno memoria FotoTag propone un modello più piccolo, il 4B (3,1 GB, almeno 8 GB di memoria): circa due volte più veloce, ma meno preciso.
- Circa 20 GB liberi sul disco: 5 GB per la compilazione, 5,8 GB per il modello di analisi (3,1 per quello piccolo), 1,5 GB per il modello di ricerca, più le anteprime. Prima di scaricare un modello FotoTag controlla che dopo restino almeno 2 GB liberi.
- Xcode 26 o successivo (gratuito sul Mac App Store)

## Installare

FotoTag non si distribuisce come app già pronta: si compila dal codice con un solo comando, in qualche minuto. L'app non è firmata con un certificato Apple Developer, e compilarla da te evita anche gli avvisi di macOS sugli «sviluppatori non identificati».

1. Installa Xcode e aprilo una volta, così finisce la configurazione.
2. Installa il Metal Toolchain, che Xcode non include di serie:
   ```
   xcodebuild -downloadComponent MetalToolchain
   ```
3. Scarica il repository e compila:
   ```
   git clone https://github.com/f-loren/FotoTagMac.git
   cd FotoTagMac
   ./crea_app.sh
   ```
   Lo script compila FotoTag, la copia in Applicazioni e la apre. I file della compilazione vanno in `../_build`, accanto al repository; con `FOTOTAG_BUILD=/un/percorso` li metti altrove.

Per aggiornare: `git pull` e di nuovo `./crea_app.sh`. Se FotoTag è aperta, lo script la chiude prima, e un'analisi in corso si ferma.

## Primi passi

1. **Dai a FotoTag l'accesso alle foto.** Scegli la cartella o il disco che le contiene. FotoTag elenca tutte le sottocartelle con foto (RAW, HEIC, JPEG, TIFF). Analizza JPEG, HEIC e TIFF. I RAW non si analizzano direttamente: quando FotoTag riesce ad abbinare con sicurezza un RAW al JPEG dello stesso scatto (o lo abbini tu), il file `.xmp` del RAW riceve i tag del JPEG.
2. **Consenti l'accesso** a Scrivania, Documenti o Download se macOS lo chiede. Poiché l'app non è firmata, macOS lo richiede dopo ogni compilazione.
3. **Scegli la lingua dei tag.** Di serie è l'italiano; per l'inglese vai in Impostazioni ▸ Generali ▸ Lingua dei tag.
4. **Analizza una cartella.** Premi **Analizza**. La prima volta FotoTag propone di scaricare il modello adatto al tuo Mac (una volta sola, da Hugging Face). Con il modello normale servono circa 8-10 secondi a foto.
5. **Controlla e scrivi.** Rivedi le proposte in **Da rivedere**, approvale e premi **Scrivi nei file** quando vuoi. Le copie di sicurezza restano 5 giorni; si possono spegnere in Impostazioni ▸ Generali.
6. **Cerca.** Alla prima ricerca FotoTag propone di scaricare il modello di ricerca (SigLIP 2, 0,75 GB).

## Profili

Un profilo dice a FotoTag come leggere i nomi delle tue cartelle: se il nome di una cartella diventa un tag, se le cartelle seguono una struttura anno/mese/rullino, quali nomi ignorare («export», «jpg»…), quali indicano una scansione di pellicola e come sciogliere le sigle delle pellicole. Assegni un profilo a ogni disco o cartella in Impostazioni ▸ Generali e lo modifichi in Impostazioni ▸ Profili, dove puoi incollare un percorso e vedere i tag che ne escono.

Il profilo **Generico** va bene per cominciare. I profili si scambiano come file JSON (Importa ed Esporta nel menu «…» del profilo); `profili/esempio-pellicola.json` è un esempio per un archivio di pellicola diviso per anno, mese e rullino.

## Privacy e dati

- Le tue foto non lasciano mai il Mac. L'unico accesso alla rete serve a scaricare i modelli da Hugging Face.
- Tutto ciò che FotoTag salva (database, profili, modelli, anteprime, copie di sicurezza e un registro) sta in `~/Library/Application Support/FotoTag/`.
- Le foto restano dove sono. FotoTag le modifica solo quando premi **Scrivi nei file** e confermi.

## Domande frequenti

**Perché non c'è un file da scaricare?** Distribuire un'app già compilata che macOS apra senza avvisi richiede un account Apple Developer a pagamento. Compilare dal codice è gratuito e dà esattamente la stessa app.

**In che lingue funziona?** Italiano e inglese, sia l'interfaccia sia i tag. L'interfaccia segue la lingua del Mac; su un Mac in un'altra lingua, senza l'inglese fra le lingue preferite, appare in italiano. Le foto già analizzate tengono i tag nella lingua di prima finché non le rianalizzi.

**Funziona con Lightroom, Photomator o darktable?** FotoTag scrive i tag nei campi XMP standard (`dc:subject`, più le parole chiave gerarchiche di Lightroom) e la didascalia in XMP e IPTC. Per i RAW puoi scegliere il nome del file `.xmp` usato da Lightroom (`DSC_1234.xmp`, quello di serie) o da darktable (`DSC_1234.NEF.xmp`). Quando aggiorna un `.xmp` esistente, FotoTag cambia solo tag e didascalia; tutto il resto, compresa la storia delle modifiche di darktable, resta identico. Sono campi standard che Lightroom, Photomator e darktable leggono, ma FotoTag non è ancora stato provato in ognuno. Se lo usi con uno di questi programmi, apri una issue e raccontaci com'è andata.

**Funziona sui Mac Intel?** No: MLX richiede un chip Apple.

## Contribuire

Segnalazioni e idee sono benvenute: leggi [CONTRIBUTING.md](CONTRIBUTING.md). Per segnalare un problema di sicurezza vedi [SECURITY.md](SECURITY.md).

Per chi sviluppa:
- `Sources/FotoTagCore`: analisi (MLX), database, tag fissi e profili, scrittura dei metadati, ricerca. `Sources/FotoTag`: l'app SwiftUI. `Sources/fototag-cli`: strumenti di prova da riga di comando.
- Prove: `swift test --scratch-path ../_build/spm` (serve il Metal Toolchain).
- Cosa deve fare l'app e perché: [docs/SPEC.md](docs/SPEC.md) e il registro delle decisioni in [docs/INTENZIONI.md](docs/INTENZIONI.md).

## Licenza

FotoTag è software libero, distribuito con la GNU General Public License versione 3: vedi [LICENSE.md](LICENSE.md) e il testo completo in [COPYING](COPYING).

I modelli non sono nel repository: FotoTag li scarica da Hugging Face. Qwen3-VL (Alibaba Cloud) e SigLIP 2 (Google) hanno entrambi licenza Apache 2.0. Librerie e modelli di terzi sono elencati in [Risorse/RICONOSCIMENTI.md](Risorse/RICONOSCIMENTI.md).

Le foto delle schermate sono immagini in pubblico dominio o CC0 da Wikimedia Commons: vedi [docs/immagini/CREDITS.md](docs/immagini/CREDITS.md).
