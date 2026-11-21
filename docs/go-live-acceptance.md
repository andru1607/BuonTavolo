# GoodDiner · Accettazione prima del lancio

Ultima revisione tecnica: 21 novembre 2026. Questo è un registro di verifiche, **non** una dichiarazione di conformità o di pubblicazione. Repository: `andru1607/BuonTavolo`. Supabase dedicato: `ixczkhmvbjszgmlqznlk`.

## A. Evidenze già disponibili

- [x] Database: prova **transazionale** `database/gooddiner_transactional_rls_test.sql` passata con 6 identità simulate, 2 locali verificati, 1 non verificato e rollback completo. Copre RLS, autorizzazioni ai gestori, token QR scaduti/rigiocati, duplicato giornaliero, recensione duplicata, contestazione e annullamento.
- [x] Ricontrollo dopo il test: nessun account, profilo, visita, recensione, token o intervento di moderazione persistente nel progetto.
- [x] Registro interno delle decisioni degli operatori con permessi negati a `anon` e `authenticated`.
- [x] Release gate nel frontend: nuove registrazioni **chiuse di default**; Turnstile mostrato solo dopo impostazione della *site key pubblica*. Senza chiave non è possibile aprire le registrazioni tramite la UI.
- [ ] Domini Vercel **non verificati** direttamente. Due check Vercel su GitHub non identificano da soli un URL pubblico canonico.

## B. Configurazioni necessarie prima di aprire le iscrizioni

Le operazioni seguenti richiedono accesso dell'amministratore ai rispettivi account. Le chiavi segrete non devono mai comparire nel repository o in una conversazione.

1. **Dominio canonico:** [Vercel](https://vercel.com/dashboard). Verificare quale progetto sia collegato a `andru1607/BuonTavolo`, scegliere UN dominio HTTPS raggiungibile, controllare risposta HTTP 200 e contenuti di `/official.js`. L'attuale connessione Vercel del progetto ChatGPT vede `sindru` e non il progetto GoodDiner: non crearne una copia alla cieca.
2. **Variabile GitHub:** [Actions Variables](https://github.com/andru1607/BuonTavolo/settings/variables/actions): impostare `GOODDINER_BASE_URL` all'origine esatta `https://dominio-verificato`. Al successivo push su main, il test `scripts/live-smoke.mjs` controllerà la home, il client, il modulo anti-bot, il manifest e la configurazione. Se la variabile non esiste il test **viene saltato**, non è da considerarsi passato.
3. **Autenticazione:** [Supabase Auth Providers](https://supabase.com/dashboard/project/ixczkhmvbjszgmlqznlk/auth/providers). Verificare login email/password, conferma email e scelta esplicita sull'accesso anonimo; non pubblicare un signup anonimo senza antiabuso.
4. **URL email:** [Supabase URL Configuration](https://supabase.com/dashboard/project/ixczkhmvbjszgmlqznlk/auth/url-configuration). Impostare il dominio canonico come Site URL e consentire esclusivamente i redirect HTTPS necessari (signup/confirm/recovery). Testare che i link riportino al dominio corretto, non alla demo.
5. **Posta:** [Supabase Email Templates](https://supabase.com/dashboard/project/ixczkhmvbjszgmlqznlk/auth/templates). Configurare provider SMTP affidabile e dominio di invio; controllare recapito, conferma e recupero su mailbox che appartengono ai tester. Non registrare password nei report.
6. **Anti-bot:** creare un widget [Cloudflare Turnstile](https://dash.cloudflare.com/) per il dominio esatto. Mettere la *secret key* solo in [Supabase Bot and Abuse Protection](https://supabase.com/dashboard/project/ixczkhmvbjszgmlqznlk/auth/protection), selezionando il medesimo provider. Inserire **solo la site key pubblica** nel campo `turnstileSiteKey` di `config.js`. Verificare il rifiuto di signup/login/recovery privi del token sia dal browser sia da richieste API dirette. Il blocco visuale non protegge le API se Supabase non è configurato.
7. **Apertura controllata:** soltanto dopo le verifiche tecniche, la nomina dell'operatore e la revisione legale, modificare `registrationEnabled: true` in `config.js`, eseguire CI/HTTP smoke e rilascio controllato. Non rimuovere `noindex` prima di avere un'informativa privacy approvata e un dominio verificato.

## C. Test autenticazione con identità reali

Eseguire questi casi su ambiente di collaudo isolato o con **volontari informati e autorizzati**, non con dati di clienti casuali. Registrare data, build, dispositivo, risultato atteso/osservato e issue, senza password o dati sensibili:

- [ ] Cliente con email: signup, email ricevuta, click conferma, accesso e logout.
- [ ] Password dimenticata: link ricevuto, nuova password, impossibilità di usare quella precedente.
- [ ] Utente anonimo se attivato: accesso locale; collegamento email; conferma; impostazione password; recupero da secondo dispositivo; stessa identità/codice personale.
- [ ] Ristoratore con email confermata: richiesta inizialmente **pending**, impossibilità di scansionare senza verifica umana, approvazione solo con prove reali.
- [ ] Titolare A non può confermare visite/recensioni del locale B.
- [ ] Cliente A non vede profilo, visite, recensioni, contestazioni e premi del cliente B.
- [ ] Token QR: validità fino a 90 s, riutilizzo respinto, scadenza respinta, duplicato nel giorno/locale respinto.
- [ ] Recensione da 1 a 10 solo su visita confermata; 7 non positivo e 8 positivo; contesto privacy.
- [ ] Contestazione cliente: una richiesta, stato in attesa e decisione umana tracciata.
- [ ] Nessuna nuova registrazione API diretta senza verifica anti-bot.
- [ ] Paginazione e conteggio corretto con più di 250 visite o recensioni per ruolo.

## D. Test Safari iPhone e Android

- [ ] iPhone Safari su HTTPS reale: layout a 375 e 430 CSS px; tab inferiori max 4; tastiera senza zoom, pulsanti non coperti dalla safe area.
- [ ] Permesso fotocamera inizialmente negato: messaggio comprensibile e fallback con codice manuale, nessun blocco.
- [ ] Permesso fotocamera consentito: scanner jsQR senza `BarcodeDetector`, risultato corretto su due dispositivi.
- [ ] Camera aperta, tasto Home / altra app, ritorno: stream sospeso, riavvio solo volontario, nessun fotogramma inviato a server esterni.
- [ ] QR cliente dopo oltre 90 secondi in background: schermata scaduta, nuovo token solo su richiesta.
- [ ] Modal scanner chiuso durante richiesta permesso: tracce camera tardive disattivate.
- [ ] Dispute e annullamento: textareas leggibili, lunghezza obbligatoria, focus e chiusura corretti.
- [ ] Web app installata dalla Home iOS: sessione, orientamento e reindirizzamento email corretti.

Nessuno dei test fisici qui sopra è marcato completato: richiedono dispositivi reali e un URL funzionante.

## E. Condizioni giuridiche e operative

- [ ] Identità e contatti del **titolare effettivo del trattamento**; fornitori, accordo/DPA con Supabase, incaricati e responsabili; policy di retention.
- [ ] Base giuridica specifica per la valutazione delle **persone**, trasparenza prima del check-in, minimizzazione e diritti GDPR; analisi dei rischi e valutazione DPIA da professionista incaricato quando necessaria.
- [ ] Policy pubblica sulle recensioni, casi vietati, correzioni, contestazioni e revisione umana con tempi e responsabilità.
- [ ] Procedure verificabili per accesso, portabilità, rettifica, cancellazione/limitazione e reclami, senza eliminazione indiscriminata di registri legittimi.
- [ ] Verifica del marchio/nome GoodDiner e delle classi rilevanti tramite [EUIPO](https://www.euipo.europa.eu/) e [UIBM](https://uibm.mise.gov.it/), preferibilmente professionale.
- [ ] Un addetto reale incaricato dell'approvazione dei locali; conservazione protetta delle prove necessarie, nessuna scheda Maps come prova sufficiente.
- [ ] Eseguire un ultimo controllo degli advisor Supabase; monitorare errori e predisporre backup/incident response.

**Regola di pubblicazione:** il progetto può essere considerato pronto soltanto quando ogni punto fondamentale sopra ha una prova verificabile e un responsabile. Non sostituire una checkbox con una promessa.
