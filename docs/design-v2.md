# GoodDiner · Design 2.0, restyling iPhone-first

**Stato:** modifiche visive implementate nel codice e nella demo, test automatici previsti su PR. Non significa che il sito sia pubblicato; verificare GitHub Actions, URL HTTPS canonico e Safari reale. Nessuna variazione a database, ruoli, registrazione o pagamenti.

## Direzione visiva

Un'identità da prodotto digitale per la ristorazione, non una raccolta di pagine scollegate. Il pass verde petrolio è l'elemento riconoscibile; la crema calda è lo sfondo, la terracotta è riservata alle azioni e ai piccoli accenti, non a ogni pulsante.

| Componente | Colore | Uso |
|---|---|---|
| Verde petrolio | `#103D37` | Identità, dashboard, pulsanti principali, DinerPass |
| Verde intermedio | `#1B5A50` | Stati hover e profondità |
| Crema | `#F5F4EE` | Sfondo |
| Bianco caldo | `#FFFEFA` | Schede e superfici |
| Testo | `#1B2925` | Testo principale, contrasto elevato |
| Grigio verde | `#68766F` | Descrizioni, indicazioni secondarie |
| Terracotta | `#B95B43` | CTA e piccoli accenti |
| Oro tenue | `#D9B878` | Dettagli grafici non essenziali |

Font principali: tipografia di sistema leggibile per UI e testo; Georgia per i titoli editoriali e le cifre principali. Nessun download di font esterno. Angoli, ombre e bordi omogenei; nessuna immagine di stock o dato dimostrativo spacciato come reale.

## Schermate interessate

**Home ufficiale:** hero verde con luci discrete, titoli editoriali, una card DinerPass decorativa sul desktop, CTA differenziata tra cliente e ristoratore, registrazioni ancora chiuse se il gate di release è disattivato. Viene chiarito che valutazioni di persone e premi non sono attivi nel pilota.

**DinerPass:** messaggio di benvenuto più compatto, pass leggibile con codice cliente, pannello QR con spiegazione privacy corrispondente alle funzionalità attive, colore e gerarchia chiari. Il QR, la validità di 90 secondi, il codice manuale e l'azione di generazione restano invariati.

**Dashboard ristoratore:** intestazione aziendale, azione di scansione, blocco di accesso non attivo e metriche reali più leggibili. Nessun dato demo o licenza inventati. Le informazioni di stato provengono dalle RPC esistenti.

**Navigazione mobile:** 4 pulsanti massimo per il cliente e 3 per il ristoratore, icona più testo, stato attivo evidente, safe-area iPhone, dimensioni di tocco adeguate e barra flottante. Il passaggio tra ruoli rimane nell'intestazione, non aggiunge una quinta voce.

**Business:** stesso linguaggio visivo del prodotto, maggiore enfasi su prova, prezzo e funzioni effettive. Il modulo contatti resta chiuso per impostazione predefinita e non accetta pagamenti.

**Demo:** foglio `demo-design-v2.css` separato che allinea palette, navigazione, pannelli e schede visive del prototipo senza cambiare logica, profili fittizi, storage o simulatori legacy. Va comunque etichettata come demo e non come servizio attivo.

## Accessibilità e prestazioni

- Tutti i tab mobile mantengono etichette testuali visibili e `aria-current="page"` sul tab selezionato. Le icone SVG sono nascoste ai lettori di schermo, perché ridondanti.
- Un test CI calcola il contrasto dei principali accoppiamenti testo/sfondo: obiettivo WCAG AA almeno 4,5:1.
- Font input almeno 16px come nel CSS originale, così Safari non effettua zoom involontario.
- Schede e statistiche usano `minmax(0,1fr)`, dimensioni responsive e safe-area; breakpoint dedicato a schermi da 360px o meno.
- Rispettare `prefers-reduced-motion`, nessuna animazione obbligatoria e nessun caricamento di immagini/font da provider terzi.
- Il service worker incrementa il proprio cache key e include i nuovi fogli CSS. Sessioni, token, contenuto utenti e risposte Supabase restano esclusi dalla cache.

## Checklist per verifica umana su iPhone

- [ ] Home con e senza login: titolo leggibile, CTA non tagliate a 320/375/390/430px e su Safari con testo ingrandito.
- [ ] Cliente reale: card, QR, countdown, stato scaduto, codice manuale, nessun testo che prometta voti attualmente disabilitati.
- [ ] Ristoratore reale verificato e con trial attivo: panoramica, nav 3 voci, scansione e registrazione visite.
- [ ] Ristoratore non verificato e licenza scaduta: informazioni e CTA senza accesso ingannevole.
- [ ] Safari tastiera aperta: campi di registrazione, scanner e finestra modale navigabili.
- [ ] Android/Chrome e desktop Safari/Chrome: layout e contrasto, tab mobile solo sul breakpoint previsto.
- [ ] Eseguire `scripts/live-smoke.mjs` su URL pubblico verificato; controllare che `/design-v2.css` e `/demo-design-v2.css` siano serviti dal commit attuale. Senza URL, il test live non si considera superato.

## Perimetro

In questa modifica **nessuna operazione SQL, nessuna registrazione aperta, nessun pagamento attivato** e nessuna nuova funzione che usi dati personali. Le schermate reali continuano a leggere il database GoodDiner dedicato.

I problemi di pubblicazione Vercel sono tracciati in [issue #28](https://github.com/andru1607/BuonTavolo/issues/28); lo stato generale in [issue #10](https://github.com/andru1607/BuonTavolo/issues/10).
