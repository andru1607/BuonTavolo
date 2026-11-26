# GoodDiner · Stato di preparazione commerciale — 26/11/2026

**Decisione: NO-GO per lancio commerciale a pagamento fino alla verifica dei blocchi.** Il sito è distribuito per pilota/collaudo, non è una certificazione di operatività commerciale. Preservare tutti gli account, i dati e il dominio attuale; nessuna cancellazione, attivazione live o acquisto di servizi automatico.

## Verificato in questo ciclo
- Repository dedicato `andru1607/BuonTavolo`, progetto Vercel `buontavolo`, target produzione, commit `eccbb553c4f21fd6de9874d3b184eab919ad7ce8`, deploy `dpl_AiGY6qvyFA3n6nsqtuE71tTTgod1` READY.
- Pagina Business aggiornata: accesso a entrambe le anteprime senza login, informazioni su Marketing Kit, agenda, programma Partner, condizioni esplicitamente proposte. La pagina non promette disponibilità commerciale né raccoglie dati.
- Correzione del refresh dello storico dopo conferma di una presenza dalla locandina; controllo della sessione dopo il refresh.
- Controlli mirati di sintassi e sorgente superati: link demo, form lead disabilitato, separazione preview/Auth, guardia sessione dopo conferma. Test completi CI e test fisico Safari non confermati.
- Vercel: nessun errore runtime rilevato nell'ora controllata prima dell'ultimo deploy; questo non copre errori client o Supabase.

## Blocchi e criteri di accettazione
| Area | Evidenza corrente | Accettazione prima del lancio |
|---|---|---|
| Supabase dedicato | Accesso connettore negato a `ixczkhmvbjszgmlqznlk`; solo EasyGart visibile | Riconnettere l'organizzazione corretta; audit read-only, migrazioni e privilegi RLS, backup; mai usare EasyGart |
| Auth | Config browser: clienti email/password senza invito, ristoratori con invito; chiave CAPTCHA vuota | Test effettivo email/recupero/inviti e limiti antiabuso lato server; nessuna apertura aggiuntiva senza verifica |
| Presenze e recensioni | UI e RPC presenti, test simulati effettuati | Test con identità autorizzate distinte, QR scaduto/riutilizzato, check-in locandina, accessi incrociati negati, contestazioni, verifica permessi |
| Condivisione valutazioni | Flag browser disattivato | Revisione giuridica, base giuridica, informativa, scelta specifica revocabile, test server autorizzazioni e audit; non attivare globalmente |
| Stripe | Connettore espone esclusivamente Sandbox, endpoint esistente accetta solo test mode | Conferma soggetto venditore e piano commerciale, account live autorizzato, prodotti/prezzi approvati, checkout e webhook firmati/idempotenti, rinnovi, disdette, fatture, rimborsi, revoche licenze; test senza addebiti reali non richiesti |
| Prezzi | Pagina Business: proposta 39 EUR/mese; Sandbox: 29,90 EUR/mese o 299 EUR/anno | Confermare offerta unica, IVA, condizioni Founders e durata prova; aggiornare documenti e prezzi Stripe coerentemente |
| Lead e assistenza | Form lead disattivato, recapito privacy non configurato | Recapito reale, informativa, sicurezza server, procedure di assistenza e moderazione, retention/diritti, termini e valutazione privacy |
| Hosting | Deploy READY; dominio invariato; piano commerciale non verificato | Verifica piano compatibile con uso commerciale, HTTPS effettivo, link canonico, redirect Auth e capacità/limiti; nessun acquisto automatico |
| QA | Sintassi e test mirati superati | Suite CI completa verde, smoke HTTP sull'origine esistente, prova Safari iPhone e secondo dispositivo con utenti autorizzati; registrare commit e risultati |

## Link operativi
- App: https://buontavolo.vercel.app/
- Business: https://buontavolo.vercel.app/business.html
- Anteprima ristoratore: https://buontavolo.vercel.app/?gd_preview=merchant
- Anteprima cliente: https://buontavolo.vercel.app/?gd_preview=customer
- Supabase GoodDiner: https://supabase.com/dashboard/project/ixczkhmvbjszgmlqznlk
- Stripe: https://dashboard.stripe.com/

Le anteprime sono isolate e non salvano modifiche sul server. Non distribuire QR o inviti dimostrativi. Non inventare verifiche, utenti, ricavi o disponibilità del backend. Non eseguire modifiche distruttive durante il collaudo.
