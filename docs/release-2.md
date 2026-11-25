# GoodDiner 2.0 — app operativa, non demo
25 novembre 2026. Ambito: solo repository andru1607/BuonTavolo e progetto GoodDiner.
- Identità unica Plum & Pastel. Nessun pattern; design mobile-first, testi principali 16px, controlli 44–48px o più, stato testuale e focus visibile.
- Home collegata a Supabase reale. Demo e account legacy conservati per test, ma le due pagine pubbliche reindirizzano alla home.
- DinerPass: simbolo originale incorporato localmente al centro del QR, correzione H, quiet zone di 4 moduli, protezione dei pattern di allineamento e token invariato. Codice manuale resta disponibile.
- I DinerPass Editions non vengono offerti in vendita finché non esistono checkout live, verifica webhook, proprietà persistente lato server, informativa/prezzi/condizioni e prova di acquisto/rimborso. L'attuale Stripe è un laboratorio test per il gestore, non una prova di vendita live.
- Signup cliente attualmente email/password, invito per ristoratore. La configurazione client attuale ha Turnstile non impostato e valutazioni personali/premi disabilitati. Non cambiare questi gate per chiamare il prodotto ufficiale.
- Test automatici e risultati deployment da verificare sulla specifica revisione. Test iPhone/VoiceOver e prova QR fotocamera con account autorizzati restano necessari; nessuna certificazione dichiarata.
- Privacy, gestione contestazioni, assistenza, condizioni di acquisto e titolarità commerciale devono essere verificati prima della diffusione pubblica e di addebiti reali.
