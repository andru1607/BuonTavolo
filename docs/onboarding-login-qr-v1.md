# GoodDiner · Flusso login, profili e DinerPass QR (specifica V1)

**Stato:** specifica di prodotto approvata come direzione UX, **NON implementazione live**. Il backend Supabase non è attivo. Non abilitare iscrizioni effettive, lookup online o check-in tra dispositivi prima di infrastruttura, sicurezza e privacy.

## Principi non negoziabili
- Nessuna scelta “Sei cliente o ristoratore?” al primo avvio. Prima schermata uguale per tutti, identità GoodDiner, azioni “Accedi”, “Crea account” e “Esplora la demo”.
- La scelta del percorso appare solo dopo “Crea account”: “Profilo personale” e “Registra un ristorante”, con etichette e linguaggio chiari.
- Due aree dopo il login: clienti e ristoratori verificati. Le UI e i permessi non devono essere confusi.
- Mai dire che un account ristoratore è verificato soltanto perché il locale esiste online. Demo e account veri devono essere chiaramente distinti.

## Cliente: registrazione e login
1. Input obbligatorio: nickname, con validazione e limiti; nickname non è dato affidabile per autenticare o identificare univocamente la persona.
2. Input facoltativi: email e numero di telefono. Nessuna necessità di fornirli per avere un profilo.
3. Credenziale obbligatoria: passkey (WebAuthn) o altra autenticazione sicura equivalente; non basta conoscere il nickname o codice cliente. Se contatti assenti, mostrare e far salvare un codice di recupero una sola volta, con spiegazione dei rischi.
4. Il server crea un ID interno casuale non prevedibile, separato dal codice pubblico utente leggibile, ad esempio GD-7K42P9. Il codice pubblico non è una password o token di autenticazione.
5. Al termine, mostrare DinerPass con nickname, codice, QR dedicato all'identificazione della presenza, privacy e scorciatoia per mostrare il codice; area badge separata da dati pubblici.
6. Evitare che email, telefono e credenziali vengano copiati nel QR o mostrati ai ristoratori.

## Ristoratore: identificazione e verifica
1. Nel percorso “Registra un ristorante”: campo Nome locale, città e ricerca suggerimenti. Usare un provider affidabile come Places API con nome, indirizzo e place_id. Visualizzare fonte e attributi conformemente ai termini del fornitore; non effettuare scraping indiscriminato.
2. Selezione sede precisa, conferma dati e referenze; gestire omonimie, più sedi, attività assenti dalla directory e cambi proprietà.
3. Separare `found_online` da `verified_operator`. Verifica gestione: Google Business Profile autorizzato dove tecnicamente/contrattualmente applicabile, verifica recapito d'impresa o verifica documentale/manuale. Non basarsi solo sul controllo di un telefono pubblico o una email privata.
4. Stati espliciti: `draft`, `place_matched`, `pending_verification`, `verified`, `rejected`, `suspended`. Fino a `verified`, impedire server-side registrazione presenze e recensioni.
5. Account responsabile e staff con permessi separati, accesso registrato e revoca.

## DinerPass e QR personale
- L'ID pubblico del cliente è stabile; il QR visualizzato nel suo badge è invece un **token opaco, firmato, a vita breve** (es. 60-120 secondi), rinnovabile, vincolato all'utente, con anti-replay e nessun dato personale in chiaro. Non usare il codice pubblico come unica prova della presenza.
- DinerPass presenta un QR leggibile, un codice manuale di fallback accessibile, livello di zoom, testo esplicativo “Mostralo al ristoratore per registrare la visita”. Evitare QR permanenti facilmente fotografabili e riutilizzabili.
- Home ristoratore verificato: azione principale “Scansiona DinerPass”; l'app richiede il permesso camera soltanto quando serve; fallback manuale e compatibilità Safari iOS/Android. `BarcodeDetector` ha compatibilità limitata, prevedere decoder con fallback e controllo camera `getUserMedia` su HTTPS.
- Alla scansione, il server verifica token, utente, ristorante, autorizzazione operatore e limiti anti-duplicazione e **registra immediatamente la presenza**, con feedback “Presenza registrata”. Mostrare soltanto nickname e codice parziale, non email/telefono. Prevedere correzione motivata per scansione errata.
- La scansione intenzionale del QR mostrato dal cliente costituisce l'azione di check-in. Stato visita: `confirmed`, oppure `voided` dopo correzione motivata/contestazione. Il cliente riceve una notifica con nome del locale, data e possibilità di segnalare una presenza non riconosciuta. Non imporre un secondo tap di conferma al cliente nel flusso normale; l'associazione recensione è permessa solo da una visita `confirmed`.
- La visita registra `customer_id`, `restaurant_id`, `checked_in_at`, `status`, `merchant_actor_id`; niente posizione GPS precisa. Log audit per dispute, retention limitata e cancellazione secondo policy approvate.
- Ristoratore: dopo conferma visita, mostrala in “Presenti oggi / Visite registrate” e poi “Da recensire”. Non assegnare recensione automaticamente.

## Coerenza con reputazione e privacy
- Positiva solo recensione **8, 9 o 10 / 10**; un voucher ogni **10** recensioni positive; le recensioni non si creano senza presenza valida.
- Trasparenza su scopo e destinatari del trattamento, base giuridica appropriata, minimizzazione, protezione dati, accesso, rettifica, contestazione e cancellazione dove applicabili. La valutazione reputazionale di persone richiede revisione GDPR e probabilmente valutazione dei rischi prima di produzione.
- QR e codice pubblico non devono concedere accesso a informazioni private né permettere di falsificare presenze o recensioni.
- Non usare direttamente localStorage come fonte di verità per identità o visite reali. Supabase dedicato, RLS, transazioni lato server e verifica token server-side sono prerequisiti.

## Sequenza delle schermate
1. Benvenuto pubblico: logo / valore / Accedi / Crea account / Esplora demo.
2. Accesso: passkey preferita; alternative applicabili quando registrate. Nessun ruolo richiesto.
3. Creazione account: scelta discreta Profilo personale / Registra ristorante.
4. Cliente: nickname, email/telefono facoltativi, passkey + recupero, conferma, DinerPass con QR.
5. Ristoratore: ricerca locale online, selezione sede, prova controllo, stato verifica, dashboard con scanner QR quando approvato.
6. Cliente: notifiche visita da approvare, storico visite, recensioni e premi.

## Criteri di accettazione
- All'apertura non compare nessuna scelta di ruolo; “Accedi” e “Crea account” portano a flussi distinti.
- Registrazione cliente senza email e telefono ammessa, ma non senza autenticazione sicura e metodo di recupero spiegato.
- Ogni cliente ha nickname, ID stabile e QR opaco a scadenza in DinerPass.
- Un ristorante trovato online non ottiene automaticamente privilegi di ristoratore verificato.
- Scansione QR valida e autorizzata salva la presenza subito, senza secondo consenso manuale; QR fallito/scaduto/duplicato non crea visite. Il check-in appare nella home del solo locale autorizzato e nello storico del cliente, con contestazione disponibile.
- Nessuna recensione senza visita confermata; nessun dato sensibile nel payload QR; supporto scanner iOS/Android con fallback.
- Backend non collegato: tutto ciò rimane documentazione/preview, non viene presentato come operativo.

## Ricerca tecnica consultata (2026-11)
- Google Places Text Search: https://developers.google.com/maps/documentation/places/web-service/text-search
- Google Business Profile verification: https://developers.google.com/my-business/content/manage-verification
- FIDO passkeys: https://fidoalliance.org/passkeys/
- BarcodeDetector browser compatibility: https://developer.mozilla.org/en-US/docs/Web/API/BarcodeDetector
- GDPR UE: https://eur-lex.europa.eu/eli/reg/2016/679/oj/eng/
