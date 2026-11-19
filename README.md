# BuonTavolo V7.2 · Identità visiva e foto del titolare

**Demo frontend, senza database.** I file e le fotografie selezionati nella demo rimangono nel localStorage del browser corrente. Non c’è un caricamento su server o condivisione con altri dispositivi. Non inserire foto con dati personali.

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