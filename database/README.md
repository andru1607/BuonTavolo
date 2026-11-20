# GoodDiner · Database dedicato (staging)

**Stato: schema pronto, NON applicato a Supabase.** Attualmente l'unico progetto accessibile è `easygart`: non eseguire SQL lì. Occorre creare un **progetto Supabase separato**, dopo aver confermato l'organizzazione e gli eventuali costi.

## Contenuto

`gooddiner_initial.sql` crea le tabelle pubbliche `profiles`, `merchant_applications`, `restaurants`, `visits`, `reviews`, `disputes`, `vouchers`; le tabelle riservate `gd_private.visit_tokens` e `gd_private.visit_audit`; un trigger di creazione del profilo senza escalation da metadati; policy RLS e permessi per riga/colonna; funzioni verificate per emettere QR, registrarne il check-in, annullare la visita e pubblicare recensioni.

## Flussi

1. Supabase Auth crea un account; il trigger crea il profilo cliente e il codice GD. La persona può modificare solo il nickname. Per iscrivere un ristoratore occorre un account permanente (email, telefono o altro provider d'identità idoneo), non anonimo.
2. Il gestore inserisce una richiesta `merchant_applications`; il locale ritrovato online **non è** verifica di titolarità. Un amministratore esamina la richiesta e crea/attiva `restaurants` con `verified_at` *solo da contesto server protetto*. Nessun grant client per verificare un locale.
3. Il cliente richiede `issue_guest_qr()`: riceve `GD1:<uuid>` scadente dopo 90 secondi. Il token resta su tabella privata, non contiene PII e non è leggibile via Data API.
4. Solo il titolare verificato può chiamare `checkin_guest(token,restaurant_id)`. Il server controlla scadenza, uso precedente, duplicato per giorno/locale, scrive visita e audit, e restituisce il nickname necessario al check-in. Niente elenco globale dei profili cliente.
5. Solo il titolare verificato può chiamare `publish_guest_review(visit_id,rating,comment)`, collegata a visita confermata. Rating 8, 9, 10 positivo; ogni decimo positivo crea un voucher **pending**, non riscattabile senza verifiche commerciali/privacy.
6. Un cliente vede esclusivamente le sue visite, recensioni, contestazioni e voucher. Un ristoratore vede soltanto le visite e recensioni dei propri locali, mai recapiti o account degli altri clienti.

## Blocco prima del lancio

- **Account senza recapiti**: Supabase Auth supporta l'anonimo, ma **le passkey richiedono un utente permanente confermato**. L'anonimo perde l'account se perde la sessione. Serve decidere un sistema di recupero davvero sicuro, oppure limitare il profilo anonimo a modalità provvisoria, prima della produzione.
- **Verifica operatore**: provider Places/API e controllo documentale/Business Profile con permessi definiti, no “verificato” al semplice risultato di ricerca.
- **Moderazione e GDPR**: informativa, base giuridica, limiti della valutazione delle persone, accesso ai dati, contestazioni, eliminazioni, retention, audit, possibile DPIA. Nessuna raccolta reale finché non completati.
- **Protezione abuso**: CAPTCHA/Turnstile e limiti anche a livello gateway per iscrizioni anonime e QR; monitoraggio, revoca sessioni, job di pulizia token scaduti e audit.
- **Frontend**: `account.js` è una bozza storica (usa vecchie operazioni di insert) e **non è compatibile con questa nuova API finché non viene migrato**. `config.js` resta vuoto e la demo locale resta operativa separatamente.
- **Schema**: eseguire in un progetto **nuovo e vuoto**. Non sovrascrivere le tabelle di altri prodotti. Eseguire advisors Supabase dopo l'installazione, verificare ruoli e test RLS con almeno due utenti e due ristoranti prima di attivare l'accesso.

## Test minimi richiesti sul progetto dedicato

- Nessuna tabella pubblica con RLS disattivata, nessun grant `anon` sulle tabelle.
- Cliente A non legge profilo/visite/voucher del cliente B; nessun cliente può cambiare `role`, `customer_code`, `verified_at` o `rating`.
- Applicazione ristoratore da account anonimo rifiutata. Richiesta da utente permanente resta `pending`.
- Ristorante non verificato non chiama check-in o review, neppure con un QR vero.
- QR scaduto e già usato respinto, nonce di cliente non enumerabile; duplicato stesso giorno respinto.
- Solo il titolare del locale verifica la visita e la corregge prima di recensirla. Audit preservato.
- Recensione solo su visita valida; 7/10 non è positivo; voucher `pending` soltanto sul decimo positivo.
- Una richiesta di contestazione può essere inserita soltanto dall'interessato; nessun utente può approvare il proprio reclamo.

## Documentazione

- https://supabase.com/docs/guides/database/postgres/row-level-security
- https://supabase.com/docs/guides/auth/auth-anonymous
- https://supabase.com/docs/guides/auth/passkeys
- https://supabase.com/docs/guides/api/securing-your-api