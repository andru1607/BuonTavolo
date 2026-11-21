# GoodDiner · Tutela delle persone e gestione delle richieste privacy

**Documento operativo e di progettazione, NON informativa legale definitiva.** Versione 21/11/2026. Prima di aprire la piattaforma a clienti e ristoranti serve un titolare del trattamento identificato, una valutazione giuridica e l'approvazione delle informazioni da pubblicare.

## Dati, finalità e rischi da valutare

| Elemento | Origine | Impiego previsto | Principali rischi |
| --- | --- | --- | --- |
| Nickname e codice DinerPass | Cliente | Identificare il profilo | Collegabilità tra locali e riconoscimento indiretto |
| Email confermata | Supabase Auth | Login/recupero | Accesso non autorizzato, perdita account |
| QR `GD1:` e momento visita | Server e gestore verificato | Dimostrare una singola presenza | Tracciamento degli spostamenti e abusi |
| Recensione 1–10 e commento | Ristoratore verificato | Feedback sulla visita | Danno reputazionale, discriminazione, trattamenti inaccurati |
| Contestazioni, audit e richieste privacy | Interessato/operatore | Garanzie, verifica e gestione diritti | Conservazione eccedente e accessi impropri |
| Eventuali log di rete | Fornitori infrastrutturali | Sicurezza | Identificazione/retention non controllata |

I **voti assegnati alle persone** meritano un controllo particolarmente rigoroso: una visita effettiva non rende automaticamente lecito qualsiasi giudizio. Vietare informazioni su salute, origine, convinzioni, orientamento, minori, accuse non verificate, caratteristiche sensibili e dati non necessari. Evitare graduatorie pubbliche e decisioni di esclusione automatiche basate sui voti, salvo verifica legale e garanzie appropriate.

## Informazioni da completare prima di pubblicare l'informativa

- [ ] Denominazione, indirizzo e contatto effettivo del titolare del trattamento: **NON FORNITI**, da definire con la documentazione societaria.
- [ ] Recapito dedicato a privacy/reclami accessibile anche a ex utenti, non basato soltanto sul login: **NON CONFIGURATO**.
- [ ] Base giuridica articolo 6 per **ogni** operazione: account, presenze, recensioni sul cliente, premi, moderazione. Non presumere che il check-in sia consenso generale a una reputazione.
- [ ] Informativa articoli 13–14, origine dei dati e destinatari; se i commenti sono scritti da terzi, valutare gli obblighi di informazione per dati non ottenuti direttamente.
- [ ] Accordo DPA e regioni/subprocessor per Supabase, Vercel e Cloudflare se attivato; trasferimenti extra-UE, sicurezza e log.
- [ ] Tempi di conservazione verificabili per token QR, visite, recensioni, contestazioni, audit e richieste. **Non impostare una pulizia automatica senza criteri approvati**.
- [ ] Valutazione dei rischi DPIA, da svolgere prima del trattamento quando necessaria, soprattutto considerando scoring di persone e possibili effetti discriminatori.
- [ ] Processo umano per contestazioni e revisione delle recensioni, tempi e priorità; chi può accedere ai dati e con quali controlli.
- [ ] Regole per minorenni, sospensioni e prevenzione di contenuti diffamatori o discriminatori; sicurezza account e data breach.
- [ ] Verifica finale della dicitura sui premi: i voucher sono **non riscattabili** finché manca un accordo commerciale.

Fonti di partenza: [Garante, privacy by design](https://www.garanteprivacy.it/home/principi-fondamentali-del-trattamento), [Garante, valutazione DPIA](https://www.garanteprivacy.it/it/valutazione-d-impatto-della-protezione-dei-dati-dpia-), [Regolamento UE 2016/679](https://eur-lex.europa.eu/eli/reg/2016/679/oj).

## Richieste dell'interessato: sistema predisposto

Da **Profilo → Privacy · Diritti**, l'utente autenticato può:

1. Scaricare un archivio JSON delle informazioni che lo riguardano, con paginazione delle visite, recensioni, contestazioni, voucher e richieste. L'archivio viene generato nel browser; non viene caricato su server terzi. Il browser può scaricarlo sul dispositivo, quindi l'utente deve custodirlo.
2. Inviare un'istanza di accesso, rettifica, cancellazione, limitazione o opposizione. Descrizione facoltativa fino a 500 caratteri; avviso di non inserire informazioni sensibili.
3. Vedere lo stato: ricevuta, in valutazione, conclusa oppure respinta.
4. Una sola istanza aperta per tipologia, con vincolo anche nel database.

L'invio **non** elimina account, visite, commenti o audit automaticamente. Le richieste richiedono verifica umana: un diritto di cancellazione può prevedere eccezioni e non deve danneggiare i diritti altrui o gli obblighi legali. Una richiesta `resolved` può essere marcata soltanto *dopo* che l'operatore ha realmente adempiuto e comunicato l'esito.

Il modulo web autenticato **non sostituisce** un canale esterno accessibile a chi ha perso la sessione o ha già eliminato il proprio account. Questo canale resta un blocco al lancio.

## Operatore: solo editor SQL protetto

[Console SQL progetto GoodDiner](https://supabase.com/dashboard/project/ixczkhmvbjszgmlqznlk/sql). Non trasferire in GitHub email, password, documenti d'identità, commenti integrali o prove riservate.

Elenco delle richieste:

```sql
select r.id,r.requester_id,r.request_kind,r.created_at,r.status,r.details
from public.privacy_requests r
where r.status in ('received','in_review')
order by r.created_at asc;
```

Dopo istruttoria e adempimento reale:

```sql
select gd_private.close_privacy_request(
  '00000000-0000-0000-0000-000000000000'::uuid,
  true,
  'operatore-autorizzato',
  'Adempimento eseguito e risposta comunicata nel canale protetto previsto.'
);
```

Usare `false` solo per una richiesta motivatamente respinta. La funzione non concede all'operatore privilegi automatici per cancellare persone o documenti; registra status e una decisione nell'audit `gd_private.operator_audit`.

**Prove richieste per ogni caso:** richiesta identificata, verifica identità proporzionata, base e motivazione della decisione, azioni realmente eseguite, comunicazione all'interessato, data e identificativo dell'incaricato. Definire separatamente le procedure tecniche per accesso, rettifica, anonimizzazione, cancellazione e conservazione legale, con supporto competente.

## Stato operativo

- [x] RLS e grant limitati su `public.privacy_requests`.
- [x] Routine amministrativa SQL senza API client; audit delle decisioni.
- [x] UI profilo per invio e monitoraggio; export personale via SDK con filtro per `auth.uid()` e paginazione.
- [ ] Responsabile privacy individuato; contatti e istruttoria formalizzati.
- [ ] Verifica legale, DPIA e informativa completate.
- [ ] Test con utenti veri e gestione di una richiesta autentica eseguiti e documentati.

Questa checklist distingue codice esistente e responsabilità operative non ancora assunte.
