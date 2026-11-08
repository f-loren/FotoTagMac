# FotoTag: intenzioni e decisioni

Ricostruito a ritroso il 31/10/2026 (percorso C di `analisi-intenzioni`) da chat e thread del progetto, note in `../note/`, piano del progetto, memoria e codice al commit `7c31111` (build 88). Ogni decisione ha la sua fonte. In tabella sta solo ciò che Lorenzo ha scritto, scelto su una scheda o approvato: il resto è in «Aperte». La specifica è in [SPEC.md](SPEC.md).

## Idea di partenza

Le parole di Lorenzo, riordinate:

> Sono un fotografo analogico, le mie scansioni le ho organizzate per date nel mio pc. I file non hanno tag contestuali per poter fare una ricerca semantica. Vorrei creare una App che riconosca il contenuto delle immagini e scriva i corretti tag.

> Una app che ricerchi e che mi dia anche una preview del file ricercato, ovviamente bisognerà procedere ad un coding snello in funzione delle performance.

> Vorrei che si espandesse successivamente anche alle mie fotografie (editate) digitali, magari anche con un tag (analogica, digitale etc). [...] Anche da dare ad altri fotografi.

> Vorrei che questa app sia generica e non legata alle mie caratteristiche uniche e personali.

In una frase: un fotografo con migliaia di foto su disco oggi non le ritrova per contenuto, perché i file non hanno tag; FotoTag le guarda sul suo Mac, propone tag e didascalia, glieli fa controllare, li scrive nei file e gli permette di cercare a parole.

## Destinazione

Confermata da Lorenzo il 31/10 (D42). Lo stato attuale è la **v0.1**. La destinazione è la **v0.2, beta per 2-5 fotografi**: un altro fotografo installa FotoTag su un Mac pulito (dal 3/11 compilandola dal repository, senza DMG: D56, proposta da confermare) e arriva da solo a una ricerca e a una scrittura riuscite. Restano fuori la distribuzione pubblica (quando pubblicare il codice è da decidere), Sfoglia (D47) e l'integrazione con DigitalDarkroom.

## Decisioni

| n | data | tema | decisione | nota |
|---|---|---|---|---|
| 1 | 2026-10-05 | Obiettivo | Entrambe le cose: ritrovare le foto in pochi secondi con una ricerca a parole, con anteprima, e scrivere i tag dentro i file (IPTC/XMP). | Chat: «sarebbe possibile ottenere entrambi?», «esattamente!» |
| 2 | 2026-10-05 | Privacy | Conta la privacy più del modello specifico. Si lavora in locale, nessuna foto esce dal Mac; il cloud resta scartato. | Chat. Conferma: revisione critica 11/10, approvata |
| 3 | 2026-10-05 | Piattaforma | Mac. | Chat. Macchine: Mac mini M2 Pro e MacBook Air M4, 16 GB |
| 4 | 2026-10-05 | Scrittura | Prima si analizza, poi si rivede, solo dopo si scrive: nessun file cambia senza un via esplicito. | Scheda «Prima analizza» |
| 5 | 2026-10-05 | Destinatari | L'app è anche da dare ad altri fotografi, non solo per l'archivio di Lorenzo. | Thread Archivio: «anche da dare ad altri fotografi». Vedi 38 |
| 6 | 2026-10-05 | Ambito | Oltre alle scansioni, anche le foto digitali editate, con il tag analogica/digitale. | Thread Archivio |
| 7 | 2026-10-05 | Digitali | Si taggano i JPG editati e si recupera il RAW corrispondente. | Thread Archivio: «direi anche io jpg, magari [...] del raw corrispondente?» |
| 8 | 2026-10-05 | Pellicola | Serve anche il tag della pellicola, con una tabella sigla → nome da completare. | Thread Archivio. Tabella di base cambiata da 39 |
| 9 | 2026-10-05 | Importazione | Si importa da scheda creando la struttura al momento, a partire dai nuovi file; l'archivio vecchio non si riordina. Struttura `Foto/AAAA/AAAA-MM-GG soggetto/` con `RAW/` e `JPG/`, file rinominati `AAAAMMGG_NNNN`. | Thread Organizzazione. La struttura come regola per tutti è superata da 39 |
| 10 | 2026-10-05 | Importazione | La destinazione si sceglie a ogni importazione; la scheda non si tocca mai; il contesto è testo libero con suggerimenti dai nomi già usati. | Thread Organizzazione |
| 11 | 2026-10-05 | Importazione | Dati del rullino: pellicola, ISO di scatto, sviluppo (tipo, diluizione, minuti). Per il laboratorio: C-41, ECN-2 o non determinato. | Thread Organizzazione |
| 12 | 2026-10-05 | Importazione | Una sola struttura per foto personali e di lavoro; personale/lavoro e cliente sono tag. | Lorenzo: «consigliami tu», seguito il consiglio |
| 13 | 2026-10-05 | Architettura | App nativa per Mac (SwiftUI + MLX) e non il prototipo Python impacchettato. Qwen3-VL 8B di base, 4B per i Mac da 8 GB. | Chat: «mi va tutto bene». Prova su 52 foto |
| 14 | 2026-10-05 | Lingua | Tag in italiano per ora; altre lingue nelle prossime versioni. | Thread App da distribuire. Confermata per la beta da 43 |
| 15 | 2026-10-05 | Beta | Prima una beta per pochi fotografi conosciuti, senza firma Apple. | Piano del progetto, «deciso» |
| 16 | 2026-10-05 | Avvio | Una schermata d'inizio che chieda da dove iniziare, secondo gli scenari d'uso. | Superata da 33 |
| 17 | 2026-10-05 | Selezione | Si devono poter scegliere più foto, non solo una o tutte. | Thread App da distribuire. Col puntatore: ribadito il 12/10 |
| 18 | 2026-10-05 | Sidecar | Nome predefinito `DSC_1234.xmp` (Lightroom), con opzione darktable per chi la usa. | Lorenzo non usa né l'uno né l'altro: «altri fotografi sì, quindi va bene» |
| 19 | 2026-10-06 | Importazione | I gruppi si scelgono a mano dalle miniature, niente divisione automatica per pause. Le scansioni di pellicola sono RAW e si trattano come RAW. | Chat: «fammi scegliere i gruppi dalle miniature» |
| 20 | 2026-10-06 | Ricerca | Il modello SigLIP: prima su un repository Hugging Face pubblico, poi anche dentro l'app. | Chat. La prima parte è fatta |
| 21 | 2026-10-06 | Cartelle | Barra laterale come Photomator: Recenti richiudibili e albero delle directory. | Superata da 27 |
| 22 | 2026-10-06 | Licenze | Riconoscimenti e licenze di terzi dentro l'app, «tutti i diritti riservati» per la beta. | Chat. Bozza da far rivedere, vedi Aperta 7 |
| 23 | 2026-10-06 | Icona | Etichetta con diaframma, vettoriale. | Chat: «si mettila nell'app» |
| 24 | 2026-10-06 | Codice | Repository GitHub privato con la sola app. | Pubblicato da Lorenzo |
| 25 | 2026-10-11 | Direzione | Dopo la revisione critica: niente funzioni nuove finché non è chiuso l'elenco dell'11/10; perimetro della beta Tagga, Cerca, Scrivi nei file; Importa «sperimentale»; Riordina fuori dalla schermata d'inizio. | «ok mi piace il piano iniziamo». Blocco superato da 42 |
| 26 | 2026-10-12 | Build | Niente compilazioni né installazioni senza il via di Lorenzo. | Oggi l'uso è: Lorenzo chiude l'app e scrive «chiusa» |
| 27 | 2026-10-12 | Interfaccia | Direzione A «nativa rifinita», solo controlli di sistema; barra con il solo albero e il riquadro di avanzamento; File ▸ Apri recente con 5 cartelle. | Scelta delle 16:39. Supera 21. Dettaglio: `../note/2026-10-12_specifica_interfaccia_A.md`. Superata da 67 |
| 28 | 2026-10-12 | Revisione | «Conferma tag» al posto di «Rivista, vai alla prossima». Confermare non scrive: nei file si scrive solo con «Scrivi nei file». | Thread Revisione critica |
| 29 | 2026-10-19 | Metodo | Per l'interfaccia, prima i mockup, poi il codice. | Chat: «prima di scrivere codice fai dei mockup per farmi capire» |
| 30 | 2026-10-19 | Analisi | Prima la robustezza: una riprova dopo un errore GPU, tetto alla memoria MLX, controllo della memoria prima di partire. | Scheda |
| 31 | 2026-10-19 | Interfaccia | Seconda parte approvata: foto grande, Annulla, Cerca nella barra, Dock e notifica, suggerimenti di tag, anteprime per le foto in cloud. | «tutti». Dettaglio: `../note/2026-10-19_specifica_interfaccia_P2.md`. Fatta |
| 32 | 2026-10-25 | Metodo | Le revisioni dell'interfaccia sono poche proposte, senza ripetizioni, secondo le buone pratiche Apple e ordinate per flusso di lavoro. | Dopo le 9 proposte «troppo complesse e ridondanti» |
| 33 | 2026-10-25 | Cartelle | L'app chiede l'accesso una volta sola, poi le cartelle sono un unico albero. Spariscono «Aggiungi cartella…», il pannello con le regole e la schermata Inizio. | Supera 16 |
| 34 | 2026-10-25 | Interfaccia | La revisione per flusso (6 proposte) è la specifica del prossimo giro di codice, che parte al via di Lorenzo. | «approvo la modifica». `../note/2026-10-25_revisione_flusso.md`. Stato: solo la proposta 1 è fatta |
| 35 | 2026-10-26 | Tag fissi | L'origine è analogica o digitale, senza «non so». | Chat |
| 36 | 2026-10-31 | Indice | Dato l'accesso, l'app indicizza da sola tutto quello che trova. | Chat: «riscrivi quella parte di codice» |
| 37 | 2026-10-31 | RAW | I RAW senza JPG si vedono ma per ora non si analizzano né si taggano. | «per ora solo vedere». Codice predisposto, vedi Aperta 4 |
| 38 | 2026-10-31 | Generale | L'app è generica: regole solo su ciò che vale per tutti. Ciò che è di Lorenzo resta un profilo facoltativo, mai il comportamento di base. | Regola che vale su tutte le altre. Vedi 5 |
| 39 | 2026-10-31 | Generale | Cornici saltate, sigle delle pellicole e schema d'importazione passano nel Profilo Lorenzo; i testi dicono «disco in cloud». | Scheda «Sì, tutte». Supera 9 per la struttura di base |
| 40 | 2026-10-31 | Cartelle | Resta tutto visibile, anche ciò che non è foto: l'utente nasconde a mano le cartelle che non gli servono. | Scheda «Tutto, nascondo io». Formati ristretti da 48 |
| 41 | 2026-10-31 | Griglia | Si sceglie se vedere anche le sottocartelle (Vista ▸ Includi le sottocartelle), attivo di base; ogni cartella dell'albero si apre. | Chat |
| 42 | 2026-10-31 | Direzione | Il blocco dell'11/10 è chiuso. La prossima versione è la beta per 2-5 fotografi, con Tagga, Cerca e Scrivi, e Importa sperimentale. | «1 si». Supera 25 |
| 43 | 2026-10-31 | Lingua | Beta in italiano. | «2 italiano». Vedi 14 |
| 44 | 2026-10-31 | Profili | Una sezione nelle Impostazioni permette di personalizzare il profilo. | Scritta da Lorenzo come domanda: dettagli e mockup prima del codice (D29), Aperta 3 |
| 45 | 2026-10-31 | Riordino | Niente spostamenti né rinomine nel Finder: l'ordine su disco si decide solo all'importazione (D9, D10, D39). Il riordino è una modalità dell'app. | Thread sul riordino: «non serve spostare nel finder». Approvata alle 19:33 |
| 46 | 2026-10-31 | Sfoglia | Modalità «Sfoglia»: viste dinamiche su tag, didascalie, EXIF e dati del rullino. Nella colonna un campo di ricerca e le ricerche fissate dall'utente, nessun elenco di tag deciso dall'app. Una ricerca fissata si può rinominare, modificare, spostare ed eliminare; eliminarla non tocca foto né tag. Stelle, scelte, versioni ed esportazione restano fuori. | «ti direi 1 [...] poter pinnare quella ricerca», «può essere eliminata». Dettaglio e idee da PhotoPrism: `riordino/2026-10-31_riordino_per_tag.md` nei file del progetto. Mockup: https://claude.ai/artifact/VnZken1ou85hc4XQubpEjX |
| 47 | 2026-10-31 | Sfoglia | Si fa dopo la beta: fino alla v0.2 compresa resta fuori. | Proposta approvata con le righe del thread sul riordino, alle 19:33 |
| 48 | 2026-10-31 | Cartelle | Si dà accesso dalla directory più alta e si vedono solo RAW, HEIC, JPG e TIFF; i PNG sono fuori. | Chat delle 19:38. Modifica 40 per i formati. Nascondere resta a mano |
| 49 | 2026-10-31 | Cartelle | L'app non confronta le foto tra loro: le copie su un altro disco sono un backup, possono non essere collegate e restano foto a sé. | Chat delle 19:41. Si analizza solo dove si preme Analizza |
| 50 | 2026-10-31 | Cartelle | Nell'elenco un livello per riga, niente righe composte «A > B». | Chat delle 19:41 |
| 51 | 2026-10-31 | Profili | Le regole del profilo sono una per ogni accesso (cartella utente, disco, disco in cloud), nelle Impostazioni, mai sulle sottocartelle. | Chat delle 19:41. Precisa D44 |
| 52 | 2026-11-01 | Cartelle | La colonna delle cartelle è una lista piatta di righe rientrate, con i rami aperti tenuti nello stato dell'app, non rami annidati. | Terzo difetto di righe sovrapposte (schermata di Lorenzo del 1/11): rivista l'impostazione. Causa dedotta, non riprodotta |
| 54 | 2026-11-03 | Profili | Scheda Profili nelle Impostazioni al posto di Pellicole (variante A di `docs/mockup/profili.html`): i profili sono dati salvati sul Mac, Generico c'è sempre ed è modificabile, gli altri si creano, duplicano, rinominano, importano ed esportano come file. Ogni profilo ha le sue sigle delle pellicole. Una prova mostra i tag che un percorso dà con le regole scelte. Il Profilo Lorenzo esce dall'app: è il file `profili/esempio-pellicola.json`, dato di prova nel repo, importato sul suo Mac. | «ok mi piace» sul mockup, che conteneva le tre proposte. Chiude Aperta 3, supera 39 dove metteva le regole di Lorenzo dentro l'app |
| 55 | 2026-11-03 | Perimetro | Il riordino esce da FotoTag: l'app si occupa solo di tag (analisi, revisione, ricerca, scrittura nei file). | Chat del 3/11 alle 15:55. Supera 45 dove faceva del riordino una modalità dell'app. Da decidere se togliere il codice nascosto di Riordina. Importa da scheda: vedi 57 |
| 56 | 2026-11-03 | Distribuzione | FotoTag si pubblica online come codice aperto: non serve un DMG. | Chat del 3/11 alle 15:55. Repository pubblico e push solo con il sì di Lorenzo; licenza ancora aperta (Aperta 7) |
| 57 | 2026-11-03 | Perimetro | «Importa da scheda» esce da FotoTag e vivrà solo nella nuova app FotoOrdina. In futuro FotoTag avrà una voce di menu «Importa con FotoOrdina…». | Risposta «1. a» di Lorenzo nel thread sull'app di riordino, 3/11 alle 16:23. Chiude ciò che 55 lasciava aperto su Importa. Il codice di Importa si toglie solo col sì di Lorenzo |
| 58 | 2026-11-03 | Licenza | FotoTag (e FotoOrdina) è codice aperto con licenza GPL 3.0. | «si confermo GPL3», 3/11 alle 16:29, nel thread sull'app di riordino. Chiude Aperta 7. I componenti Apache 2.0 e MIT si possono usare in un'opera GPL 3.0. Il 4/11 («adesso»): `LICENSE.md` in italiano, testo completo in `COPYING`, copyright dell'app aggiornato. Versione 3 soltanto, non «o successive» |
| 59 | 2026-11-04 | Scrittura | Una didascalia diversa già nel file non si sovrascrive, tranne quelle che la fotocamera mette da sola («SONY DSC», «OLYMPUS DIGITAL CAMERA»…): contano come vuote e FotoTag scrive la sua. | Lorenzo ha approvato le correzioni della prova sul MacBook Air (punto 6), thread «Aggiungere i profili nelle Impostazioni». Conferma la seconda regola di Aperta 9 con questa eccezione. Elenco in `Scrittura.segnaposti` |
| 60 | 2026-11-08 | Perimetro | Il codice nascosto di Riordina e di Importa da scheda esce da FotoTag. | «1. a», thread «Liberare spazio occupato da FotoTag». Chiude ciò che 55 e 57 lasciavano al sì di Lorenzo |
| 61 | 2026-11-08 | Copie di sicurezza | Le copie di sicurezza si tengono 5 giorni, poi si eliminano da sole. Si possono disattivare nelle Impostazioni (accese di base, come oggi). | «facciamo ultimi 5gg e soprattutto deve essere disattivabile nelle impostazioni». Chiude la terza regola di Aperta 9 |
| 62 | 2026-11-08 | Disco in cloud | Le foto riportate sul Mac per scriverci si liberano da sole appena il disco in cloud le dà per caricate, con un controllo periodico. | «3. a». Chiude Aperta 8 per la scrittura; resta il caso della foto scaricata dopo i 30 secondi dell'analisi |
| 63 | 2026-11-08 | RAW | I RAW non si analizzano mai: prendono i tag solo dal JPG collegato. Un RAW senza JPG resta da vedere. | «francamente non li analizzerei mai». Chiude Aperta 4, conferma 37 senza il «per ora». Lorenzo chiede un collegamento che regga anche se il JPG cambia nome: proposta in Aperte |
| 64 | 2026-11-08 | Distribuzione | Niente DMG: chi vuole FotoTag lo compila dal repository seguendo il README. | «si» alla domanda 6. Conferma 56, punto 8 e criterio 1 della SPEC non sono più proposte |
| 65 | 2026-11-08 | Ricerca | L'indice di ricerca si prepara da solo dopo l'indice delle cartelle e dopo il download del modello di ricerca, partendo dalla cartella aperta. Va in pausa durante l'analisi e quando il Mac è a batteria. Un'impostazione permette «Solo quando cerco». Le foto solo in cloud non si scaricano mai in sottofondo: entrano con un comando esplicito, con conferma, che le scarica una alla volta e le libera. | Scheda dell'8/11 nel thread «Valutare le strategie dell'indice di ricerca», valutazione https://claude.ai/artifact/9WAtRo7cBNHbNEMY4461wC. Chiude Aperta 6. Estende D36 all'indice di ricerca. Prima o insieme: query con voci in memoria fuori dal thread principale (criterio 10), niente ricerca ripetuta ogni 10 foto, errori non contati come fatti, avvio dopo il download, pulsante Ferma, SigLIP liberato a fine lavoro |
| 66 | 2026-11-08 | RAW | Il collegamento JPG → RAW usa l'impronta dello scatto dall'EXIF (fotocamera, numero di serie, data al centesimo, numero dello scatto), così regge un cambio di nome. Lorenzo accetta che leggere l'EXIF di un RAW in cloud possa scaricarlo (25-60 MB). | «proposta», poi «eh lo accettiamo» sul costo del BeeStation. Per non contraddire D36 e D65, proposta da confermare: i RAW in cloud si leggono con lo stesso comando esplicito di D65, uno alla volta, e si liberano subito. Prima del codice: provare se la lettura dell'EXIF scarica davvero il file intero. 8/11 alle 10:34 Lorenzo conferma («ok») le scelte del codice: impronta = modello, data e centesimi, senza numero di serie (ImageIO non lo legge dal NEF della D200); senza centesimi niente impronta, si torna al nome; dopo «Includi…» si ricollegano solo le foto della cartella aperta |
| 67 | 2026-11-08 | Interfaccia | Poche animazioni proprie ammesse, solo per riscontro, stato o continuità: valori in un solo file `Movimento.swift` (rapida, standard, giroScanner), mai sulle azioni da tastiera ripetute (↩, frecce, spazio), Riduci movimento rispettato, nessuna libreria. Sulla foto in analisi passa la linea dello scanner. | Scheda «Sì, con la linea dello scanner», 8/11 alle 10:27, e «la decisione 27 è superata» alle 10:41, thread «Valutare come abbellire l'interfaccia». Supera 27. Proposte e regole: https://claude.ai/artifact/TQPac2B8V2GwJVd2xjdMR1 |
| 68 | 2026-11-08 | Lingua | FotoTag in inglese prima della pubblicazione: l'interfaccia segue la lingua di macOS (inglese su un Mac in inglese, italiano su un Mac in italiano). | «ok» alle 12:23 alle tre proposte del thread «Completare FotoTag per la pubblicazione»; scelta della traduzione alle 11:08 nel thread «Preparare la pagina GitHub di FotoTag». Oggi circa 270 testi in 21 file, senza String Catalog |
| 69 | 2026-11-08 | Lingua | La lingua dei tag resta un'impostazione separata dall'interfaccia (Impostazioni ▸ Lingua dei tag), con l'inglese accanto all'italiano. | «ok» alle 12:23. La lingua dei tag è già isolata in `FotoTagCore/Lingua.swift`, oggi solo `.italiano` |
| 70 | 2026-11-08 | Lingua | Dei profili si traducono solo nome e descrizione dei profili predefiniti; le sigle delle pellicole restano uguali (Portra 400 resta Portra 400); i profili dell'utente non si toccano. | «ok» alle 12:23 |

## Aperte

Proposte fatte al posto di Lorenzo, da confermare o da decidere.

1. Chiusa da D42.
2. Chiusa da D43 per la beta. Dopo la beta resta da decidere, perché tira contro la regola 38.
3. Chiusa da D54.
4. Chiusa da D63 e D66. Testo di partenza: **RAW senza JPG.** Sono circa 13.500 file nell'archivio di Lorenzo. Opzioni: restano solo da vedere nella beta (proposta); si analizzano dall'anteprima incorporata e i tag vanno nel `.xmp`.
5. **Primo avvio.** Senza modello, Analizza si ferma su un messaggio. Un amico di Lorenzo ha riferito che una vecchia versione «non scaricava il modello», causa mai accertata. Il DMG non è mai stato provato su un Mac pulito.
6. Chiusa da D65. Testo di partenza: **Ricerca senza il modello grande.** La revisione critica propone di indicizzare subito con SigLIP e taggare dopo. Non è mai stata decisa. La ricerca funziona già senza tag. Dal 31/10 calcola gli embedding delle foto sul Mac e, per quelle in cloud, solo dall'anteprima salvata, senza scaricare: una foto in cloud mai analizzata non si trova finché non la si analizza (proposta fatta correggendo il bug, da confermare). Va deciso anche quando calcolarli su decine di migliaia di foto.
7. Chiusa da D58 (GPL 3.0).
8. Per la scrittura chiusa da D62. Resta: **foto scaricata dopo i 30 secondi dell'analisi.** Testo di partenza: **Foto scritte sul disco in cloud.** Per scrivere si riportano sul Mac e dopo ci restano, perché toglierle subito fallisce finché non sono caricate. Scrivendo migliaia di foto lo spazio si riempie: va scelto quando liberarle. Stesso rischio per una foto il cui download arriva dopo i 30 secondi di attesa dell'analisi.
9. **Regole implicite nel codice, da confermare:**
   - i tag dei RAW collegati finiscono nel sidecar solo se il collegamento è «sicuro» o scelto a mano;
   - una didascalia diversa già nel file non viene sovrascritta: confermata da D59, che toglie i segnaposto della fotocamera;
   - chiusa da D61 (5 giorni, disattivabile): la copia di sicurezza è accesa di base, tiene il percorso intero del file e cresce in Application Support senza limite né pulizia;
   - le foto in errore si rianalizzano insieme a quelle nuove;
   - «Rianalizza» tiene i tag aggiunti a mano e chiede una proposta diversa;
   - un RAW con un JPG dello stesso nome nella stessa cartella conta come una sola foto.
10. **Soglia della ricerca.** Dal 4/11 una foto esce se SigLIP le dà almeno l'1% (il prototipo usava il 2%) o se ha metà delle parole cercate fra tag e didascalia. Prova: con «ritratto» tre ritratti evidenti avevano 10%, 1,25% e 1,22%, e il 2% ne trovava uno. Più risultati deboli in fondo all'elenco: da rivedere sull'archivio vero.

## Nebbia

- Integrazione con DigitalDarkroom: app separata che scrive XMP, oppure motore chiamato dalla Suite. Dipende dalla licenza e da cosa quella app leggerà.
- Modelli diversi da Qwen, compresa la prova di Gemma 3 4B e l'uso di Ollama o LM Studio già installati.
- Tag scritti solo come sidecar anche per i JPG, per chi non vuole che l'app li tocchi.
- Sandbox: se arriverà, il modello degli accessi va rivisto.
- Isolare l'analisi in un processo separato, per contenere gli errori della GPU.
- Cosa succede ai tag se un file taggato viene poi riesportato da un altro programma: verificato solo che Photomator non li mostra nel pannello Info.

## Fuori perimetro

- Cloud per l'analisi: le foto non escono dal Mac (decisione 2).
- Mac App Store.
- Altri sistemi operativi.
- Fino alla v0.2 compresa: Sfoglia, firma e notarizzazione, aggiornamenti automatici, distribuzione pubblica.
- Spostare o rinominare file nel Finder dopo l'importazione (D45), compreso riorganizzare l'archivio esistente di un utente.
- Il riordino in ogni forma, anche come modalità dell'app (D55).
