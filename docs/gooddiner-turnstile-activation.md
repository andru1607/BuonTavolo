# GoodDiner · Attivazione CAPTCHA Cloudflare Turnstile

**Stato:** frontend pronto, **CAPTCHA non ancora attivo** fino all'installazione congiunta delle chiavi e al test Auth. La chiave privata non va mai salvata su GitHub, su Vercel statico o in una chat.

## Attivazione senza bloccare le iscrizioni clienti

1. Da Safari aprire https://dash.cloudflare.com/ → Turnstile → Add widget. Etichetta: GoodDiner; modalità **Managed**; dominio di produzione `buontavolo.vercel.app`. Aggiungere eventuali host di staging **solo** se vengono effettivamente usati. Conservare la **Secret Key** dentro Cloudflare; annotare la sola Site Key pubblica.
2. Configurare la **Site Key** pubblica nel file `config.js` di GoodDiner, impostando `turnstileSiteKey: "..." `. Nessun'altra configurazione segreta nel repository. Con un Site Key valido, l'interfaccia rende il widget su registrazione cliente, registrazione ristoratore, login, recupero password e reinvio della conferma email.
3. Eseguire `npm test`, fare CI/Preview e pubblicare il frontend che mostra il widget e invia `captchaToken` a Supabase Auth. I form **non** inviano una richiesta quando manca il token dopo l'attivazione.
4. **Subito dopo** abilitare la verifica **server-side** nel progetto Supabase GoodDiner `ixczkhmvbjszgmlqznlk` da https://supabase.com/dashboard/project/ixczkhmvbjszgmlqznlk/auth/protection : Authentication → Bot and Abuse Protection → Enable CAPTCHA protection → Cloudflare Turnstile. Incollare **lì**, e solo lì, la Secret Key e salvare. Le due chiavi devono appartenere allo **stesso widget**.
5. Provare una vera iscrizione cliente con email/password e invito assente, una registrazione ristoratore con invito, login e recupero password dal dominio di produzione e da Safari iPhone. Controllare nel backend che un tentativo Auth **senza captchaToken** venga respinto; in caso contrario, **la protezione non è ancora attiva**. Non pubblicare dati di test reali o segreti nei log.
6. Verificare Supabase Auth rate limits e conferma email. Esaminare l'analytics Cloudflare per errori e token rifiutati.

**Regole:** Turnstile non è una misura sufficiente senza convalida server-side. Il widget genera token a breve durata, monouso; la libreria front-end effettua un reset dopo ciascuna chiamata. Il controllo autorizzazioni ristoratori tramite invito monouso + email confermata + RLS rimane indipendente e non va disattivato.

**Rollback operativo:** se dopo l'attivazione del backend si bloccano tutti gli accessi, controllare prima hostname, Site Key, Secret Key e CSP. Disabilitare temporaneamente CAPTCHA in Supabase Auth solo in caso di malfunzionamento grave e documentare la finestra di esposizione, senza aprire la verifica ristoratori.

Fonti: https://supabase.com/docs/guides/auth/auth-captcha e https://developers.cloudflare.com/turnstile/get-started/server-side-validation/
