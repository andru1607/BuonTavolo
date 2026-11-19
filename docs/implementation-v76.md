# GoodDiner V7.6 · Flussi UX realizzati nella demo

- Primo ingresso: **Accedi / Crea account / Esplora la demo**, senza scelta del ruolo nel primo schermo.
- Crea account: scelta discreta profilo personale o registra ristorante.
- Profilo personale: nickname 3–24 caratteri e codice `GD-XXXXXXXXX`; email e telefono opzionali, **non registrati** nella demo. Ripresa sessione solo locale, non autenticazione.
- DinerPass QR: stringa `GDDEMO1:<token casuale>`, 90 s, valida soltanto nel `localStorage` dello stesso browser, single-use. Non contiene dati personali. QR generato offline (MIT QR encoder).
- Home ristoratore: lettura fotocamera solo quando richiesta se `BarcodeDetector` disponibile; fallback codice manuale. Presenza salvata localmente con timestamp, customerId e ristorante fittizio La Quercia. Anti-duplicati giornaliero.
- Ricerca ristorante: apre Google Maps col nome e la città inseriti, **non è una conferma di esistenza/identità**. Stato di verifica non attivo e nessun account ristoratore reale abilitato.
- Il progetto attuale è una demo statica. Non utilizzare per clienti reali. Tutti i permessi effettivi andranno verificati lato server con backend dedicato, token firmati e monouso, autenticazione passkey e conferma del legittimo operatore commerciale.
- Nessuna modifica alle regole valutazione positiva da 8/10 e voucher ogni 10 positive.

## Necessario per il rilascio vero

1. Backend dedicato GoodDiner; iscrizione anonima con passkey WebAuthn + recupero, regole anti-abuso, ID unico server-side.
2. Provider Places API tramite server con protezione chiavi, limiti e caching consentito; verifica ruolo merchant separata dalla ricerca luogo e processo di ricorso.
3. API check-in transazionale che valida token breve, non prevedibile, monouso e controlla ruoli, ristorante, data e idempotenza.
4. Audit, contestazione presenze, privacy policy, minimizzazione dati e valutazione GDPR.
5. Decodifica QR cross-browser con decoder locale di fallback e prove Safari iOS/Android.