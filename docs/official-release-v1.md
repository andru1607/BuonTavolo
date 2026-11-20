# GoodDiner 1.0 · App con dati reali (accesso controllato)

**Progetto Supabase dedicato:** GoodDiner, `ixczkhmvbjszgmlqznlk` in `andru1607's Org` (`eu-central-1`, Francoforte). Nessuna modifica a EasyGart.

## Cambiamenti

- `/` è l'app principale, non una demo: account Supabase Auth, codice cliente `GD-*` assegnato dal trigger, profili e cronologia letti tramite RLS, token QR di 90 secondi generati dalla RPC, ristoranti e stato delle verifiche dal database.
- La precedente demo a dati simulati resta in `/demo.html` **solo per regressioni**. Non viene proposta nella navigazione pubblica. `account.html` è il vecchio prototipo ed è disabilitato.
- Registrazione cliente: nickname obbligatorio; email e telefono non obbligatori. Senza email si tenta l'account anonimo autenticato da Supabase, che **non è recuperabile** se si perde la sessione, finché non si collega un'identità verificata. Il telefono non viene memorizzato perché non è verificato; il collegamento email in Profilo prevede prima verifica email e poi impostazione password.
- Registrazione ristoratore: email/password richieste, richiesta di verifica attività nella tabella `merchant_applications`. La semplice ricerca su Google Maps non abilita nessun privilegio. Solo i locali con `verified_at` assegnato da un amministratore possono usare lo scanner.
- Check-in: lettura QR tramite API nativa `BarcodeDetector` se supportata o inserimento manuale, RPC atomica `checkin_guest`, storico visite, annullamento tracciato, recensione soltanto su presenza confermata.
- 8–10/10 sono valutazioni positive. Il database crea traguardi `pending` dopo ogni 10 positive; i premi non sono riscattabili in questa fase.
- `official.css` ha layout mobile-first, campi >= 16px per Safari iOS, animazioni ridotte in base alla preferenza di accessibilità. Il QR contiene un token monouso, mai nickname o recapiti.

## Configurazione e blocchi per l'accesso pubblico

1. In **Supabase → Authentication → URL Configuration**, configurare `Site URL` sull'URL pubblico Vercel ufficiale e aggiungere `/` tra gli indirizzi di reindirizzamento autorizzati. Le conferme email e il recupero password dipendono da questi URL.
2. In **Supabase → Authentication → General configuration**, per gli utenti senza recapiti attivare `Allow anonymous sign-ins`; aggiungere protezione anti-abuso Cloudflare Turnstile/hCaptcha prima di aprire al pubblico. Senza provider anonimo il cliente deve registrarsi con email. Per associare un'email a un account anonimo occorre il percorso di verifica e le impostazioni di identity linking.
3. Verificare e configurare **SMTP ed email**: limiti del servizio email predefinito Supabase, conferma account, reindirizzamenti, reset password.
4. Definire operatore/titolare del trattamento, **informativa GDPR completa**, meccanismo per richiedere rettifica/cancellazione, gestione contestazioni, periodi di conservazione, controlli sulle recensioni e idoneità giuridica del sistema di reputazione riferito a persone. La pagina Privacy nell'app è solo trasparenza tecnica, non sostituisce questo lavoro.
5. **Verifica gestori:** preparare procedura documentale, controlli anti-frode e interfaccia amministrativa protetta; nessuna autoapprovazione dal browser. In attesa, gli account ristoratori rimangono `pending`. Nessuna attività è verificata nel database appena creato.
6. **Scanner Safari/iPhone:** fallback software jsQR `1.4.0` (Apache-2.0, https://github.com/cozmo/jsQR) caricato su richiesta tramite jsDelivr; legge i fotogrammi localmente, senza inviarli a un server. Il lettore nativo `BarcodeDetector` è usato solo quando disponibile; l'inserimento manuale resta sempre accessibile. La fotocamera viene interrotta al passaggio in background e dopo la chiusura, anche se il permesso era ancora in sospeso. **Resta necessario il collaudo su iPhone Safari reale**, con scanner e tastiera aperti.
7. **Test multiutente RLS e sessioni:** i test UI sono stati effettuati con una simulazione del client SDK; i test di autorizzazione live end-to-end con due utenti reali e due locali sono ancora necessari prima di consentire valutazioni su persone reali.

L'app principale non presenta dati di esempio. In caso di errore Supabase mostra un messaggio esplicito, non risultati simulati. `config.js` contiene solo la chiave **pubblica**, mai service-role/secret.

## Collaudo

- `node --check official.js`; `npm test` (test regressione demo e test della nuova app) e rendering Chromium con SDK simulato su 320, 375, 390, 430, 740, 1024 e 1280 px.
- Dopo ogni deploy, verificare l'accesso pubblico, la presenza di codice `GD-*` ottenuto dal server, la conferma email, la possibilità di leggere solo dati propri e la mancata concessione di permessi ristoratore a utenti non verificati.