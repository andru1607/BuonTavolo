# GoodDiner Business · Offerta pilota e percorso verso i primi incassi

**Stato:** pacchetto tecnico predisposto, **non ancora vendibile come servizio attivo**. Controllo del 22/11/2026. Progetto GoodDiner Supabase `ixczkhmvbjszgmlqznlk`. Non coinvolgere Gartenarte, DopoTurno, SINDRU o altri database.

## Prodotto minimo da vendere

**Cliente pagante:** ristorante, non il cliente finale. **Offerta pilota proposta:** 39 € al mese per singolo locale, IVA esclusa quando dovuta, senza costo d'attivazione. **Prova:** 14 giorni soltanto dopo la verifica umana del titolare. Nessuna carta chiesta per la prova in questo stato di preparazione. Il prezzo è una decisione di posizionamento iniziale da confermare con documentazione fiscale e condizioni contrattuali, non una promessa di vendite.

Funzioni già presenti nella web app: QR DinerPass di 90 secondi monouso, check-in confermato sul server, registro con storico/paginazione, conteggi reali di presenze, annullamento motivato con audit, area titolare separata da quella del cliente. Un ristorante deve essere verificato e autorizzato; anche i clienti necessitano di un DinerPass e della relativa autenticazione. **Non vendere funzionalità che non esistono**: POS, campagne SMS, invio automatico email, prenotazioni, CRM con contatti, accesso multi-dipendente, voucher riscattabili o recensioni pubbliche.

Le **recensioni dei clienti come persone** restano chiuse: il server verifica `gd_private.business_features.personal_reviews_enabled=false` e risponde con `RECENSIONI_PERSONALI_NON_ATTIVE` anche se qualcuno aggira la UI. La protezione è una scelta intenzionale per anticipare un pilota sulle presenze senza mettere in commercio il punteggio di persone prima di una verifica giuridica.

## Licenze e prova

La migrazione `database/gooddiner_business_pilot.sql` crea un registro privato `gd_private.merchant_licenses`, un audit, e l'interruttore delle recensioni personali.

1. Quando un operatore approva davvero una domanda attraverso `gd_private.review_merchant_application(...)`, viene creato un locale verificato e automaticamente un accesso **trialing per 14 giorni**. La creazione di domanda, un locale trovato online o un account cliente **non** concedono un abbonamento.
2. La RPC `checkin_guest` richiede oltre al titolare verificato un accesso `trialing` o `active` che non sia scaduto. Se scade, non permette nuove scansioni e le visite già registrate restano leggibili dall'utente autorizzato. L'operatore può comunque correggere le presenze esistenti tramite il flusso di annullamento tracciato.
3. L'app legge `get_my_merchant_license(p_restaurant_id)`, che mostra stato e scadenza **soltanto al titolare**. Nessun utente può modificare direttamente la licenza, lo stato del pagamento o la data.
4. Una licenza attiva deve essere **registrata dall'operatore solo dopo aver verificato il pagamento realmente riuscito nel proprio Stripe**. Attualmente non esistono checkout, fatture o addebiti live collegati al progetto. Non usare ritorni da URL, email del cliente, screenshot o campi del browser come conferma di pagamento.

### Attivazione manuale dopo una transazione confermata

Da [Supabase SQL Editor GoodDiner](https://supabase.com/dashboard/project/ixczkhmvbjszgmlqznlk/sql), dopo aver verificato identità del ristorante, contratto, fatturazione e pagamento nella dashboard dell'account Stripe effettivo:

```sql
-- Prima individuare il locale nel proprio progetto.
select id,name,owner_id,verified_at
from public.restaurants order by created_at desc limit 20;

-- Solo su un UUID reale verificato, sostituendo tutti i valori segnaposto:
select gd_private.set_merchant_license(
  'INSERIRE-UUID-RISTORANTE'::uuid,
  'active',
  now()+interval '1 month',
  'operatore-identificato',
  'Pagamento verificato nella dashboard Stripe e abbonamento concordato'
);
```

Non eseguire il comando con il segnaposto. La procedura lascia audit (non memorizza carta, password o segreto Stripe). Per sospendere si usa la stessa funzione con `p_status='suspended'`, data e motivazione, dopo la valutazione dei diritti contrattuali applicabili. Il codice non genera fatture e non verifica automaticamente rinnovi, mancati pagamenti o rimborsi: **i rinnovi sono manuali** finché non viene integrato e testato un webhook Stripe firmato e idempotente.

## Percorso più rapido per incassare con un servizio verificato

1. **Dominio:** risolvere [blocco Vercel](https://github.com/andru1607/BuonTavolo/issues/28) e scegliere una sola origine HTTPS verificata. Non acquistare un piano Vercel automaticamente. Eseguire smoke del commit effettivamente pubblicato.
2. **Società e fiscalità:** confermare soggetto venditore, titolo fiscale, condizioni B2B, fatturazione IVA, politica rinnovi/cancellazione e contatto di assistenza. Un account Stripe verificato **non sostituisce** questi adempimenti.
3. **Privacy proporzionata alle visite:** approvare informativa per clienti e ristoratori, base giuridica per visite/identità, conservazione, diritti, accordi con fornitori e misura di sicurezza. Non attivare punteggi delle persone. Configurare SMTP, email, redirect e Turnstile **anche sul server Supabase Auth**. Test con persone autorizzate, non con ospiti reali inconsapevoli.
4. **Vendita iniziale 1 a 1:** contattare personalmente poche attività locali e mostrare `/business.html` e `/demo.html`. La demo contiene dati simulati e va presentata come tale. Raccogliere adesioni soltanto tramite un recapito commerciale/strumento approvato.
5. **Pagamenti:** collegare Stripe e attivare un prodotto ricorrente da 39 €/mese più imposte appropriate o inviare un link di pagamento/una fattura dal conto del soggetto venditore, mai direttamente dalla demo. Confermare nel pannello Stripe la transazione andata a buon fine, quindi attivare la licenza manualmente. Non abilitare un link di pagamento pubblico prima che il servizio sia realmente erogabile.
6. **Dopo le prime vendite:** integrare Stripe Checkout e webhook con firma verificata, deduplicazione e gestione di `invoice.paid`, rinnovi, scadenze, cancellazioni e rimborsi, così l'attivazione diventa automatica. Non inserire in GitHub `sk_live_`, `whsec_` o altre chiavi private.

## Contatti commerciali senza registrare dati troppo presto

La pagina `/business.html` presenta il prezzo e le funzioni con una **chiara indicazione di programma pilota**. Il form è chiuso finché `businessLeadIntakeEnabled:false`. Il backend tecnico è pronto in `supabase/functions/business-pilot-lead/index.ts`, ma i segreti e il dominio legittimo non sono configurati.

Il form può essere aperto **soltanto dopo** una informativa dedicata alla richiesta commerciale approvata, un URL HTTPS reale, protezione Turnstile e gestione della cancellazione dei dati:

- `GOODDINER_CANONICAL_ORIGIN`: esatto dominio canonico HTTPS; la funzione rifiuta origini diverse
- `GOODDINER_LEAD_TURNSTILE_SECRET`: secret Cloudflare nel vault **Supabase**, mai nel browser
- `GOODDINER_LEAD_RATE_SALT`: stringa privata casuale almeno 32 caratteri, nel vault, usata per limitare i tentativi senza memorizzare IP in chiaro
- Il client deve conoscere soltanto `turnstileSiteKey` pubblica, `businessPrivacyUrl` HTTPS e `businessLeadIntakeEnabled:true` in `config.js`
- Abilitare `supabase/config.toml` con `verify_jwt=false` per la Edge Function **soltanto** perché la verifica Turnstile viene fatta obbligatoriamente sul server. Se manca un parametro la funzione risponde `503` e non raccoglie contatti.

La tabella `public.business_pilot_leads` ha RLS, nessuna policy/grant per `anon` o `authenticated`: solo server autorizzato può scrivere. Conserva **nome locale, città ed email di contatto**, data e hash di rate-limit, non dati degli ospiti. La scadenza `delete_after` a 90 giorni è una **data per l'operatore**, non elimina automaticamente i dati. Prima di aprire il form va attivata una cancellazione verificabile e scegliere il periodo di conservazione con il titolare.

Esempio di intervento manuale sul database autorizzato (da automatizzare e auditare prima del go-live del form):

```sql
select count(*) from public.business_pilot_leads
where delete_after < now();

-- Eseguire dopo approvazione della retention e verifica dei backup:
-- delete from public.business_pilot_leads where delete_after < now();
```

Non accettare documenti, informazioni sensibili dei clienti, dati sanitari o numeri di carta nel modulo contatti.

## Test e condizioni di successo

- [x] Il frontend mostra il business pilot senza pubblicare prezzi inventati come incassi reali.
- [x] Il codice protegge l'abilitazione delle licenze e delle recensioni personali sul server.
- [ ] Migrazione business applicata e test SQL transazionale superato.
- [ ] Test reale di rilascio su dominio canonico con traffico HTTPS e Safari iPhone.
- [ ] Cliente + ristoratore volontari: sessione verificata, check-in reale, scadenza prova, accesso incrociato negato, modulo privacy funzionante.
- [ ] Stripe verificato, prodotto attivo, checkout reale e pagamento correttamente registrato con fattura.
- [ ] Contatto commerciale funzionante, privacy approvata, CAPTCHA server-side, retention effettiva.
- [ ] Almeno un locale che usa l'app durante il servizio e segnala un beneficio misurabile, con feedback non inventato.

**Criterio:** la prima vendita si può dichiarare soltanto dopo un pagamento confermato e un servizio effettivamente erogato. Un prezzo in pagina, un test verde e una PR unita non sono ricavi.
