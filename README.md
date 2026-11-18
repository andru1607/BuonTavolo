# BuonTavolo — demo web v4

Web app dimostrativa di reputazione clienti per ristoratori, ottimizzata per iPhone e con interfaccia in italiano.

## Stato reale

**Solo demo.** I dati sono simulati e sono salvati localmente nel browser (localStorage). Non usare con clienti reali: non esistono registrazione, autorizzazione server, database condiviso o note private protette.

## Regole attuali

- Solo il ruolo ristoratore *simulato* pubblica recensioni.
- Voto da 1 a 10 stelle.
- Positiva = 8, 9 o 10 stelle.
- Ogni 10 recensioni positive valide viene emesso un buono demo.
- Le recensioni contestate non entrano nel conteggio dei premi.

## Test locali

Con Node.js: `node test-rating.cjs`. Il test verifica soglia 8/10 e generazione del buono.

## Distribuzione Vercel via GitHub

Importa tutti i file di questa cartella nella radice di un repository GitHub dedicato chiamato `BuonTavolo`. Su Vercel seleziona **Add New > Project > Import Git Repository** e collega `BuonTavolo` con **Framework Preset: Other**. `index.html` è già nella root: non è necessario un build command né variabili d'ambiente. I successivi push sul branch di produzione sono distribuiti automaticamente.

Nessun altro repository deve essere utilizzato. La versione pubblicata è una **demo**, non un prodotto pronto per la gestione reale di recensioni su persone.