/* GoodDiner V7.6 · public access and local-only QR demo. Not authentication or server check-in. */
'use strict';
(() => {
  ICON.scan='<path d="M7 3H4a1 1 0 0 0-1 1v3M17 3h3a1 1 0 0 1 1 1v3M3 17v3a1 1 0 0 0 1 1h3M21 17v3a1 1 0 0 1-1 1h-3M6 12h12"/>';
  ICON.shield='<path d="M12 2 4 6v6c0 5 4 8 8 10 4-2 8-5 8-10V6z"/><path d="m9 12 2 2 4-4"/>';
  ICON.close='<path d="M18 6 6 18M6 6l12 12"/>';
  const SESSION_KEY = 'gooddiner-demo-session-v76';
  const QR_KEY = 'gooddiner-demo-token-v76';
  const DEMO_VISITS = 'gooddiner-demo-attendance-v76';
  const VENUE_KEY = 'gooddiner-demo-venue-v76';
  const HTML = value => esc(value);
  let step = 'landing';
  let scannedPreview = '';
  let searchOpened = false;
  let cameraStream = null;
  let cameraGeneration = 0;
  let latestScan = '';
  const session = () => {
    try {const x=JSON.parse(localStorage.getItem(SESSION_KEY)||'null'); return x && typeof x==='object' ? x : null;} catch {return null;}
  };
  const saveSession = data => {try{localStorage.setItem(SESSION_KEY,JSON.stringify(data));}catch{}};
  const readLocal = (key, fallback) => {try {return JSON.parse(localStorage.getItem(key)||'null')||fallback;} catch{return fallback;}};
  const saveLocal = (key,data) => {try{localStorage.setItem(key,JSON.stringify(data));return true;}catch{return false;}};
  const existing=session();
  if (existing?.role==='customer' && customer(existing.customerId)) {
    state.role='customer';state.tab='home';db.activeCustomer=existing.customerId;state.welcome=false;
  } else if(existing?.role==='restaurant' || existing?.role==='preview'){
    state.role=existing.role==='restaurant'?'restaurant':'customer';state.tab='home';state.welcome=false;
  } else {state.welcome=true;}

  const originalHeader = header;
  const originalClientHome = clientHome;
  const originalClientProfile = clientProfile;
  const originalMerchantHome = merchantHome;
  const originalSwitchRole = switchRole;

  const logo = (size=50) => `<img src="/icons/mark-light.svg" width="${size}" height="${size}" alt="" loading="eager">`;
  const backButton = destination => `<button type="button" class="gd-text-link" data-gd-entry="${destination}">Indietro</button>`;
  const formField = (id,label,placeholder,required=false,type='text') => `<label class="gd-field"><span>${label}${required?' <b aria-label="obbligatorio">*</b>':''}</span><input id="${id}" name="${id}" type="${type}" ${required?'required':''} placeholder="${placeholder}" maxlength="${id==='gd-nick'?24:80}" autocomplete="off"></label>`;
  function landing(){
    return `<div class="gd-landing">
      <div class="gd-brand">${logo(54)}<span>GoodDiner</span></div>
      <div class="gd-opening"><span class="gd-kicker">LA REPUTAZIONE È PERSONALE</span><h1>Ogni esperienza<br><em>lascia il segno.</em></h1><p>Un'identità che ti accompagna. Le tue visite, la tua reputazione e i riconoscimenti che meriti.</p></div>
      <div class="gd-open-actions"><button class="gd-primary" data-gd-entry="signin">Accedi <span aria-hidden="true">›</span></button><button class="gd-outline" data-gd-entry="signup">Crea un account</button><button class="gd-text-link" data-gd-entry="preview">Esplora la demo senza registrarti</button></div>
      <div class="gd-landing-foot">Anteprima dimostrativa · Nessun account reale attivo</div>
    </div>`;
  }
  function chooseSignup(){
    return `<div class="gd-form-frame"><div class="gd-kicker">NUOVO PROFILO</div><h1>Cominciamo da te.</h1><p>Come vuoi utilizzare GoodDiner?</p>
    <button class="gd-pick" data-gd-entry="customer"><span class="gd-pick-icon">${icon('user',25)}</span><span><strong>Il mio profilo personale</strong><small>Nickname, DinerPass e riconoscimenti.</small></span>${icon('arrow',19)}</button>
    <button class="gd-pick" data-gd-entry="merchant"><span class="gd-pick-icon">${icon('settings',24)}</span><span><strong>Registro un ristorante</strong><small>Identità del locale e gestione visite.</small></span>${icon('arrow',19)}</button>
    ${backButton('landing')}</div>`;
  }
  function customerSignup(){
    return `<div class="gd-form-frame"><div class="gd-kicker">ACCOUNT PERSONALE · DEMO</div><h1>Il tuo DinerPass inizia qui.</h1><p>Scegli un nickname. Email e telefono non sono necessari per creare questa anteprima.</p>
    <form id="gd-create-customer" class="gd-fields">${formField('gd-nick','Nickname','Es. marco_27',true)}
    ${formField('gd-email','Email (facoltativa)','nome@esempio.it',false,'email')}
    ${formField('gd-phone','Telefono (facoltativo)','+39 ...',false,'tel')}
    <div class="gd-security-note">${icon('shield',19)} <span>Il tuo ID cliente sarà generato automaticamente. Email e telefono non vengono salvati in questa demo. L'accesso reale richiederà una passkey o un altro metodo sicuro.</span></div>
    <button class="gd-primary" type="submit">Crea il mio profilo demo ${icon('arrow',17)}</button></form>${backButton('signup')}</div>`;
  }
  function merchantSignup(){
    return `<div class="gd-form-frame"><div class="gd-kicker">PER I RISTORATORI · DEMO</div><h1>Troviamo il tuo locale.</h1><p>Inserisci nome e città per consultare la sua presenza online. La verifica del gestore è un passaggio separato.</p>
    <form id="gd-create-merchant" class="gd-fields">
    ${formField('gd-venue-name','Nome ristorante','Es. Trattoria dei Tigli',true)}
    ${formField('gd-venue-city','Città','Es. Verona',true)}
    <button type="button" class="gd-outline gd-search-button" data-gd-entry="maps">${icon('search',19)} Cerca il locale su Google Maps</button>
    <div class="gd-security-note">${icon('info',19)} <span>La ricerca si apre su Google Maps. Non possiamo verificare automaticamente chi gestisce il locale senza un servizio dedicato. La registrazione reale resterà in attesa di verifica.</span></div>
    <button class="gd-primary" type="submit">Continua nell'anteprima ristoratore ${icon('arrow',17)}</button></form>${backButton('signup')}</div>`;
  }
  function signin(){
    const saved=session();const canResume=!!saved;
    return `<div class="gd-form-frame"><div class="gd-kicker">IL TUO SPAZIO</div><h1>Bentornato.</h1><p>Accedi al tuo profilo GoodDiner. Nella demo non è ancora disponibile un'autenticazione reale.</p>
    <div class="gd-signin-card">${icon('fingerprint',34)}<strong>Accesso con passkey</strong><small>In preparazione per la versione con backend protetto.</small><button class="gd-outline" type="button" disabled>Continua con passkey</button></div>
    ${canResume?`<button class="gd-primary" data-gd-entry="resume">Riprendi la sessione demo ${icon('arrow',16)}</button>`:`<button class="gd-primary" data-gd-entry="preview">Entra nel profilo dimostrativo ${icon('arrow',16)}</button>`}
    ${backButton('landing')}</div>`;
  }
  function gate(){
    const body={landing,signup:chooseSignup,customer:customerSignup,merchant:merchantSignup,signin}[step]||landing;
    return `<main class="gd-gate" aria-label="Ingresso GoodDiner"><div class="gd-gate-art" aria-hidden="true"><span></span><span></span></div>${body()}</main>`;
  }
  header = function(){
    if(state.welcome)return gate();
    return originalHeader().replaceAll('Cambia modalità','Cambia vista demo');
  };

  function tokenData(){
    const active=customer(db.activeCustomer);
    if(!active)return null;
    const now=Date.now();let obj=readLocal(QR_KEY,null);
    if(!obj||obj.customerId!==active.id||!obj.token||obj.expires<=now){
      obj={customerId:active.id,token:'GDDEMO1:'+rand(18),expires:now+90000};saveLocal(QR_KEY,obj);
    }
    return obj;
  }
  function qrHTML(t=tokenData()){
    if(!t)return '<p>Non è disponibile un profilo demo.</p>';
    const qr=window.GoodDinerQR?.svg(t.token)||'<div>QR non disponibile</div>';
    return `<div class="gd-qr-visual" aria-label="QR del DinerPass" data-qr-token="${HTML(t.token)}">${qr}</div><div class="gd-qr-expiry">QR temporaneo dimostrativo · aggiornamento ogni 90 secondi</div>`;
  }
  function guestQR(){
    return `<section class="gd-qr-section" aria-labelledby="gd-qr-head"><div class="gd-qr-copy"><span class="gd-kicker">IL TUO DINERPASS</span><h2 id="gd-qr-head">Il tuo ingresso, un solo gesto.</h2><p>Mostra il QR personale al ristoratore: nella versione completa registrerà la tua presenza. Questo QR è utilizzabile solo nella simulazione locale.</p><span class="gd-qr-code">${HTML(customer(db.activeCustomer)?.id||'')}</span></div>
    <div class="gd-qr-side"><div id="gd-qr-viewport">${qrHTML()}</div><button type="button" data-gd-entry="copy-qr" class="gd-outline gd-qr-copybtn">${icon('copy',17)} Copia il codice QR demo</button><details class="gd-manual-code"><summary>Mostra codice manuale</summary><code>${HTML(tokenData()?.token||'')}</code></details></div></section>`;
  }
  clientHome = function(){
    const original=originalClientHome();
    return original.replace('<section class="reward-feature">',guestQR()+'<section class="reward-feature">');
  };
  clientProfile = function(){
    const original=originalClientProfile();
    return guestQR()+original+`<button type="button" class="gd-text-link gd-logout" data-gd-entry="logout">Esci dalla demo</button>`;
  };
  const visits=()=>{const entries=readLocal(DEMO_VISITS,[]);return Array.isArray(entries)?entries.filter(x=>x&&typeof x==='object'):[];};
  function visitList(){
    const rows=visits().slice(0,5);
    return rows.length?rows.map(v=>`<div class="gd-visit-row"><div><b>${HTML(v.nickname)}</b><small>${HTML(v.customerId)} · ${HTML(new Date(v.at).toLocaleString('it-IT',{day:'2-digit',month:'short',hour:'2-digit',minute:'2-digit'}))}</small></div><span>Confermata · demo</span></div>`).join(''):'<p class="gd-visit-empty">Nessuna presenza registrata nella demo. Prova a scansionare il DinerPass di un cliente creato su questo dispositivo.</p>';
  }
  function merchantScanner(){
    const venue=readLocal(VENUE_KEY,null);
    return `<section class="gd-scanner-section"><div class="gd-scanner-head"><div><span class="gd-kicker">PRESENZE · ANTEPRIMA</span><h2>Accogli un ospite.</h2><p>Scansiona il suo DinerPass e registra una presenza.</p></div><div class="gd-scanner-mark">${icon('scan',29)}</div></div>
    ${venue?`<div class="gd-venue-pill">${icon('info',15)} ${HTML(venue.name)} · ${HTML(venue.city)} · Verifica non attiva</div>`:''}
    <button class="gd-primary gd-scan-launch" type="button" data-gd-entry="scan">${icon('scan',20)} Scansiona DinerPass</button>
    <div class="gd-visit-title"><strong>Visite registrate nella demo</strong><span>${visits().length}</span></div>${visitList()}
    <p class="gd-privacy-line">Solo questa sessione browser. Nessuna scansione crea una presenza nel database reale.</p></section>`;
  }
  merchantHome = function(){
    return originalMerchantHome().replace('<section class="merchant-feature',merchantScanner()+'<section class="merchant-feature');
  };
  switchRole = function(next){stopCamera();const target=next||(state.role==='customer'?'restaurant':'customer');saveSession({role:target==='restaurant'?'restaurant':'customer',customerId:db.activeCustomer});return originalSwitchRole(next);};

  function scanPanel(){
    return `<div class="gd-scan-overlay" role="dialog" aria-modal="true" aria-labelledby="gd-scan-title"><div class="gd-scan-modal"><div class="gd-scan-top"><div><span class="gd-kicker">REGISTRA PRESENZA</span><h2 id="gd-scan-title">Scansiona DinerPass</h2></div><button class="gd-icon-close" aria-label="Chiudi" data-gd-entry="close-scan">${icon('close',22)}</button></div>
    <p>Inquadra il QR mostrato dal cliente oppure inserisci il codice demo. È necessario che i profili siano nello stesso browser.</p>
    <div id="gd-camera-box" class="gd-camera-box"><div class="gd-camera-idle">${icon('scan',36)}<span>La fotocamera si attiverà solo quando la richiedi.</span></div></div>
    <button type="button" class="gd-outline" data-gd-entry="camera">${icon('scan',18)} Attiva fotocamera</button>
    <form id="gd-scan-manual" class="gd-manual-form"><label for="gd-manual-token">Codice QR demo (alternativa)</label><div><input id="gd-manual-token" name="token" placeholder="GDDEMO1:..." required autocapitalize="off" autocomplete="off" spellcheck="false"><button class="gd-primary" type="submit">Verifica</button></div></form>
    <p id="gd-scan-result" class="gd-scan-result" role="status"></p>
    <p class="gd-privacy-line">La lettura non equivale a una verifica reale. Il check-in sicuro richiederà un server.</p></div></div>`;
  }
  function closeScanner(){
    stopCamera();
    const overlay=document.querySelector('.gd-scan-overlay');
    if(!overlay)return;
    const reduced=window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
    if(reduced){overlay.remove();}else{overlay.classList.add('gd-leaving');window.setTimeout(()=>overlay.remove(),170);}
    document.querySelector('.gd-scan-launch')?.focus({preventScroll:true});
  }
  function stopCamera(){
    cameraGeneration++;
    cameraStream?.getTracks().forEach(track=>track.stop());
    cameraStream=null;
  }
  async function startCamera(){
    const box=document.getElementById('gd-camera-box');if(!box)return;
    if(!navigator.mediaDevices?.getUserMedia||!window.BarcodeDetector){
      box.textContent='Scansione non disponibile. Inserisci il codice manuale del DinerPass.';return;
    }
    stopCamera();
    const generation=cameraGeneration;
    const active=()=>generation===cameraGeneration;
    try{
      const detector=new window.BarcodeDetector({formats:['qr_code']});
      const stream=await navigator.mediaDevices.getUserMedia({video:{facingMode:'environment'},audio:false});
      if(!active()){stream.getTracks().forEach(track=>track.stop());return;}
      cameraStream=stream;
      box.innerHTML='<video autoplay playsinline muted aria-label="Anteprima fotocamera per la lettura QR"></video>';
      const video=box.querySelector('video');video.srcObject=stream;await video.play();
      let previous='';
      const frame=async()=>{
        if(!active())return;
        try{
          const codes=await detector.detect(video);
          const raw=codes[0]?.rawValue||'';
          if(active()&&raw&&raw!==previous)scanCode(raw);
          previous=raw;
        }catch{}
        if(active())window.setTimeout(frame,230);
      };
      frame();
    }catch{
      if(!active())return;
      stopCamera();box.textContent='Impossibile utilizzare la fotocamera. Controlla il permesso o inserisci il codice manuale.';
    }
  }
  function scanError(message){
    const result=document.getElementById('gd-scan-result');
    if(result)result.textContent=message;
    else notify(message);
  }
  function scanCode(raw){
    const value=String(raw||'').trim().toUpperCase();const qr=readLocal(QR_KEY,null);
    if(!value.startsWith('GDDEMO1:')){scanError('Questo non è un QR DinerPass demo valido.');return;}
    if(!qr||qr.expires<=Date.now()||value!==qr.token||!customer(qr.customerId)){
      scanError('QR demo scaduto o non presente su questo dispositivo. Non è stata registrata alcuna visita.');return;
    }
    const c=customer(qr.customerId),todayKey=today();
    if(visits().some(v=>v.customerId===c.id&&v.day===todayKey)){
      scanError('La presenza di oggi risulta già registrata.');return;
    }
    const next=[{id:'DV'+rand(8),customerId:c.id,nickname:c.nickname,restaurant:N,at:Date.now(),day:todayKey},...visits()].slice(0,100);
    if(!saveLocal(DEMO_VISITS,next)){
      scanError('Visita non salvata. Verifica lo spazio disponibile e riprova con il DinerPass.');
      return;
    }
    // A QR token is single-use in the local demo.
    saveLocal(QR_KEY,{customerId:qr.customerId,token:'used',expires:0});
    latestScan=c.id;closeScanner();render();notify(`Presenza demo registrata: ${c.nickname}.`);
  }
  function enter(role, customerId){
    stopCamera();state.welcome=false;state.tab='home';state.role=role;state.passportFlipped=false;
    if(customerId&&customer(customerId))db.activeCustomer=customerId;
    localStorage.setItem(WELCOME,'1');
    saveSession({role:role==='restaurant'?'restaurant':'customer',customerId:db.activeCustomer});
    save();render();window.scrollTo?.({top:0,behavior:'instant'});
  }
  function renderGate(next){step=next;state.welcome=true;stopCamera();render();window.scrollTo?.({top:0,behavior:'instant'});}
  function openGoogleMaps(){
    const name=document.getElementById('gd-venue-name')?.value.trim()||'';
    const city=document.getElementById('gd-venue-city')?.value.trim()||'';
    if(name.length<3||city.length<2){notify('Inserisci nome del ristorante e città.');return;}
    const url='https://www.google.com/maps/search/?api=1&query='+encodeURIComponent(name+', '+city);
    window.open(url,'_blank','noopener,noreferrer');
    searchOpened=true;
    const msg=document.querySelector('.gd-security-note span');if(msg)msg.textContent='Ricerca aperta su Google Maps. La presenza online non dimostra la proprietà del locale. La verifica del gestore non è ancora attiva.';
  }
  document.addEventListener('click',event=>{
    if(event.target.closest('[data-tab]'))stopCamera();
    const btn=event.target.closest('[data-gd-entry]');if(!btn)return;
    const action=btn.dataset.gdEntry;
    switch(action){
      case 'landing': renderGate('landing');break;
      case 'signin':case 'signup':case 'customer':case 'merchant':renderGate(action);break;
      case 'preview':enter('customer');break;
      case 'resume':{const s=session();if(s?.role==='customer'&&customer(s.customerId))enter('customer',s.customerId);else if(s?.role==='restaurant')enter('restaurant');else enter('customer');break;}
      case 'maps':openGoogleMaps();break;
      case 'logout':localStorage.removeItem(SESSION_KEY);renderGate('landing');break;
      case 'copy-qr':{
        const token=refreshPass();
        if(!token)break;
        const showManual=()=>{
          const details=document.querySelector('.gd-manual-code');
          if(details){details.open=true;notify('Puoi selezionare e copiare il codice mostrato.');}
        };
        if(navigator.clipboard?.writeText)navigator.clipboard.writeText(token).then(()=>notify('Codice demo copiato.')).catch(showManual);
        else showManual();
        break;
      }
      case 'scan':{if(document.querySelector('.gd-scan-overlay'))break;document.body.insertAdjacentHTML('beforeend',scanPanel());document.querySelector('.gd-scan-overlay .gd-icon-close')?.focus({preventScroll:true});break;}
      case 'close-scan':closeScanner();break;
      case 'camera':startCamera();break;
    }
  });
  document.addEventListener('keydown',event=>{if(event.key==='Escape'&&document.querySelector('.gd-scan-overlay')){event.preventDefault();closeScanner();}});
  document.addEventListener('submit',event=>{
    const form=event.target;
    if(form.id==='gd-create-customer'){
      event.preventDefault();const nickname=String(form.elements['gd-nick'].value||'').trim().replace(/\s+/g,' ');
      if(nickname.length<3||nickname.length>24){notify('Il nickname deve contenere da 3 a 24 caratteri.');return;}
      // Contacts in the demo are discarded intentionally, never persisted.
      const id='GD-'+rand(9);
      db.customers.push({id,nickname});
      db.activeCustomer=id;db.vouchers=db.vouchers||[];save();
      enter('customer',id);notify('Il tuo profilo demo e il DinerPass sono pronti.');
    }else if(form.id==='gd-create-merchant'){
      event.preventDefault();const name=String(form.elements['gd-venue-name'].value||'').trim(),city=String(form.elements['gd-venue-city'].value||'').trim();
      if(name.length<3||city.length<2){notify('Inserisci nome e città del locale.');return;}
      saveLocal(VENUE_KEY,{name:name.slice(0,80),city:city.slice(0,80),status:'pending_verification',source:searchOpened?'public_search_opened':'not_checked'});
      enter('restaurant');notify('Anteprima ristoratore aperta. La verifica dell’attività non è attiva.');
    }else if(form.id==='gd-scan-manual'){
      event.preventDefault();scanCode(form.elements.token.value);
    }
  });
  // Refresh the visual QR only while visible. Avoid exposing contact data in the payload.
  function refreshPass(){
    const view=document.getElementById('gd-qr-viewport');
    if(!view||document.hidden)return;
    const pass=tokenData();
    if(!pass)return;
    if(view.querySelector('[data-qr-token]')?.dataset.qrToken!==pass.token){
      view.innerHTML=qrHTML(pass);
      const manual=document.querySelector('.gd-manual-code code');
      if(manual)manual.textContent=pass.token;
    }
    return pass.token;
  }
  window.setInterval(refreshPass,1000);
  function pauseScanner(){
    stopCamera();
    const box=document.getElementById('gd-camera-box');
    if(box)box.textContent='Fotocamera disattivata. Puoi riattivarla o inserire il codice manuale.';
  }
  window.addEventListener('pagehide',pauseScanner);
  document.addEventListener('visibilitychange',()=>{if(document.hidden)pauseScanner();else refreshPass();});
  render();
})();