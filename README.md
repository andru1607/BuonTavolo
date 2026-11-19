# BuonTavolo · V6

**Stato:** anteprima web **mobile-first** con dati **interamente dimostrativi**. La versione V6 non utilizza database né raccoglie registrazioni reali. Le funzioni che simulano recensioni, premi e note sono salvate nel browser di chi prova la demo; non hanno effetti su altre persone.

## Cosa cambia rispetto alla V5

- **Identità editoriale originale:** passaporto ospite verde bottiglia con sigillo e identificativo, interfaccia su carta avorio, dettagli terracotta e tipografia calda.
- **Esperienza cliente:** tessera centrale con copia ID, media e livello indicativo; dieci timbri di progressione verso il buono; recensioni in formato diario e premi con codice dimostrativo.
- **Esperienza ristoratore:** Home come registro di sala, ricerca rapida per nickname o ID, dati essenziali in evidenza, scheda ospite con media/recensioni, "salva ospite" per ritrovarlo.
- **Recensioni:** rimane un percorso guidato in 3 passaggi. La valutazione va da **1 a 10 stelle** e soltanto 8/9/10 sono positive. Commento e caratteristiche della visita; nota facoltativa **solo nella simulazione**.
- **Esperienza iPhone:** barra con quattro sezioni, pulsanti raggiungibili con una mano, nessuno scorrimento orizzontale ai formati 320/393 px, responsive desktop.
- **Piccoli dettagli:** sigillo illustrato, timbri animati (rispettano "Riduci movimento"), scheda a biglietto per il buono, indicatori di stato e testi in linguaggio naturale.

## Come provarla

1. Aprire il sito pubblicato e scegliere **Cliente** o **Ristoratore**.
2. In **Cliente** si può consultare il passaporto di LunaBlu (9 recensioni positive) e vedere il traguardo 9/10.
3. In **Ristoratore**, scegliere LunaBlu e compilare una recensione da **8 stelle** con data e visita simulata valide. Il cliente riceverà un buono dimostrativo alla decima recensione positiva.
4. Nella scheda cliente del ristoratore, premere **☆ Salva** per ritrovarlo nella Home; il salvataggio vale soltanto in questo browser.
5. I dati possono essere ripristinati da **Gestione → Ripristina i dati dimostrativi**.

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