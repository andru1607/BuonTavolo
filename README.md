# BuonTavolo · V5

**Stato:** demo pubblicabile, più area multiutente *predisposta ma disattivata*. Non è un prodotto operativo e non raccoglie credenziali finché non viene collegato a un database Supabase **dedicato**.

## Apri dal tuo iPhone

- `/` mostra la demo locale, senza dati reali; funziona su Safari e come PWA.
- `/account.html` mostra la nuova area di accesso. Finché `/config.js` è vuoto **non compaiono form di registrazione**.
- L'app cliente include un ID, il nickname, le proprie recensioni e il codice monouso per verificare la presenza al ristorante.
- L'app ristoratore richiede un'attività **verificata manualmente** per poter registrare visite o pubblicare valutazioni.

## Regola di reputazione confermata

- Valutazioni da **1 a 10 stelle**.
- **Da 8 a 10 = positiva**. Da 1 a 7 non è positiva.
- Il traguardo è ogni 10 recensioni positive su visite verificate. La generazione dei *buoni reali* è volutamente disattivata fino alla definizione dell'offerta, degli accordi con i ristoratori e dei controlli antiabuso.
- Nel prototipo storico (`/`) i buoni restano soltanto simulati nel browser.

## Backend: non condividere il database con EasyGart

`database/schema.sql` è una bozza di schema da revisionare e applicare **una volta sola**, esclusivamente al futuro progetto Supabase BuonTavolo (mai a EasyGart, SINDRU o altri database). **Non è una migration già applicata.**

Prevede tabelle `profiles`, `restaurants`, `visit_tokens`, `visits`, `reviews`, `disputes`, privilegi minimi, RLS per ogni tabella e una RPC `claim_visit` che richiede un ristorante verificato e un codice UUID monouso valido 15 minuti.

### Attivazione, dopo la creazione del nuovo progetto

1. Creare un progetto Supabase **dedicato** scegliendo esplicitamente l'organizzazione, verificando eventuali costi.
2. Rivedere lo schema con attenzione; applicarlo al nuovo database e **testare RLS con due account separati** (cliente e ristoratore). Verificare che l'account ristoratore non possa modificare `verified_at`, né leggere profili non collegati.
3. Configurare l'autenticazione email/password e le URL consentite di redirect (`https://<dominio>/account.html`) nel dashboard Supabase.
4. Aggiornare `config.js` con il **project URL** e la sola chiave `sb_publishable_...`. Il publishable key è pubblicabile; non copiare MAI `secret`, `service_role`, credenziali SQL o password nel repository.
5. Verificare login, conferma email, creazione profili, registrazione ristoratore, verifica amministrativa, codice visita e recensione 8/10.
6. Definire privacy/GDPR, informativa, gestione accessi, cancellazioni e rettifiche, abbonamenti e regole dei premi **prima** di invitare utenti reali.

**Nota GDPR:** note visibili ad altri ristoratori e consultazione indiscriminata delle valutazioni **non sono attive**. Occorrono una progettazione giuridica e regole rigorose prima di condividere valutazioni riferite a persone identificabili.

### Protezioni essenziali

- Ogni nuovo account ha un record `profiles` con ruolo cliente oppure ristoratore. **Scegliere il ruolo nel form non equivale a essere ristoratore verificato.**
- I titolari non possono approvare da soli il proprio ristorante.
- Un ristoratore può scrivere una recensione soltanto per una propria visita collegata a un codice temporaneo e se il suo ristorante è verificato.
- Un cliente vede soltanto recensioni e contestazioni proprie.
- Non esiste ricerca globale dei clienti o delle note tra ristoranti.
- L'area autenticata non viene salvata nella cache PWA offline.

## Verifica del codice prima dei push

```sh
npm test
node --check account.js
node --check sw.js
```

I test automatici controllano la scala 1–10, 7 stelle non positive, 8 stelle positive, il buono demo al decimo feedback positivo e il blocco della registrazione quando manca il backend. **Non sostituiscono i test di sicurezza sul database reale.**

## Deployment

GitHub: `andru1607/BuonTavolo`, branch `main`, importazione in Vercel **Framework Other**. Non sono richiesti build command, ambiente server o segreti finché il nuovo database non è configurato. Controllare eventuali progetti Vercel duplicati collegati allo stesso repository.