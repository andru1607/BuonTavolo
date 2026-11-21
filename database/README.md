# GoodDiner · Database dedicato (installato, home 1.0 collegata)

**Stato verificato il 21 novembre 2026:** progetto Supabase **GoodDiner** creato e attivo nell'organizzazione **andru1607's Org**, regione `eu-central-1` (Francoforte), project ref `ixczkhmvbjszgmlqznlk`. Confermato costo mensile di creazione pari a 0. **Non è il progetto easygart.**

Sono state applicate in Supabase le migrazioni `gooddiner_initial_secure_schema` (`20261120163135`), `gooddiner_policy_performance_baseline` (`20261120163247`) e `gooddiner_operator_only_moderation_audit` (`20261121164607`), oltre a `gooddiner_privacy_requests_and_rights` (`20261121171031`). Ora esistono **8 tabelle pubbliche e 3 tabelle private**, tutte con RLS. Le verifiche del 21 novembre confermano nessun account, locale o intervento di moderazione fittizio; assenza di SELECT `anon` sulle tabelle applicative; funzione di approvazione ristoranti e funzione di risoluzione contestazioni **solo `postgres`**, non eseguibili da `anon`/`authenticated`; tabella audit dell'operatore non leggibile dal client. I test negativi con ID inesistenti sono passati. Gli advisor mostrano come attese 3 tabelle private deny-all senza policy e 4 funzioni pubbliche `SECURITY DEFINER` eseguibili solo dagli autenticati con controlli interni; [advisor RLS](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy) e [advisor funzioni](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable). **Sono stati eseguiti** test SQL transazionali con sei utenti fittizi e rollback completo per verificare permessi, presenze, recensioni e istanze privacy, senza salvare utenti fittizi. **Restano da eseguire** le prove Auth su dispositivi veri e la moderazione effettiva dopo verifica umana.

**La home principale GoodDiner v1.0 è collegata a questo database tramite `official.js` e chiave browser pubblicabile in `config.js`.** La vecchia demo vive soltanto su `/demo.html` per i test, e `account.js` legacy è disabilitato. Non annunciare il lancio pubblico prima dei test RLS multiutente, della configurazione Auth, delle verifiche dei gestori e della valutazione GDPR. EasyGart non è stato modificato.

## Contenuto

`gooddiner_privacy_requests.sql` aggiunge `public.privacy_requests` con RLS, vincolo sulle richieste doppie e una routine `gd_private.close_privacy_request` riservata all'operatore, con audit. L'app mostra la coda personale e permette l'esportazione JSON paginata. [Procedura e limiti](../docs/privacy-operations.md).

`gooddiner_operator_moderation.sql` aggiunge un registro di audit riservato e due funzioni `SECURITY INVOKER` disponibili soltanto all'operatore SQL interno: [procedure e limiti](../docs/operator-moderation.md). La creazione di una funzione tecnica non costituisce una verifica reale o approvazione automatica del locale.

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
- **Moderazione e GDPR**: le routine riservate di approvazione e moderazione e il registro privato sono installati, ma occorrono un operatore identificato, procedure di verifica indipendente, tempi e canali di risposta, informativa, base giuridica, limiti della valutazione delle persone, accesso ai dati, rettifica/cancellazione, conservazione, possibile DPIA e revisione legale. Nessuna raccolta reale finché non completati.
- **Protezione abuso**: CAPTCHA/Turnstile e limiti anche a livello gateway per iscrizioni anonime e QR; monitoraggio, revoca sessioni, job di pulizia token scaduti e audit.
- **Frontend**: `official.js` è collegato alle nuove RPC, con sola chiave publishable. `account.js` è una bozza storica disabilitata e non deve essere riattivato. La demo locale rimane disponibile in `/demo.html` esclusivamente per test.
- **Schema**: le due migrazioni sono già state applicate al progetto dedicato e gli advisor eseguiti. Restano i test RLS con almeno due utenti e due ristoranti prima di aprire il servizio al pubblico.

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
## Conteggi affidabili e paginazione

La migrazione `gooddiner_accurate_statistics.sql` aggiunge due RPC **SECURITY INVOKER**, che non bypassano RLS, per ottenere i conteggi esatti del cliente e del singolo locale verificato. Le liste nell'interfaccia sono caricate a pagine di 250 record per ruolo e i riepiloghi non dipendono più dalle pagine scaricate. I conteggi e la paginazione reali devono ancora essere collaudati su più dispositivi con account veri.
