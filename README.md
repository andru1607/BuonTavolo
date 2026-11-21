# GoodDiner 1.0 · Accesso reale (rilascio controllato)

**Accesso controllato:** le nuove registrazioni sono disabilitate nel browser e, dopo l'applicazione della [migrazione del gate Auth](database/gooddiner_registration_gate.sql), anche direttamente nel database, finché non sono configurati il CAPTCHA server-side, email e privacy. La home resta consultabile e l'accesso agli account esistenti non è rimosso. [Checklist go-live](docs/go-live-acceptance.md).

**La home principale `/` non è più una demo.** Profili, DinerPass e storico consultano il database Supabase GoodDiner dedicato `ixczkhmvbjszgmlqznlk`; nessun utente, visita o recensione viene inventato. La vecchia demo è mantenuta in [demo.html](demo.html) solo per test. Il vecchio `account.html` è disabilitato.

**Non è ancora il lancio pubblico:** i test automatici e la verifica dei privilegi non sostituiscono le prove fra account reali su iPhone. Restano da completare configurazione Auth/email, URL pubblico canonico, protezione anti-bot, approvazione documentale dei locali, operatore effettivo per la moderazione e documentazione GDPR. Nessun locale è approvato automaticamente. [Registro di rilascio aggiornato](https://github.com/andru1607/BuonTavolo/issues/10).

**Sicurezza iscrizioni:** la [procedura per aprire e richiudere le registrazioni](docs/registration-gate.md) richiede una decisione amministrativa documentata. Il controllo nel frontend da solo non è una misura anti-bot.

**Diritti degli utenti:** il Profilo offre un archivio JSON personale e un modulo per le richieste di accesso, rettifica, cancellazione, limitazione e opposizione, con esame umano e audit. Il modulo non sostituisce un contatto privacy esterno né una valida informativa, ancora da completare. [Procedure privacy](docs/privacy-operations.md).

Leggi [le note ufficiali di rilascio](docs/official-release-v1.md) e [il database](database/README.md).

---

# GoodDiner · Database Supabase dedicato installato

Il progetto Supabase **GoodDiner** (`ixczkhmvbjszgmlqznlk`) è attivo in `andru1607's Org` nella regione `eu-central-1`. Sono state applicate [la migrazione iniziale](database/gooddiner_initial.sql), [l'ottimizzazione RLS/indici](database/gooddiner_policy_performance.sql) e [la migrazione di moderazione riservata](database/gooddiner_operator_moderation.sql). Il database contiene 7 tabelle applicative con RLS e 3 tabelle private con RLS; alla verifica del 21 novembre erano prive di utenti e operazioni reali. La home 1.0 usa Supabase. [Procedure operatori](docs/operator-moderation.md). Per provare i flussi con dati inventati nel browser, apri [la demo locale](demo.html). Consulta lo [stato delle verifiche prima del lancio](database/README.md). Non usare o modificare il database easygart.

---

# GoodDiner V7.10 · Storico e registro presenze

## Cosa è cambiato
- **Cliente:** storico delle presenze nella home e nel profilo, riferito soltanto al codice cliente attivo. Mostra nome del locale, momento del check-in e stato. La demo non scambia dati tra telefoni.
- **Ristoratore:** registro presenze nella home, con riepiloghi Oggi / ultimi 7 giorni / Totale, filtri temporali, ricerca per nickname/ID e scheda dettagliata.
- **Correzioni:** il ristoratore può annullare una scansione locale errata. La presenza non viene cancellata dal registro: resta con stato `annullata` e `voidedAt`. Una visita annullata non blocca un nuovo check-in valido nello stesso locale e giorno.
- **Luogo corretto:** il check-in registra il nome del locale scelto nell'onboarding demo, invece di usare sempre “La Quercia”. Duplicati valutati per cliente + locale + giorno; i registri non mostrano presenze di locali con nome differente.
- **Feedback immediato:** nell'area ristoratore appare una ricevuta discreta quando una presenza è stata registrata da meno di due minuti.
- **Accessibilità:** focus e pulsanti nel dettaglio, supporto Escape, dimensioni minime dei controlli e `prefers-reduced-motion`. Nessuna nuova voce nella navigazione.

## Limiti
Sono solo **registrazioni simulate nel localStorage dello stesso browser**. La verifica del ristorante, la lettura QR fra dispositivi, l'identità personale e un registro attendibile richiedono autenticazione reale e backend autorizzato. Il nome del locale e lo storico locale non costituiscono prove di presenza reale. Non usare dati di persone vere nella demo.

Rimangono invariati logo GD, personalizzazione V7.9, accesso unico, valutazioni positive solo **8–10/10** e premio ogni dieci positive. Nessun servizio esterno o database attivato.

## Test
- Suite V7.10: ordinamento, visibilità per cliente/locale, conteggi, duplicati, annullamento tracciato, sicurezza dei dati locali e integrazione delle schermate attraverso VM.
- Suite storiche invariate salvo il controllo della nuova cache service worker.
- Il browser automatizzato disponibile nell'ambiente ha bloccato l'apertura di pagine locali (`ERR_BLOCKED_BY_ADMINISTRATOR`): non dichiarare un test visuale completo. Restano da verificare manualmente comportamento touch, scansione su iOS/Android e layout su dispositivi fisici.

---

# GoodDiner V7.9 · Studio di personalizzazione

La personalizzazione visiva ora è interattiva nella demo: il **cliente** può selezionare tre finiture del proprio DinerPass (con anteprima e selezione distinta per codice cliente); il **ristoratore** può selezionare tre accenti per la scheda locale, mantenendo esclusivamente logo e foto caricati dal gestore. Tutti possono scegliere fra tre temi dell'interfaccia e densità Aria/Compatta, senza aggiungere nuove voci alla navigazione.

**Dove:** Cliente → Profilo → Studio DinerPass; Ristoratore → Gestione → Studio locale. Entrambe le home offrono una scorciatoia. Si applicano subito e restano salvate nel browser, con possibilità di ripristinare la configurazione originale. L'anteprima del locale riprende il nome inserito nell'onboarding e il suo eventuale logo.

**Privacy:** le sole preferenze sono nel localStorage `gooddiner-demo-appearance-v79`. La personalizzazione non cambia ID, recensioni, voto, premi, QR o stato di verifica. Backend/autenticazione reali restano disattivati; nessuna immagine stock. Rispetta `prefers-reduced-motion`.

**Collaudo:** 12 suite `npm test` superate. Rendering e interazione browser verificati a 320, 375, 390, 430, 740, 1024 e 1280 px: nessuno scorrimento orizzontale o errore JavaScript; scelte persistenti anche dopo riapertura, ripristino e gestione dei due ruoli. Test fisici su iOS/Android ancora da effettuare.

---

# GoodDiner V7.8 · Zoom corretto e transizioni più fluide

- **Zoom involontario su iPhone:** campi di registrazione, scanner, area demo e account predisposto con caratteri di almeno 16 px, senza bloccare lo zoom manuale dell'utente.
- **Schermi adattivi:** titoli responsivi, contenuti lunghi spezzati, QR nel DinerPass senza debordamenti, modali compatibili con safe area e schermi corti.
- **Transizioni:** ingresso/registrazione con piccolo movimento verticale e dissolvenza, navigazione con View Transitions e fallback, scanner con entrata/uscita animata, tasti e dock più fluidi; niente zoom o ingrandimenti decorativi.
- **Scanner:** quando si apre, focus sul pulsante di chiusura anziché sul campo manuale, per non aprire la tastiera subito; tasto Esc per chiudere.
- **Accessibilità:** mantiene il pinch-to-zoom, non imposta `maximum-scale`, rispetta `prefers-reduced-motion`.
- **Verifiche:** 11 suite `npm test` superate; browser Chromium a 320, 375, 390, 430, 740, 1024, 1280 px senza scorrimento orizzontale, input >=16px, scanner chiudibile e nessun errore JS nei flussi controllati. Test sui dispositivi fisici ancora da completare.
- **Nessun backend attivato:** logica demo locale, 8–10/10 positivi e voucher ogni dieci positive rimangono invariati.

---

# GoodDiner V7.7 · Petrolio e corallo

La versione V7.7 applica una nuova palette vivace ma raffinata a tutte le aree della demo, mantenendo il logo GD, i flussi e i dati.

**Palette:** petrolio `#0F3D3E` per navigazione e DinerPass, corallo `#E06B4F` per il pulsante iniziale con testo scuro e dettagli, corallo accessibile `#C45337` per pulsanti con testo bianco, crema `#F7F1E8` per le superfici, grafite `#1E2423` per i testi e oro sabbia `#C9A86A` per riconoscimenti.

Il tema è isolato in `theme-v77.css` e include la schermata Accedi/Crea account, intestazioni, sidebar, navigazione mobile, manifesto del cliente, tessera reputazionale, scanner, QR DinerPass e area account predisposta. Nessuna fotografia stock aggiunta. `manifest.webmanifest`, meta theme-color e service worker aggiornati per distribuire la palette anche come web app installata.

**QA:** dieci suite con `npm test`; controlli di contrasto delle CTA e rendering browser su iPhone, schermi piccoli, pieghevoli e desktop. Le recensioni positive restano esclusivamente i voti 8–10/10, premio ogni 10 positive. **Backend e autenticazione reale rimangono disattivati.**

---

# GoodDiner V7.6 · Ingresso unificato e DinerPass QR

## Nuovo funzionamento della demo

- All’apertura non si domanda se l’utente sia cliente o ristoratore: mostra **Accedi**, **Crea un account** e **Esplora la demo**. La scelta del percorso avviene solo durante la creazione dell’account.
- Il cliente sceglie soltanto un **nickname obbligatorio**. Email e telefono sono facoltativi e **non vengono salvati** in questa demo. Viene generato un codice `GD-…` locale.
- Il DinerPass mostra un **QR vero, leggibile da lettori standard**, contenente soltanto un token dimostrativo temporaneo (90 secondi), senza nickname, email o telefono.
- Nella home ristoratore è stato inserito **Scansiona DinerPass**: usa la fotocamera se il browser supporta `BarcodeDetector` oppure l’inserimento manuale del codice. Se cliente e ristoratore condividono lo stesso browser e la stessa demo, il token valido e non già usato registra una **presenza simulata**, impedendo duplicati nello stesso giorno.
- Il ristoratore può inserire nome e città e aprire una ricerca pubblica su Google Maps. **Non esiste alcuna API attiva o verifica automatica della proprietà**. Il profilo creato resta una *anteprima*, con stato di verifica non attivo.
- Le sessioni e le presenze della demo sono salvate esclusivamente nel browser locale, non tra telefoni. Non c’è login reale, sincronizzazione, servizio SMS/email o associazione server-side fra QR e visita. Non inserire dati personali veri.
- Login reale con passkey/codice di recupero, ricerca automatizzata Places e verifica di gestione, QR firmati server-side e sincronizzazione presenze richiedono backend dedicato, RLS e verifiche privacy prima della produzione.
- Licenze: l’encoder QR `qr-core.js` deriva da *QRCode for JavaScript* di Kazuhiko Arase (MIT), distribuito nel pacchetto `qrcode-terminal` (Apache 2.0). Test di decodifica QR tramite OpenCV superato.
- Nessun cambiamento a valutazioni positive **8–10 / 10** o buono demo ogni **10** recensioni positive.

## Avvio e test

Esegui `npm test` dalla cartella del progetto. Per verificare la registrazione presenza usa **Crea account** > **Profilo personale**, copia il codice QR demo e passa alla *vista ristoratore demo*, dove puoi usare **Scansiona DinerPass** > Inserimento manuale. Da telefoni diversi non è possibile senza un backend reale.

---

# GoodDiner V7.5 · Simbolo GD definitivo (demo)

Il logo temporaneo è stato sostituito dal simbolo scelto dall'utente: **due forme GD intrecciate e una stella a quattro punte**. La grafica nasce dalla terza proposta confermata e viene ridisegnata in SVG vettoriale a colori piatti, senza sfumature, posate, piatti o emoji.

- `icons/mark.svg`: marchio trasparente verde/oro, per superfici avorio.
- `icons/mark-light.svg`: marchio trasparente avorio/oro, per superfici verde scuro.
- `icons/icon.svg` e `icons/icon-180.png`, `icons/icon-192.png`, `icons/icon-512.png`: icone app/PWA coerenti con il nuovo simbolo.
- Monogramma mostrato anche nella sidebar, nell'intestazione mobile e nell'onboarding; Apple Touch Icon usa PNG 180px.
- Service worker cache incrementata per evitare vecchie icone offline.
- Test aggiunto per vettoriale, marchio, dimensioni e requisiti demo invariati.

**Stato: soltanto demo**; nessun database attivo, autenticazione reale o raccolta di dati personali. Il marchio GoodDiner non è stato certificato libero da conflitti legali.

# GoodDiner V7.4 · Nuova identità

**Nome scelto:** GoodDiner. **Stato:** demo frontend; nessun database o autenticazione reale. **Verifica legale:** il nome non è ancora stato definitivamente liberato da un controllo professionale sui marchi; non presentarlo come registrato o esclusivo.

## Cosa cambia

- Nome e testi aggiornati in home cliente, area ristoratore, onboarding, account, manifest PWA e schermate premi.
- Logo vettoriale provvisorio **GD**, minimal, senza posate, piatti o emoji; icone PWA 180/192/512 rigenerate.
- Funzioni riconoscibili: **DinerPass** (tessera), **DinerBadge** (riconoscimenti), **DinerRewards** (premi), con identità del cliente al centro.
- Nessuna emoji o stella testuale nei flussi UI: valutazioni e simboli sono resi con SVG; la scala resta da 1 a 10.
- Nuovi buoni demo con prefisso `GD-`; i buoni `BT-` già presenti nella memoria locale restano leggibili e riscattabili.
- Le chiavi di `localStorage` precedenti restano volutamente immutate per preservare dati, fotografie e preferenze demo esistenti.
- La bozza SQL non è stata eseguita né collegata. I nomi tecnici `bt_*` rimangono come identificatori storici nel file di schema, che dovrà essere revisionato prima di un backend reale.
- Il repository GitHub resta temporaneamente `andru1607/BuonTavolo` per non rompere il deploy automatico Vercel esistente.
- Il rebranding non cambia il funzionamento: **positive solo recensioni 8–10/10**, un buono demo ogni 10 positive.



- **Tessera reputazionale a due facce:** vista principale e retro con ID, media e conteggio delle recensioni positive. Pulsante "Girala" accessibile e animazione breve; su mouse è presente un riflesso che segue il puntatore (non obbligatorio sui touch). La preferenza Riduci movimento disabilita tutte le animazioni decorative.
- **Navigazione inferiore:** dock con icona attiva evidenziata e feedback al tocco, mantenendo solo quattro voci per ruolo e le aree sicure di iOS/Android.
- **Timbri collezionabili:** disegno a sigillo e animazione soltanto per l'ultimo timbro. Un effetto breve annuncia il buono demo ogni 10 valutazioni positive.
- **Riconoscimenti fedeli ai dati:** vengono mostrati *solo* per le caratteristiche presenti nei tag delle recensioni pubblicate da almeno 8/10, senza classificazioni automatiche di persone.
- **Profilo ristorante:** eventuali foto della galleria caricate dal titolare compaiono nell'anteprima del locale. Nessuna foto stock o generata è usata nell'interfaccia.
- **Tipografia e superfici:** gerarchia editoriale più nitida, pannelli con profondità leggera, dettagli metallici discreti e miglioramenti per stati vuoti e premi.
- **Compatibilità:** layout fluido per Android, iPhone e schermi pieghevoli aperti/chiusi. Verifica su dispositivo fisico ancora necessaria.

**Limiti invariati:** demo senza database e autenticazione reale. Foto e dati demo salvati solo sul dispositivo; nessuna condivisione o nota riservata realmente protetta.

## Aggiornamenti

- Rimosse **tutte** le immagini illustrative di ristoranti e piatti. Nessun asset stock o generato viene mostrato nel prodotto.
- Nuovi hero grafici con monogrammi, sigilli, pattern originali, palette verde bottiglia, avorio, terracotta e oro sobrio.
- Transizioni tra aree e sezioni con View Transitions quando disponibili e fallback breve; rispettano «Riduci movimento».
- Area ristoratore → **Gestione**: caricamento facoltativo della propria copertina, logo e tre foto della galleria. Solo JPG/PNG/WebP, fino a 6 MB per sorgente, poi ridimensionate prima di salvarle localmente. Pulsanti per sostituire/rimuovere.
- L'anteprima del ristorante nelle schermate mostra soltanto foto scelte dal titolare; quando assenti, usa un elegante placeholder illustrativo tipografico.
- Layout per iPhone, Android e pieghevoli con griglie responsive, senza imporre fotografie o banner.
- Nessuna modifica alla regola: **positivo soltanto da 8 stelle su 10**; buono demo ogni 10 recensioni positive.

## Test

Eseguire `npm test`; inoltre test manuali con Chrome Android, Safari iPhone e dispositivi pieghevoli (chiuso/aperto) prima di offrire la versione reale. Le foto non sono dati condivisi: per questo servirà un backend dedicato, non ancora attivo.

## Sicurezza e limiti

- Questa è una **demo locale**, non una piattaforma funzionante per persone vere.
- `account.html` è una **predisposizione disattivata**: senza un progetto Supabase dedicato non consente la registrazione. **Non inserire dati personali o credenziali reali.**
- Il database non è stato creato, configurato né collegato; `database/schema.sql` è solo una bozza da riesaminare in futuro. Non applicarla a EasyGart, SINDRU o altri progetti.
- Le note non sono condivise tra ristoranti e non vanno considerate riservate nella demo: sono dati locali del browser. Un'eventuale funzione reale dovrà avere permessi server, moderazione, diritti privacy e revisione giuridica prima del lancio.
- I buoni non hanno valore economico. I termini commerciali del programma saranno definiti più avanti.

## Test

`npm test` esegue test automatici della scala 1–10, della soglia positiva 8/10, dei buoni demo, della navigazione a quattro voci e degli elementi UX. In aggiunta, il flusso completo è stato provato su Chromium con viewport 393 × 852, 320 × 720 e desktop; nessuno scorrimento laterale rilevato. Questi controlli non costituiscono un audit di sicurezza né un test diretto su Safari iOS.

## GitHub → Vercel

Repository: `andru1607/BuonTavolo`, branch `main`. Progetto statico con framework **Other**, senza comando di build. Il push su `main` avvia il deploy nei progetti Vercel già collegati, da verificare attraverso lo stato del commit. Se vi sono due progetti collegati allo stesso repository, scegliere uno come destinazione definitiva in seguito.

## Dettagli vivi della V7.2

- **Home cliente:** messaggio contestuale calcolato dal progresso dei timbri; piccoli suggerimenti illustrati, stati vuoti editoriali e feedback quando si compiono azioni.
- **Home ristoratore:** segnalazione dell’ultimo ospite aperto e accesso rapido agli ultimi quattro profili consultati; informazioni salvate soltanto nel browser demo.
- **Identità del locale:** breve frase personalizzabile e scelta dell’atmosfera (accogliente, tradizionale, contemporaneo o informale) da Gestione; mostrate anche nell’anteprima cliente. Le immagini restano solo quelle caricate dal ristoratore.
- **Motion:** ingressi rapidi e delicati, risposta dei bottoni e toast visivamente distinti; preferenza Riduci movimento sempre rispettata.
- **Compatibilità:** layout fluidi per iPhone, Android e pieghevoli aperti/chiusi; la verifica fisica sui dispositivi resta da eseguire.
- **Protezione dei dati:** funzione dimostrativa, senza database, senza autenticazione e senza informazioni reali. I dati delle foto, della frase del locale e degli ospiti recenti rimangono nel browser.

Eseguire `npm test` per i controlli JavaScript della V7.2.# GoodDiner V7.5 · Nuovo simbolo GD

Il marchio provvisorio è stato sostituito dalla **terza proposta scelta dall'utente**: due forme GD intrecciate con un piccolo accento oro. I file SVG `icons/mark.svg` e `icons/mark-light.svg` sono vettoriali a colori piatti, adattabili allo sfondo. `icons/icon.svg`, le icone PNG 180/192/512, l'intestazione desktop/mobile, l'onboarding e l'Apple Touch Icon sono coerenti col nuovo segno. La cache offline è aggiornata e i test coprono il marchio.

**Solo demo**, senza backend e senza autenticazione reale. La disponibilità legale di GoodDiner come marchio resta da verificare.

# GoodDiner V7.4 · Nuova identità

**Nome scelto:** GoodDiner. **Stato:** demo frontend; nessun database o autenticazione reale. **Verifica legale:** il nome non è ancora stato definitivamente liberato da un controllo professionale sui marchi; non presentarlo come registrato o esclusivo.

## Cosa cambia

- Nome e testi aggiornati in home cliente, area ristoratore, onboarding, account, manifest PWA e schermate premi.
- Logo vettoriale provvisorio **GD**, minimal, senza posate, piatti o emoji; icone PWA 180/192/512 rigenerate.
- Funzioni riconoscibili: **DinerPass** (tessera), **DinerBadge** (riconoscimenti), **DinerRewards** (premi), con identità del cliente al centro.
- Nessuna emoji o stella testuale nei flussi UI: valutazioni e simboli sono resi con SVG; la scala resta da 1 a 10.
- Nuovi buoni demo con prefisso `GD-`; i buoni `BT-` già presenti nella memoria locale restano leggibili e riscattabili.
- Le chiavi di `localStorage` precedenti restano volutamente immutate per preservare dati, fotografie e preferenze demo esistenti.
- La bozza SQL non è stata eseguita né collegata. I nomi tecnici `bt_*` rimangono come identificatori storici nel file di schema, che dovrà essere revisionato prima di un backend reale.
- Il repository GitHub resta temporaneamente `andru1607/BuonTavolo` per non rompere il deploy automatico Vercel esistente.
- Il rebranding non cambia il funzionamento: **positive solo recensioni 8–10/10**, un buono demo ogni 10 positive.



- **Tessera reputazionale a due facce:** vista principale e retro con ID, media e conteggio delle recensioni positive. Pulsante "Girala" accessibile e animazione breve; su mouse è presente un riflesso che segue il puntatore (non obbligatorio sui touch). La preferenza Riduci movimento disabilita tutte le animazioni decorative.
- **Navigazione inferiore:** dock con icona attiva evidenziata e feedback al tocco, mantenendo solo quattro voci per ruolo e le aree sicure di iOS/Android.
- **Timbri collezionabili:** disegno a sigillo e animazione soltanto per l'ultimo timbro. Un effetto breve annuncia il buono demo ogni 10 valutazioni positive.
- **Riconoscimenti fedeli ai dati:** vengono mostrati *solo* per le caratteristiche presenti nei tag delle recensioni pubblicate da almeno 8/10, senza classificazioni automatiche di persone.
- **Profilo ristorante:** eventuali foto della galleria caricate dal titolare compaiono nell'anteprima del locale. Nessuna foto stock o generata è usata nell'interfaccia.
- **Tipografia e superfici:** gerarchia editoriale più nitida, pannelli con profondità leggera, dettagli metallici discreti e miglioramenti per stati vuoti e premi.
- **Compatibilità:** layout fluido per Android, iPhone e schermi pieghevoli aperti/chiusi. Verifica su dispositivo fisico ancora necessaria.

**Limiti invariati:** demo senza database e autenticazione reale. Foto e dati demo salvati solo sul dispositivo; nessuna condivisione o nota riservata realmente protetta.

## Aggiornamenti

- Rimosse **tutte** le immagini illustrative di ristoranti e piatti. Nessun asset stock o generato viene mostrato nel prodotto.
- Nuovi hero grafici con monogrammi, sigilli, pattern originali, palette verde bottiglia, avorio, terracotta e oro sobrio.
- Transizioni tra aree e sezioni con View Transitions quando disponibili e fallback breve; rispettano «Riduci movimento».
- Area ristoratore → **Gestione**: caricamento facoltativo della propria copertina, logo e tre foto della galleria. Solo JPG/PNG/WebP, fino a 6 MB per sorgente, poi ridimensionate prima di salvarle localmente. Pulsanti per sostituire/rimuovere.
- L'anteprima del ristorante nelle schermate mostra soltanto foto scelte dal titolare; quando assenti, usa un elegante placeholder illustrativo tipografico.
- Layout per iPhone, Android e pieghevoli con griglie responsive, senza imporre fotografie o banner.
- Nessuna modifica alla regola: **positivo soltanto da 8 stelle su 10**; buono demo ogni 10 recensioni positive.

## Test

Eseguire `npm test`; inoltre test manuali con Chrome Android, Safari iPhone e dispositivi pieghevoli (chiuso/aperto) prima di offrire la versione reale. Le foto non sono dati condivisi: per questo servirà un backend dedicato, non ancora attivo.

## Sicurezza e limiti

- Questa è una **demo locale**, non una piattaforma funzionante per persone vere.
- `account.html` è una **predisposizione disattivata**: senza un progetto Supabase dedicato non consente la registrazione. **Non inserire dati personali o credenziali reali.**
- Il database non è stato creato, configurato né collegato; `database/schema.sql` è solo una bozza da riesaminare in futuro. Non applicarla a EasyGart, SINDRU o altri progetti.
- Le note non sono condivise tra ristoranti e non vanno considerate riservate nella demo: sono dati locali del browser. Un'eventuale funzione reale dovrà avere permessi server, moderazione, diritti privacy e revisione giuridica prima del lancio.
- I buoni non hanno valore economico. I termini commerciali del programma saranno definiti più avanti.

## Test

`npm test` esegue test automatici della scala 1–10, della soglia positiva 8/10, dei buoni demo, della navigazione a quattro voci e degli elementi UX. In aggiunta, il flusso completo è stato provato su Chromium con viewport 393 × 852, 320 × 720 e desktop; nessuno scorrimento laterale rilevato. Questi controlli non costituiscono un audit di sicurezza né un test diretto su Safari iOS.

## GitHub → Vercel

Repository: `andru1607/BuonTavolo`, branch `main`. Progetto statico con framework **Other**, senza comando di build. Il push su `main` avvia il deploy nei progetti Vercel già collegati, da verificare attraverso lo stato del commit. Se vi sono due progetti collegati allo stesso repository, scegliere uno come destinazione definitiva in seguito.

## Dettagli vivi della V7.2

- **Home cliente:** messaggio contestuale calcolato dal progresso dei timbri; piccoli suggerimenti illustrati, stati vuoti editoriali e feedback quando si compiono azioni.
- **Home ristoratore:** segnalazione dell’ultimo ospite aperto e accesso rapido agli ultimi quattro profili consultati; informazioni salvate soltanto nel browser demo.
- **Identità del locale:** breve frase personalizzabile e scelta dell’atmosfera (accogliente, tradizionale, contemporaneo o informale) da Gestione; mostrate anche nell’anteprima cliente. Le immagini restano solo quelle caricate dal ristoratore.
- **Motion:** ingressi rapidi e delicati, risposta dei bottoni e toast visivamente distinti; preferenza Riduci movimento sempre rispettata.
- **Compatibilità:** layout fluidi per iPhone, Android e pieghevoli aperti/chiusi; la verifica fisica sui dispositivi resta da eseguire.
- **Protezione dei dati:** funzione dimostrativa, senza database, senza autenticazione e senza informazioni reali. I dati delle foto, della frase del locale e degli ospiti recenti rimangono nel browser.

Eseguire `npm test` per i controlli JavaScript della V7.2.