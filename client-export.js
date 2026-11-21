/* GoodDiner: self-service export of the authenticated user's own data.
   Never cache exports, post them to a third party or include Auth tokens. */
(() => {
  'use strict';
  const pageSize = 500;
  const collections = [
    ['visits','customer_id','id,restaurant_id,guest_nickname,guest_code,visited_on,checked_in_at,status,void_reason,voided_at','checked_in_at'],
    ['reviews','customer_id','id,visit_id,restaurant_id,rating,comment,status,created_at','created_at'],
    ['disputes','customer_id','id,review_id,reason,status,created_at,resolved_at','created_at'],
    ['vouchers','customer_id','id,milestone,status,created_at','created_at'],
    ['privacy_requests','requester_id','id,request_kind,details,status,created_at,resolved_at','created_at']
  ];
  async function collect(sb, user) {
    if (!sb || !user?.id) throw Error('Accedi prima di esportare i dati.');
    const actual = await sb.auth.getUser();
    if (actual.error || actual.data?.user?.id !== user.id) {
      throw Error('Sessione non valida. Effettua nuovamente l’accesso.');
    }
    const profile = await sb.from('profiles')
      .select('id,nickname,customer_code,role,created_at,updated_at')
      .eq('id',user.id).single();
    if (profile.error) throw Error('Profilo non disponibile: '+profile.error.message);
    const result = {
      source: 'GoodDiner',
      exported_at: new Date().toISOString(),
      account: {id:user.id,email:user.email||null,is_anonymous:Boolean(user.is_anonymous)},
      profile: profile.data
    };
    for (const [table,ownerField,fields,sortField] of collections) {
      const rows=[];
      for(let offset=0; ;offset+=pageSize) {
        const response=await sb.from(table).select(fields)
          .eq(ownerField,user.id).order(sortField,{ascending:true})
          .range(offset,offset+pageSize-1);
        if(response.error) throw Error('Esportazione '+table+': '+response.error.message);
        const page=response.data||[];
        rows.push(...page);
        if(page.length<pageSize)break;
        if(offset>=100000)throw Error('Archivio troppo ampio: contatta l’assistenza per completare l’accesso ai dati.');
      }
      result[table]=rows;
    }
    return result;
  }
  async function download(sb,user) {
    const data=await collect(sb,user);
    const json=JSON.stringify(data,null,2);
    const url=URL.createObjectURL(new Blob([json],{type:'application/json;charset=utf-8'}));
    try {
      const anchor=document.createElement('a');
      anchor.href=url;
      anchor.download='gooddiner-dati-personali-'+new Date().toISOString().slice(0,10)+'.json';
      anchor.hidden=true;
      document.body.appendChild(anchor);
      anchor.click();
      anchor.remove();
    }finally{
      setTimeout(()=>URL.revokeObjectURL(url),3000);
    }
    return true;
  }
  window.GoodDinerDataExport=Object.freeze({collect,download});
})();
