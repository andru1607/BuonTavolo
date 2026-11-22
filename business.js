/* GoodDiner Business. Fail closed until official domain, CAPTCHA and privacy are approved. */
(() => {
  'use strict';
  const cfg=window.GOODDINER_PUBLIC_CONFIG||{};
  const form=document.getElementById('business-lead-form');
  const disabled=document.getElementById('lead-disabled');
  const message=document.getElementById('business-lead-message');
  const privacyLink=document.getElementById('business-privacy-link');
  const url=String(cfg.businessPrivacyUrl||'').trim();
  let approvedPrivacy=false;
  try {
    const parsed=new URL(url);
    approvedPrivacy=parsed.protocol==='https:'&&!parsed.username&&!parsed.password;
  } catch {}
  const active=cfg.businessLeadIntakeEnabled===true
    &&approvedPrivacy
    &&Boolean(String(cfg.turnstileSiteKey||'').trim())
    &&String(cfg.supabaseUrl||'')==='https://ixczkhmvbjszgmlqznlk.supabase.co'
    &&String(cfg.supabasePublishableKey||'').startsWith('sb_publishable_');
  if(!active||!form||!disabled)return;
  privacyLink.href=url;
  disabled.hidden=true;
  form.hidden=false;
  window.GoodDinerCaptcha?.mount();
  let pending=false;
  form.addEventListener('submit',async event=>{
    event.preventDefault();
    if(pending)return;
    message.textContent='';
    const restaurant=String(form.elements.restaurant.value||'').trim();
    const city=String(form.elements.city.value||'').trim();
    const email=String(form.elements.email.value||'').trim().toLowerCase();
    const consent=Boolean(form.elements.contactConsent.checked);
    if(!consent||restaurant.length<3||restaurant.length>100||city.length<2||city.length>100||
       email.length<5||email.length>254||!email.includes('@')){
      message.textContent='Controlla i campi e conferma la richiesta di contatto.';
      return;
    }
    let token;
    try{token=window.GoodDinerCaptcha?.token(form,true);}
    catch(error){message.textContent=error.message;return;}
    const button=form.querySelector('button[type="submit"]');
    pending=true;
    button.disabled=true;
    try{
      const request=await fetch(cfg.supabaseUrl+'/functions/v1/business-pilot-lead',{
        method:'POST',
        headers:{'Content-Type':'application/json','apikey':cfg.supabasePublishableKey},
        body:JSON.stringify({restaurant_name:restaurant,city,email,contact_requested:consent,captcha_token:token})
      });
      if(!request.ok){
        if(request.status===429)throw Error('Troppe richieste. Riprova in un altro momento.');
        throw Error('Invio non disponibile. Nessuna attivazione o pagamento è stato effettuato.');
      }
      form.reset();
      message.textContent='Richiesta inviata. Non hai acquistato un abbonamento e non ti verrà addebitato nulla.';
    }catch(error){message.textContent=error.message||'Impossibile inviare la richiesta.';}
    finally{pending=false;button.disabled=false;window.GoodDinerCaptcha?.resetFor(form);}
  });
})();
