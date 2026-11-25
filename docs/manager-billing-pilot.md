# GoodDiner: pilot abbonamenti Manager (25/11/2026)
- Accesso tramite https://buontavolo.vercel.app/?billing_test=1, area ristoratore verificato; il server richiede anche operatore Studio, proprietario del locale e email confermata. Nessuna apertura ai clienti reali.
- Checkout ospitato Stripe Sandbox EUR 29,90/mese, ritorno Manager, ripresa checkout aperto, portale di gestione e disdetta. Una sola prova in corso per locale; sessione checkout circa 31 minuti, finestra protezione 35 minuti.
- Licenza simulata calcolata: abbonamento active, pagamento paid, fine periodo futura. Disdetta a fine periodo non la revoca anticipatamente; mancato pagamento o scadenza la rendono non attiva. Nessuna scrittura sulle licenze commerciali.
- SQL con rollback: protezione duplicati, disdetta, pagamento mancato, accesso non autorizzato e licenze commerciali immutate. Il checkout Studio già verificato dal pagamento del 25/11. Manager, portal e rinnovi reali Sandbox ancora da collaudare su iOS/Android.
- Stripe Tax e vendite reali non attivati. Il link di test è esplicito e la protezione è sul server, non sul parametro URL.
