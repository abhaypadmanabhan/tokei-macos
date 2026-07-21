class Component extends DCLogic {
  constructor(props){
    super(props);
    this.state = { tab:'overview', range:'today', kpiMetric:'usage', drillId:null, settingsOpen:false, addOpen:false, screen:'live', sizePreset:'full', narrow:false, mbReadout:'tokens', accentOverride:null, live:{claude:'live',codex:'off',cursor:'off',cline:'off',antigravity:'live',opencode:'off'}, planCost:{}, hidden:{}, watching:{}, rescan:{}, warnAt:80, alertAt:95, notif:{quota:true,weekly:false}, syncing:false, syncedLabel:'12s ago', updChecking:false, updDone:false, t:0 };
    this.shade = { claude:'#6E6E78', codex:'#9A9AA4', cursor:'#C4C4CC', cline:'#4A4A52', opencode:'#37373E' };
    this.providers = [
      { id:'claude', name:'Claude Code', glyph:'CC', today:533e6, conf:'reported', tier:'Frontier', peakHour:15,
        path:'~/.claude/usage.db', lastSync:'18s ago', reads:'~/.claude session logs (token counts only)', privacy:'Local file, read-only. No prompts or code.',
        models:[
          {model:'Opus 4.6', windows:[{label:'Weekly',pct:46,reset:'resets in 3d 14h',elapsed:0.52},{label:'5-hour',pct:22,reset:'resets in 2h 41m',elapsed:0.47}]},
          {model:'Sonnet 4.6', windows:[{label:'Weekly',pct:31,reset:'resets in 3d 14h',elapsed:0.52},{label:'5-hour',pct:9,reset:'resets in 2h 41m',elapsed:0.47}]},
        ],
        quotas:[{label:'Weekly',pct:46,reset:'resets in 3d 14h',elapsed:0.52},{label:'5-hour session',pct:22,reset:'resets in 2h 41m',elapsed:0.47}],
        api:722, multStr:'3.6×', plan:200, planLabel:'$200/mo · 2× Max accounts', lifetime:2.31e9, hasTokens:true, source:'~/.claude · OAuth' },
      { id:'codex', name:'Codex', glyph:'CX', today:8.9e6, conf:'estimated', tier:'Frontier', peakHour:11,
        path:'~/.codex/sessions/', lastSync:'44s ago', reads:'codex CLI session log', privacy:'Local file, read-only. Token counts only.',
        models:[
          {model:'GPT-5.2 Codex', windows:[{label:'Weekly',pct:38,reset:'resets in 4d 02h',elapsed:0.43},{label:'5-hour',pct:62,reset:'resets in 46m',elapsed:0.71}]},
        ],
        quotas:[{label:'Session',pct:62,reset:'resets in 46m',elapsed:0.71},{label:'Weekly',pct:38,reset:'resets in 4d 02h',elapsed:0.43}],
        api:58, multStr:'2.9×', plan:20, planLabel:'$20/mo', lifetime:165e6, hasTokens:true, source:'codex CLI · session log' },
      { id:'cursor', name:'Cursor', glyph:'CU', today:1.38e6, conf:'local', tier:'Standard', peakHour:14,
        path:'~/Library/Application Support/Cursor/usage.sqlite', lastSync:'2m ago', reads:'Cursor local usage database', privacy:'Local SQLite, read-only.',
        quotas:[{label:'Monthly',pct:7,reset:'resets in 21d',elapsed:0.33}],
        api:41, multStr:'2.1×', plan:20, planLabel:'$20/mo · Pro (active)', lifetime:78e6, hasTokens:true, source:'Cursor app · local db' },
      { id:'cline', name:'Cline', glyph:'CL', today:4.2e6, conf:'local', tier:'Standard', peakHour:22,
        path:'~/Library/…/globalStorage/cline/usage.json', lastSync:'1m ago', reads:'VS Code extension usage store', privacy:'Local JSON, read-only.',
        quotas:[], quotaNote:'No quota — pay-as-you-go (Cline Pass). Spend is metered locally.',
        api:12.4, multStr:'2.5×', plan:5, planLabel:'$5/mo · Cline Pass', lifetime:210e6, hasTokens:true, source:'VS Code ext · local' },
      { id:'antigravity', name:'Antigravity', glyph:'AG', today:null, conf:'unavailable', tier:'Preview', peakHour:null,
        path:'quota API only (online)', lastSync:'5m ago · online', reads:'Antigravity online quota endpoint', privacy:'Read-only quota. No local token log exists.',
        quotas:[{label:'Quota',pct:71,reset:'—',elapsed:0.6}],
        creditsUsed:340, creditsTotal:500, acceptedLines:4210,
        api:null, multStr:'—', plan:5, planLabel:'$5/mo · Google student', lifetime:null, hasTokens:false, planOnly:true, source:'quota API only' },
      { id:'gemini', name:'Gemini', glyph:'GM', today:null, conf:'unavailable', tier:'—', peakHour:null,
        path:'not connected', lastSync:'—', reads:'—', privacy:'Sign in to enable.',
        quotas:[], api:null, multStr:'—', plan:null, planLabel:'Not signed in', lifetime:null, hasTokens:false, signedOut:true, source:'not connected' },
      { id:'opencode', name:'opencode', glyph:'OC', today:0.62e6, conf:'local', tier:'Standard', peakHour:16,
        path:'~/.local/share/opencode/usage.db', lastSync:'3m ago', reads:'opencode CLI local database', privacy:'Local SQLite, read-only.',
        quotas:[], quotaNote:'No quota window reported by opencode.',
        api:9.2, multStr:'—', plan:null, planLabel:'No plan cost set', lifetime:21e6, hasTokens:true, noPlan:true, source:'opencode CLI · local' },
    ];
    this.split = { claude:[{k:'Input',v:41.2e6},{k:'Cache read',v:402.8e6},{k:'Cache write',v:63.5e6},{k:'Output',v:25.5e6}] };
    this.tint = { claude:'#C77D5A', codex:'#5FA88C', cursor:'#9AA0AA', cline:'#8A93E6', antigravity:'#D2A15C', gemini:'#6D93DB', opencode:'#B98BD0' };
    this.tokAgents=['claude','codex','cursor','cline','opencode'];
    this.detectedIds=['claude','codex','cursor','cline','opencode'];
    // init plan cost strings + watching
    this.providers.forEach(p=>{ this.state.planCost[p.id] = (p.plan!=null? String(p.plan):''); this.state.watching[p.id]=true; });
    // daily history
    this.daily = {};
    ['claude','codex','cursor','cline','opencode'].forEach((id,i)=>{
      const p=this.providers.find(x=>x.id===id);
      const base={claude:92e6,codex:9e6,cursor:1.3e6,cline:4e6,opencode:0.6e6}[id];
      const vol={claude:42e6,codex:5e6,cursor:0.8e6,cline:2.4e6,opencode:0.35e6}[id];
      let s=(i+3)*99173>>>0; const rnd=()=>{s=(s*1664525+1013904223)>>>0;return s/4294967296;};
      const arr=[]; for(let d=0;d<30;d++){arr.push(Math.max(0.02e6, base+(rnd()-0.5)*2*vol));}
      arr[29]=p.today; this.daily[id]=arr;
    });
    // hourly heatmap 7x24
    this.hours=[]; let hs=20250720>>>0; const hrnd=()=>{hs=(hs*1664525+1013904223)>>>0;return hs/4294967296;};
    for(let d=0;d<7;d++){ const row=[]; const weekend=(d>=5); for(let hr=0;hr<24;hr++){ let base=0; if(hr>=9&&hr<=18) base=0.55+0.4*Math.sin((hr-9)/9*Math.PI); if(hr>=20&&hr<=23) base=0.25; base*= weekend?0.4:1; row.push(Math.max(0, base+(hrnd()-0.5)*0.25)); } this.hours.push(row); }
    this.contentRef=(el)=>{ if(el&&!this._ro){ this._ro=new ResizeObserver(es=>{ const w=es[0].contentRect.width; const n=w<720; if(n!==this.state.narrow) this.setState({narrow:n}); }); this._ro.observe(el);} };
  }
  componentDidMount(){ this.runAnim(); }
  componentDidUpdate(){ const k=this.state.kpiMetric+this.state.range+this.state.tab+this.state.drillId+this.state.screen; if(k!==this._animKey) this.runAnim(); }
  componentWillUnmount(){ if(this._ro) this._ro.disconnect(); cancelAnimationFrame(this._raf); clearTimeout(this._syncT); clearTimeout(this._updT); clearTimeout(this._fb); }
  runAnim(){ this._animKey=this.state.kpiMetric+this.state.range+this.state.tab+this.state.drillId+this.state.screen; const start=performance.now(),dur=650; cancelAnimationFrame(this._raf); clearTimeout(this._fb);
    const tick=(now)=>{ let t=Math.max(0,Math.min(1,(now-start)/dur)); t=1-Math.pow(1-t,3); this.setState({t}); if(t<1) this._raf=requestAnimationFrame(tick); }; this._raf=requestAnimationFrame(tick);
    this._fb=setTimeout(()=>{ if(this.state.t<1) this.setState({t:1}); }, dur+180); }

  accent(){ return this.state.accentOverride || this.props.accent || '#FF3B70'; }
  fmtTok(n){ if(n==null) return '—'; if(n>=1e9) return (n/1e9).toFixed(2)+'B'; if(n>=1e6){const v=n/1e6; return (v>=100?v.toFixed(0):v.toFixed(2))+'M';} if(n>=1e3) return Math.round(n/1e3)+'K'; return String(Math.round(n)); }
  fmtDol(n){ if(n==null) return '—'; return '$'+n.toFixed(2); }
  fmtHour(h){ const hh=((h%24)+24)%24; const ap=hh<12?'AM':'PM'; const d=hh%12===0?12:hh%12; return d+' '+ap; }
  confStyle(conf){ const map={reported:'#B9B9C2',local:'#8E8E99',estimated:'#7A7A84',unavailable:'#54545C'}; const c=map[conf]||'#6E6E78'; const border=conf==='unavailable'?'dashed':'solid'; return `display:inline-block;font-family:ui-monospace,'SF Mono',Menlo,monospace;font-size:8.5px;letter-spacing:.08em;text-transform:uppercase;color:${c};border:1px ${border} #26262C;border-radius:3px;padding:2px 6px;white-space:nowrap`; }
  glyphCss(tint,size,fs){ return `width:${size}px;height:${size}px;border:1px solid ${tint}55;background:${tint}14;border-radius:${size>=32?4:3}px;display:flex;align-items:center;justify-content:center;font-family:ui-monospace,'SF Mono',Menlo,monospace;font-size:${fs}px;font-weight:700;color:${tint};flex:none`; }
  qColor(pct){ const A=this.accent(); return pct>=90?A:pct>=60?'#D2A15C':'#6E6E78'; }
  toggle(on){ const A=this.accent(); return { track:`width:36px;height:21px;border-radius:11px;border:none;cursor:pointer;position:relative;background:${on?A:'#2A2A31'};transition:background .15s;flex:none`, knob:`position:absolute;top:2.5px;left:${on?'17.5px':'2.5px'};width:16px;height:16px;border-radius:50%;background:#fff;transition:left .15s` }; }
  pace(pct,elapsed){ const lin=elapsed*100; if(pct>lin*1.12) return {word:'ahead',color:'#D2A15C'}; if(pct<lin*0.75) return {word:'headroom',color:'#6BBF8A'}; return {word:'on pace',color:'#8E8E99'}; }
  effPlan(p){ const v=this.state.planCost[p.id]; if(v===undefined) return p.plan; if(v==='') return null; const n=Number(v); return isNaN(n)?p.plan:n; }
  headroomId(){ const cand=this.providers.filter(p=>p.quotas&&p.quotas.length&&!this.state.hidden[p.id]); if(!cand.length) return null; return cand.reduce((a,b)=> (Math.max(...a.quotas.map(q=>q.pct)) <= Math.max(...b.quotas.map(q=>q.pct)) ? a : b)).id; }
  rangeK(){ return {today:'TODAY',week:'WEEK',month:'MONTH',all:'ALL-TIME'}[this.state.range]; }
  rangeTok(id){ const p=this.providers.find(x=>x.id===id); if(!p.hasTokens) return null; if(this.state.range==='all') return p.lifetime; const k={today:1,week:7,month:30}[this.state.range]; const a=this.daily[id]; return a.slice(a.length-k).reduce((s,v)=>s+v,0); }
  dayTotals(){ const out=[]; for(let i=0;i<30;i++){ let s=0; this.tokAgents.forEach(id=>{ if(!this.state.hidden[id]) s+=this.daily[id][i]; }); out.push(s);} return out; }
  visTok(){ return this.tokAgents.filter(id=>!this.state.hidden[id]); }

  renderChart(){
    const h=React.createElement, m=this.state.kpiMetric, A=this.accent(), t=this.state.t;
    if(m==='quota'||m==='value'){
      let rows;
      if(m==='quota') rows=this.providers.filter(p=>p.quotas.length&&!this.state.hidden[p.id]).map(p=>({name:p.name,val:Math.max(...p.quotas.map(q=>q.pct)),disp:Math.max(...p.quotas.map(q=>q.pct))+'%',max:100})).sort((a,b)=>b.val-a.val);
      else rows=this.providers.filter(p=>p.api!=null&&this.effPlan(p)!=null&&!this.state.hidden[p.id]).map(p=>({name:p.name,val:p.api/this.effPlan(p),disp:(p.api/this.effPlan(p)).toFixed(1)+'×',max:4})).sort((a,b)=>b.val-a.val);
      return h('div',{style:{display:'flex',flexDirection:'column',gap:'2px'}},rows.map((r,i)=>
        h('div',{key:i,style:{display:'flex',alignItems:'center',gap:'16px',padding:'11px 0'}},
          h('span',{style:{fontSize:'13px',color:'#C4C4CC',minWidth:'118px'}},r.name),
          h('span',{style:{flex:1,height:'6px',background:'#161619',borderRadius:'3px',overflow:'hidden'}},h('span',{style:{display:'block',height:'100%',width:Math.min(100,r.val/r.max*100*t)+'%',background:(m==='quota'?this.qColor(r.val):'#6E6E78')}})),
          h('span',{style:{fontFamily:"ui-monospace,'SF Mono',Menlo,monospace",fontSize:'15px',fontWeight:600,color:'#ECECF1',width:'50px',textAlign:'right'}},r.disp)
        )));
    }
    const days=(this.state.range==='month'||this.state.range==='all')?30:14;
    const totals=this.dayTotals().slice(30-days);
    const W=900,H=190,pT=14,pB=4,pL=2,pR=2;
    let vals=totals; if(m==='cumulative'){ let run=0; vals=totals.map(x=>run+=x); }
    const sorted=[...vals].sort((a,b)=>a-b); const cap=(m==='cumulative')?Math.max(...vals):sorted[Math.floor(sorted.length*0.82)]*1.08||Math.max(...vals)||1;
    const sx=(W-pL-pR)/(days-1);
    const co=vals.map((v,i)=>[pL+i*sx, pT+(H-pT-pB)*(1-Math.min(1,v/cap))]);
    const line=co.map((c,i)=>(i?'L':'M')+c[0].toFixed(1)+' '+c[1].toFixed(1)).join(' ');
    const area=line+' L'+co[co.length-1][0].toFixed(1)+' '+(H-pB)+' L'+pL+' '+(H-pB)+' Z';
    const last=co[co.length-1];
    const lbl=(i)=>{ const gi=30-days+i, da=29-gi; return da===0?'today':da===1?'yesterday':da+'d ago'; };
    const capY=pT+(H-pT-pB)*(1-Math.min(1,cap/cap));
    const svg=h('svg',{viewBox:`0 0 ${W} ${H}`,width:'100%',height:200,preserveAspectRatio:'none',style:{display:'block',overflow:'visible'}},
      h('line',{x1:pL,y1:capY,x2:W-pR,y2:capY,stroke:'#1C1C21',strokeWidth:1,strokeDasharray:'4 5'}),
      h('line',{x1:pL,y1:H-pB,x2:W-pR,y2:H-pB,stroke:'#1C1C21',strokeWidth:1}),
      h('path',{d:area,fill:'rgba(236,236,241,0.035)',style:{animation:'tk-fade 1s ease both'}}),
      h('path',{d:line,fill:'none',stroke:'#C4C4CC',strokeWidth:1.5,vectorEffect:'non-scaling-stroke',pathLength:1,strokeDasharray:1,style:{animation:'tk-draw 1s ease both'}}),
      h('circle',{cx:last[0],cy:last[1],r:3.5,fill:A,style:{transformOrigin:`${last[0]}px ${last[1]}px`,animation:'tk-dot .4s ease .7s both'}})
    );
    const dots=vals.map((v,i)=>h('div',{key:i,title:`${lbl(i)} · ${this.fmtTok(v)}`,style:{position:'absolute',left:(co[i][0]/W*100)+'%',top:(co[i][1]/H*200)+'px',width:'14px',height:'14px',marginLeft:'-7px',marginTop:'-7px',borderRadius:'50%',cursor:'default'}},
      h('div',{style:{width:'5px',height:'5px',margin:'4.5px',borderRadius:'50%',background:'#C4C4CC',opacity:0,transition:'opacity .12s'},className:'tk-cdot'})));
    return h('div',{},
      h('div',{style:{position:'relative',height:'200px'},onMouseOver:(e)=>{const d=e.target.closest('div')&&e.currentTarget.querySelectorAll('.tk-cdot');},ref:(el)=>{ if(el&&!el._h){el._h=1; el.addEventListener('mouseover',ev=>{const t=ev.target.closest('[title]'); el.querySelectorAll('.tk-cdot').forEach(d=>d.style.opacity=0); if(t){const cd=t.querySelector('.tk-cdot'); if(cd)cd.style.opacity=1;}}); el.addEventListener('mouseleave',()=>el.querySelectorAll('.tk-cdot').forEach(d=>d.style.opacity=0)); }}},
        svg,
        h('div',{style:{position:'absolute',top:'-4px',right:0,fontFamily:"ui-monospace,'SF Mono',Menlo,monospace",fontSize:'10px',color:'#54545C'}},'≈ '+this.fmtTok(cap)+'/day'),
        dots
      ),
      h('div',{style:{display:'flex',justifyContent:'space-between',marginTop:'9px',fontFamily:"ui-monospace,'SF Mono',Menlo,monospace",fontSize:'10px',color:'#54545C'}},
        h('span',{},lbl(0)), h('span',{},lbl(Math.floor((days-1)/2))), h('span',{},'today'))
    );
  }
  renderHistory(id){
    const h=React.createElement, t=this.state.t, tint=this.tint[id]||'#8E8E99';
    const arr=this.daily[id], n=arr.length, W=900,H=150,pT=14,pB=4,pL=2,pR=2;
    const avg=arr.reduce((a,b)=>a+b,0)/n;
    const sorted=[...arr].sort((a,b)=>a-b); const cap=(sorted[Math.floor(n*0.92)]*1.05)||Math.max(...arr)||1;
    const sx=(W-pL-pR)/(n-1);
    const co=arr.map((v,i)=>[pL+i*sx, pT+(H-pT-pB)*(1-Math.min(1,v/cap))]);
    const line=co.map((c,i)=>(i?'L':'M')+c[0].toFixed(1)+' '+c[1].toFixed(1)).join(' ');
    const area=line+' L'+co[n-1][0].toFixed(1)+' '+(H-pB)+' L'+pL+' '+(H-pB)+' Z';
    const avgY=pT+(H-pT-pB)*(1-Math.min(1,avg/cap)); const last=co[n-1];
    const lbl=(i)=>{ const da=n-1-i; return da===0?'today':da===1?'yesterday':da+'d ago'; };
    const svg=h('svg',{viewBox:`0 0 ${W} ${H}`,width:'100%',height:150,preserveAspectRatio:'none',style:{display:'block',overflow:'visible'}},
      h('line',{x1:pL,y1:avgY,x2:W-pR,y2:avgY,stroke:'#3A3A42',strokeWidth:1,strokeDasharray:'3 5'}),
      h('line',{x1:pL,y1:H-pB,x2:W-pR,y2:H-pB,stroke:'#1C1C21',strokeWidth:1}),
      h('path',{d:area,fill:tint+'18',style:{animation:'tk-fade 1s ease both'}}),
      h('path',{d:line,fill:'none',stroke:tint,strokeWidth:1.5,vectorEffect:'non-scaling-stroke',pathLength:1,strokeDasharray:1,style:{animation:'tk-draw 1s ease both'}}),
      h('circle',{cx:last[0],cy:last[1],r:3.5,fill:tint,style:{transformOrigin:`${last[0]}px ${last[1]}px`,animation:'tk-dot .4s ease .7s both'}})
    );
    const dots=arr.map((v,i)=>h('div',{key:i,title:`${lbl(i)} · ${this.fmtTok(v)}`,style:{position:'absolute',left:(co[i][0]/W*100)+'%',top:(co[i][1]/H*150)+'px',width:'12px',height:'12px',marginLeft:'-6px',marginTop:'-6px',borderRadius:'50%',cursor:'default'}}));
    return h('div',{},
      h('div',{style:{position:'relative',height:'150px'}},
        svg,
        h('div',{style:{position:'absolute',top:'-4px',right:0,fontFamily:"ui-monospace,'SF Mono',Menlo,monospace",fontSize:'10px',color:'#54545C'}},'avg '+this.fmtTok(avg)+'/day'),
        dots
      ),
      h('div',{style:{display:'flex',justifyContent:'space-between',marginTop:'8px',fontFamily:"ui-monospace,'SF Mono',Menlo,monospace",fontSize:'10px',color:'#54545C'}},
        h('span',{},'30d ago'), h('span',{},'15d ago'), h('span',{},'today'))
    );
  }
  renderDonut(){
    const h=React.createElement, t=this.state.t;
    const items=this.visTok().map(id=>({name:this.providers.find(p=>p.id===id).name,val:this.rangeTok(id)||0,tint:this.tint[id]})).filter(x=>x.val>0).sort((a,b)=>b.val-a.val);
    const tot=items.reduce((s,x)=>s+x.val,0)||1;
    const cx=80,cy=80,rr=58,sw=18,C=2*Math.PI*rr;
    let start=0; const segs=items.map((x,i)=>{ const frac=x.val/tot; const dash=C*frac*t; const el=h('circle',{key:i,cx,cy,r:rr,fill:'none',stroke:x.tint,strokeWidth:sw,strokeDasharray:`${dash.toFixed(2)} ${(C-dash).toFixed(2)}`,strokeDashoffset:(-C*start).toFixed(2),transform:`rotate(-90 ${cx} ${cy})`}); start+=frac; return el; });
    return h('svg',{viewBox:'0 0 160 160',width:150,height:150,style:{display:'block',flex:'none'}},
      h('circle',{cx,cy,r:rr,fill:'none',stroke:'#161619',strokeWidth:sw}),
      segs,
      h('text',{x:cx,y:cy-3,textAnchor:'middle',fontSize:22,fontWeight:600,fontFamily:"ui-monospace,'SF Mono',Menlo,monospace",fill:'#ECECF1'},this.fmtTok(tot*t)),
      h('text',{x:cx,y:cy+15,textAnchor:'middle',fontSize:9,letterSpacing:'0.1em',fontFamily:"ui-monospace,'SF Mono',Menlo,monospace",fill:'#54545C'},'TOKENS')
    );
  }
  renderHeatmap(){
    const h=React.createElement; const rows=this.hours; const max=Math.max.apply(null,rows.map(r=>Math.max.apply(null,r)))||1;
    const days=['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    const lx=32, cw=30, ch=20, gap=2, ty=2, cols=24; const gw=cols*cw; const H=ty+7*ch+20; const W=lx+gw+2;
    const cells=[]; rows.forEach((row,d)=>row.forEach((v,hr)=>{ const inten=v/max; cells.push(h('rect',{key:d+'-'+hr,x:lx+hr*cw+gap/2,y:ty+d*ch+gap/2,width:cw-gap,height:ch-gap,rx:2,fill:`rgba(202,202,214,${(0.05+inten*0.85).toFixed(3)})`,style:{animation:`tk-fade .5s ease ${(d*0.03).toFixed(2)}s both`}})); }));
    const dayLabels=days.map((dn,d)=>h('text',{key:'d'+d,x:lx-9,y:ty+d*ch+ch/2+3,textAnchor:'end',fontSize:9,fontFamily:"ui-monospace,'SF Mono',Menlo,monospace",fill:'#54545C'},dn));
    const hrLabels=[0,6,12,18].map(hr=>h('text',{key:'h'+hr,x:lx+hr*cw+(cw-gap)/2,y:H-6,textAnchor:'middle',fontSize:9,fontFamily:"ui-monospace,'SF Mono',Menlo,monospace",fill:'#54545C'},(hr%12===0?12:hr%12)+(hr<12?'a':'p')));
    return h('svg',{viewBox:`0 0 ${W} ${H}`,width:'100%',preserveAspectRatio:'xMinYMin meet',style:{display:'block',maxWidth:W+'px'}},cells,dayLabels,hrLabels);
  }
  renderGauge(pct,color){
    const h=React.createElement, t=this.state.t; const cx=60,cy=60,R=48,sw=9,C=2*Math.PI*R; const dash=C*(Math.min(100,pct)/100)*t;
    return h('svg',{viewBox:'0 0 120 120',width:120,height:120,style:{display:'block'}},
      h('circle',{cx,cy,r:R,fill:'none',stroke:'#1C1C21',strokeWidth:sw}),
      h('circle',{cx,cy,r:R,fill:'none',stroke:color,strokeWidth:sw,strokeLinecap:'round',strokeDasharray:`${dash.toFixed(2)} ${(C-dash).toFixed(2)}`,transform:`rotate(-90 ${cx} ${cy})`}),
      h('text',{x:cx,y:cy+2,textAnchor:'middle',fontSize:26,fontWeight:600,fontFamily:"ui-monospace,'SF Mono',Menlo,monospace",fill:'#ECECF1'},Math.round(pct*t)+'%'),
      h('text',{x:cx,y:cy+18,textAnchor:'middle',fontSize:8.5,letterSpacing:'0.1em',fontFamily:"ui-monospace,'SF Mono',Menlo,monospace",fill:'#54545C'},'USED')
    );
  }
  doSync(){ if(this.state.syncing) return; this.setState({syncing:true}); clearTimeout(this._syncT); this._syncT=setTimeout(()=>this.setState({syncing:false,syncedLabel:'just now'}),1100); }
  cycleLive(id){ const cur=this.state.live[id]; if(cur==='off'){ this.setState(s=>({live:{...s.live,[id]:'connecting'}})); const tid=setTimeout(()=>this.setState(s=>({live:{...s.live,[id]:'live'}})),1200); } else { this.setState(s=>({live:{...s.live,[id]:'off'}})); } }
  checkUpdate(){ if(this.state.updChecking) return; this.setState({updChecking:true,updDone:false}); clearTimeout(this._updT); this._updT=setTimeout(()=>this.setState({updChecking:false,updDone:true}),1200); }

  renderVals(){
    const A=this.accent(), st=this.state, narrow=st.narrow, t=st.t;
    const playful=this.props.playfulTiers!==false;
    let fw,fh; if(st.sizePreset==='w640'){fw='640px';fh='480px';} else if(st.sizePreset==='w720'){fw='720px';fh='min(780px,90vh)';} else {fw='min(1100px,96vw)';fh='min(780px,90vh)';}
    const frameStyle=`width:${fw};height:${fh};background:#0F0F12;border:1px solid #1C1C21;border-radius:10px;overflow:hidden;display:flex;flex-direction:column;position:relative`;
    const tab=(active)=>`background:transparent;border:none;padding:0 0 3px;cursor:pointer;font-size:14px;font-weight:500;color:${active?'#ECECF1':'#54545C'};border-bottom:2px solid ${active?A:'transparent'}`;
    const isOv=st.tab==='overview', isVal=st.tab==='value', isConn=st.tab==='connections';
    const rangeBtns=[['today','Today'],['week','Week'],['month','Month'],['all','All']].map(([k,l])=>({label:l,onClick:()=>this.setState({range:k}),
      style:`background:transparent;border:none;padding:5px 11px;border-radius:4px;cursor:pointer;font-size:11.5px;font-weight:500;color:${st.range===k?'#ECECF1':'#54545C'}`}));

    const dt=this.dayTotals();
    const vis=this.visTok();
    const todayTotal=vis.reduce((s,id)=>s+this.providers.find(p=>p.id===id).today,0);
    const rangeTotal=vis.reduce((s,id)=>s+(this.rangeTok(id)||0),0);
    const hroom=this.headroomId();

    const rangeWord={today:'today',week:'this week',month:'this month',all:'all-time'}[st.range];
    const usageTarget = st.range==='today' ? todayTotal : rangeTotal;
    const metricDefs={
      usage:{label:'Usage', target:usageTarget, fmt:(n)=>this.fmtTok(n), sub:`tokens ${rangeWord} across ${vis.length} active agents. Antigravity and Gemini report no token data.`},
      quota:{label:'Quota', target:71, fmt:(n)=>Math.round(n)+'%', sub:`is your tightest quota — Antigravity's weekly window. Codex's session (62%) resets in 46m, so nothing needs action yet.`},
    };
    const selector=Object.keys(metricDefs).map(k=>{ const on=st.kpiMetric===k; return {label:metricDefs[k].label,onClick:()=>this.setState({kpiMetric:k}),
      style:`background:transparent;border:none;cursor:pointer;font-size:12.5px;font-weight:500;padding:0 0 5px;color:${on?'#ECECF1':'#54545C'};border-bottom:2px solid ${on?A:'transparent'}`};});
    const md=metricDefs[st.kpiMetric]||metricDefs.usage;
    const heroValueOv=md.fmt(md.target*t);

    let heroDelta={show:false};
    if(st.kpiMetric==='usage'){
      if(st.range==='today'){ const avg=dt.slice(22,29).reduce((s,v)=>s+v,0)/7; const ratio=todayTotal/avg;
        heroDelta={show:true, arrow: ratio>=1?'▲':'▼', val: ratio>=1.8? ratio.toFixed(1)+'×' : Math.abs(Math.round((ratio-1)*100))+'%', label: ratio>=1.8?'your daily average':'vs your daily average'}; }
      else if(st.range==='week'){ const prev=dt.slice(16,23).reduce((s,v)=>s+v,0); const pct=(rangeTotal-prev)/prev*100;
        heroDelta={show:true, arrow:pct>=0?'▲':'▼', val:Math.abs(Math.round(pct))+'%', label:'vs the previous week'}; }
    }

    // donut + patterns + heatmap
    const donutItems=vis.map(id=>({id,val:this.rangeTok(id)||0})).filter(x=>x.val>0).sort((a,b)=>b.val-a.val);
    const donutTot=donutItems.reduce((s,x)=>s+x.val,0)||1;
    const donutPct=(v)=>{ const p=v/donutTot*100; return p<1?'<1%':Math.round(p)+'%'; };
    const donutLegend=donutItems.map(x=>({name:this.providers.find(p=>p.id===x.id).name,tint:this.tint[x.id],val:this.fmtTok(x.val),pct:donutPct(x.val)}));
    const avg=dt.reduce((a,b)=>a+b,0)/dt.length;
    const wdFull=['Sundays','Mondays','Tuesdays','Wednesdays','Thursdays','Fridays','Saturdays']; const wd=i=>((1-(29-i))%7+70)%7;
    const byWd=[[],[],[],[],[],[],[]]; dt.forEach((v,i)=>byWd[wd(i)].push(v));
    const wdAvg=byWd.map(a=>a.length?a.reduce((s,x)=>s+x,0)/a.length:0);
    let bWd=0,qWd=0; wdAvg.forEach((v,i)=>{ if(v>wdAvg[bWd])bWd=i; if(v<wdAvg[qWd])qWd=i; });
    const active=dt.map(v=>v>avg*0.6); let cur=0; for(let i=dt.length-1;i>=0;i--){ if(active[i])cur++; else break; }
    let lng=0,run=0; active.forEach(a=>{ if(a){run++; if(run>lng)lng=run;} else run=0; });
    const wdShort=['Su','Mo','Tu','We','Th','Fr','Sa']; const wdMax=Math.max(...wdAvg)||1; const todayWd=1;
    const weekdayBars=[1,2,3,4,5,6,0].map(di=>{ const busy=di===bWd; const quiet=di===qWd;
      return { label:wdShort[di], labelColor: di===todayWd?'#C4C4CC':'#54545C', title:`${wdFull[di]} · ${this.fmtTok(wdAvg[di])} avg`,
        h:(wdAvg[di]/wdMax*100*t).toFixed(1)+'%', color: busy?A:(quiet?'#2A2A31':'#3A3A42') }; });
    const busiestDay=wdFull[bWd];
    const dailyAvg=this.fmtTok(avg); const streakCur=cur+'d'; const streakBest=lng+'d';
    const colSums=[]; for(let hr=0;hr<24;hr++){ let s=0; this.hours.forEach(r=>s+=r[hr]); colSums.push(s); }
    let peak=0; colSums.forEach((v,i)=>{ if(v>colSums[peak])peak=i; });
    const peakGlobal=this.fmtHour(peak)+'–'+this.fmtHour(peak+1);
    const splitGrid = narrow ? '1fr' : '1.1fr 1fr';

    const agentGrid = narrow ? 'repeat(auto-fit,minmax(120px,1fr))' : `repeat(${this.providers.filter(p=>!st.hidden[p.id]).length},minmax(0,1fr))`;
    const agents=this.providers.filter(p=>!st.hidden[p.id]).map(p=>{ const maxq=p.quotas.length?Math.max(...p.quotas.map(q=>q.pct)):0;
      const stat=p.hasTokens?this.fmtTok(p.today):(p.quotas.length?maxq+'%':'—');
      return { glyph:p.glyph,glyphStyle:this.glyphCss(this.tint[p.id],20,8.5),name:p.name,stat,statColor:p.signedOut?'#54545C':(p.hasTokens?'#ECECF1':'#C4C4CC'),
        statMark:p.conf==='estimated'?'border-bottom:1px dotted #4A4A52;padding-bottom:1px;':'', confTitle:p.conf==='estimated'?'Estimated — not directly reported':'',
        headroom:p.id===hroom, onClick:()=>this.setState({drillId:p.id}) }; });

    // value
    const inc=this.providers.filter(p=>p.api!=null&&this.effPlan(p)!=null);
    const lowest=[...inc].sort((a,b)=>a.api/this.effPlan(a)-b.api/this.effPlan(b))[0];
    const under=inc.filter(p=>p.api/this.effPlan(p)<1);
    const valueInsight = under.length ? `${under[0].name} is only returning ${under[0].multStr} — you're overpaying. Consider downgrading.`
      : `Every plan is earning out. Your thinnest is ${lowest.name} at ${lowest.multStr} — still well worth it.`;
    const valueGrid = narrow ? '1fr auto' : '2.6fr 1.4fr 1fr';
    const hideNarrow = narrow ? 'display:none;' : '';
    const valueRows=this.providers.map(p=>{ const ep=this.effPlan(p); const has=p.api!=null&&ep!=null; const action=(!p.signedOut&&ep==null);
      return { glyph:p.glyph,glyphStyle:this.glyphCss(this.tint[p.id],22,9),name:p.name, plan:this.fmtDol(ep), api:this.fmtDol(p.api), mult:p.multStr,
        multColor:p.multStr==='—'?'#54545C':'#ECECF1', op:has?'1':'0.5', hideNarrow,
        action, plainMid:!action, actionText:'Set plan cost →', actionClick:()=>this.setState({settingsOpen:true}),
        apiMark:p.conf==='estimated'?'border-bottom:1px dotted #4A4A52;':'', apiTitle:p.conf==='estimated'?'Estimated':'',
        onClick:()=>this.setState({drillId:p.id,tab:'overview'}) }; });
    const tierLabel = under.length ? (under.length+' TO REVIEW') : 'ALL RIGHT-SIZED';
    const tc = under.length ? '#D2A15C' : '#6BBF8A';
    const tierStyle=`display:inline-block;font-family:ui-monospace,'SF Mono',Menlo,monospace;font-size:11px;font-weight:600;letter-spacing:.1em;color:${tc};border:1px solid ${tc}66;border-radius:3px;padding:6px 12px`;

    // pressure
    const wins=[]; this.providers.forEach(p=>{ if(!st.hidden[p.id]) p.quotas.forEach(q=>wins.push({who:p.name,id:p.id,label:q.label,pct:q.pct,reset:q.reset})); });
    wins.sort((a,b)=>b.pct-a.pct); const top=wins[0];
    const pressure = top ? { text:`${top.who} — ${top.label.toLowerCase()} at ${top.pct}%`, meta: top.reset!=='—'?top.reset:'your tightest window',
      dot:this.qColor(top.pct), bg: top.pct>=90?'rgba(255,59,112,0.06)':top.pct>=60?'rgba(210,161,92,0.06)':'transparent', onClick:()=>this.setState({drillId:top.id,tab:'overview'}) } : {};

    // drill
    let drill={};
    if(st.drillId){
      const p=this.providers.find(x=>x.id===st.drillId);
      const maxq=p.quotas.length?Math.max(...p.quotas.map(q=>q.pct)):null;
      const week=p.hasTokens?this.daily[p.id].slice(23).reduce((s,v)=>s+v,0):null;
      const prevWeek=p.hasTokens?this.daily[p.id].slice(16,23).reduce((s,v)=>s+v,0):null;
      const own7=p.hasTokens?this.daily[p.id].slice(22,29):null; const ownAvg=own7?own7.reduce((s,v)=>s+v,0)/7:null;
      const todayRatio=ownAvg?p.today/ownAvg:null;
      const wowPct=prevWeek?Math.round((week-prevWeek)/prevWeek*100):null;
      const tokSub = todayRatio==null?(p.conf==='estimated'?'estimated':'')
        : (todayRatio>=1?'▲ ':'▼ ')+(todayRatio>=1.8?todayRatio.toFixed(1)+'× its avg':Math.abs(Math.round((todayRatio-1)*100))+'% vs avg');
      const weekSub = wowPct==null?'7-day total':((wowPct>=0?'▲ ':'▼ ')+Math.abs(wowPct)+'% vs prev week');
      const dMeta=[
        {label:'WATCHED FILE',value:p.path,color:'#9A9AA4'},
        {label:'LAST SYNC',value:p.lastSync,color:'#9A9AA4'},
        {label:'CAPABILITY',value:p.tier,color:'#C4C4CC'},
      ];
      const dStats=[
        {label:'TOKENS · TODAY',value:this.fmtTok(p.today),color:p.today==null?'#54545C':'#ECECF1',sub:tokSub},
        {label:'THIS WEEK',value:this.fmtTok(week),color:week==null?'#54545C':'#ECECF1',sub:week==null?'':weekSub},
        {label:'PEAK HOUR',value:p.peakHour==null?'—':this.fmtHour(p.peakHour),color:p.peakHour==null?'#54545C':'#ECECF1',sub:p.peakHour==null?'':'most active'},
        {label:'PLAN VALUE',value:p.multStr,color:p.multStr==='—'?'#54545C':'#ECECF1',sub:this.effPlan(p)!=null?this.fmtDol(p.api)+'/mo API-equiv':'no plan cost'},
      ];
      // gauge for tightest window
      const allWins=p.quotas.slice().sort((a,b)=>b.pct-a.pct); const tight=allWins[0];
      const gv=tight?this.pace(tight.pct,tight.elapsed):null;
      // synthesized insight
      let insight='';
      if(p.id==='claude'&&this.split.claude){ const s=this.split.claude, cr=s.find(x=>x.k==='Cache read').v, tot=s.reduce((a,b)=>a+b.v,0); insight=`${Math.round(cr/tot*100)}% of today's tokens are cache reads — heavy reuse keeps real spend well under the ${p.multStr} you'd pay on API.`; }
      else if(p.id==='cline'){ insight='Pay-as-you-go, no quota ceiling — spend is metered locally so there is nothing to run out of.'; }
      else if(tight){ const winName=tight.label.toLowerCase().includes('quota')?tight.label.toLowerCase():tight.label.toLowerCase()+' window'; const rp=(tight.reset&&tight.reset!=='—')?tight.reset:'';
        if(gv.word==='ahead') insight=`Your ${winName} is at ${tight.pct}% and burning ahead of a steady pace${rp?' — it '+rp:''} — ease off or expect a throttle.`;
        else if(gv.word==='headroom') insight=`Only ${tight.pct}% of the ${winName} is used — plenty of headroom, a good place to route more work.`;
        else insight=`Your ${winName} is tracking on pace at ${tight.pct}%${rp?', '+rp:''} — no action needed.`; }
      else if(p.hasTokens){ insight=`${this.fmtTok(week)} used this week${wowPct!=null?' ('+(wowPct>=0?'+':'')+wowPct+'% vs prior)':''}, worth ${p.multStr} against plan.`; }
      // quota groups
      let dQuotaGroups=[];
      if(p.models){ dQuotaGroups=p.models.map(mo=>({model:mo.model,dotStyle:`width:7px;height:7px;border-radius:2px;background:${this.tint[p.id]};flex:none`,
        windows:mo.windows.map(q=>{ const pc=this.pace(q.pct,q.elapsed); return {label:q.label,pct:q.pct+'%',reset:q.reset,fill:this.qColor(q.pct),paceLeft:(q.elapsed*100).toFixed(0)+'%',verdict:pc.word,verdictColor:pc.color,hideReset:narrow?'display:none;':''}; })})); }
      else if(p.quotas.length){ dQuotaGroups=[{model:null,dotStyle:'',windows:p.quotas.map(q=>{ const pc=this.pace(q.pct,q.elapsed); return {label:q.label,pct:q.pct+'%',reset:q.reset,fill:this.qColor(q.pct),paceLeft:(q.elapsed*100).toFixed(0)+'%',verdict:pc.word,verdictColor:pc.color,hideReset:narrow?'display:none;':''}; })}]; }
      // split
      const splitArr=this.split[p.id]; let dSplit=[],hasSplit=false;
      if(splitArr){ hasSplit=true; const tot=splitArr.reduce((s,x)=>s+x.v,0); const ramp=['#C4C4CC','#8E8E99','#54545C','#37373E'];
        dSplit=splitArr.map((x,i)=>({k:x.k,val:this.fmtTok(x.v),pct:(x.v/tot*100).toFixed(1)+'%',shade:ramp[i]})); }
      const backLabel = st.tab==='value'?'VALUE':st.tab==='connections'?'AGENTS':'OVERVIEW';
      drill={ d:{ glyph:p.glyph,glyphStyle:this.glyphCss(this.tint[p.id],40,13),name:p.name,planLabel:p.planLabel,conf:p.conf.toUpperCase(),confStyle:this.confStyle(p.conf),
          backLabel, headroom:p.id===hroom, insight, hasInsight:!!insight, drillGrid: narrow?'1fr':'1fr 1fr',
          hasGauge: !!tight, gaugeWin: tight?tight.label:'', gaugeVerdict: gv?gv.word:'', gaugeVColor: gv?gv.color:'#8E8E99',
          hasQuota:p.quotas.length>0 && !p.planOnly, noQuota:p.quotas.length===0, quotaNote:p.quotaNote||'No quota window.',
          planOnly:!!p.planOnly, creditUsed:p.creditsUsed, creditTotal:p.creditsTotal, creditPct:p.planOnly?(p.creditsUsed/p.creditsTotal*100*t).toFixed(1)+'%':'0%', creditFill:this.qColor(p.planOnly?p.creditsUsed/p.creditsTotal*100:0),
          notMeasured:'Antigravity reports quota online but keeps no local token log — usage isn\u2019t measured on this Mac. The numbers above come from its quota endpoint.', enableSync:()=>this.setState({tab:'connections',drillId:null}),
          hasSplit, noSplit:(!hasSplit&&!p.planOnly&&p.hasTokens), splitNote:'Only aggregate '+p.conf+' totals available — no per-type split.',
          hasHistory:p.hasTokens, noHistory:(!p.hasTokens&&!p.planOnly), historyNote:p.signedOut?'Not signed in — no history.':'No local token history exists.' },
        dMeta, dStats, dQuotaGroups, dSplit, dHistoryEl: p.hasTokens?this.renderHistory(p.id):null,
        dPlanStats: p.planOnly?[{label:'CREDITS LEFT',value:(p.creditsTotal-p.creditsUsed)},{label:'ACCEPTED LINES',value:p.acceptedLines.toLocaleString()}]:[],
        gaugeEl: tight?this.renderGauge(tight.pct,this.qColor(tight.pct)):null };
    }

    // agents management (single source of truth: live quota + show/hide + watching)
    const tierChip=(t)=>`display:inline-block;font-family:ui-monospace,'SF Mono',Menlo,monospace;font-size:8.5px;letter-spacing:.08em;color:#8E8E99;border:1px solid #26262C;border-radius:3px;padding:1px 6px`;
    const connections=this.providers.map(p=>{ const s=st.live[p.id]||'off'; const on=s!=='off';
      const map={off:{label:'OFF',color:'#54545C',dot:'#37373E',anim:''},connecting:{label:'CONNECTING',color:'#D2A15C',dot:'#D2A15C',anim:'animation:tk-blink 1s infinite;'},live:{label:'LIVE',color:'#6BBF8A',dot:'#6BBF8A',anim:''}}[s];
      const tg=this.toggle(on); const show=!st.hidden[p.id]; const sg=this.toggle(show); const w=st.watching[p.id]!==false; const rescanning=st.rescan[p.id];
      return { glyph:p.glyph,glyphStyle:this.glyphCss(this.tint[p.id],28,10),name:p.name, tier:p.tier, tierStyle:tierChip(), path:p.path, rowOp:show?'1':'0.55',
        stateLabel:map.label, stateColor:map.color, dot:map.dot, dotAnim:map.anim,
        trackStyle:tg.track, knobStyle:tg.knob, toggleTitle:on?'Turn off live quota':'Turn on live quota', onClick:()=>this.cycleLive(p.id),
        showTrack:sg.track, showKnob:sg.knob, onShow:()=>this.setState(x=>({hidden:{...x.hidden,[p.id]:show}})),
        watchDot:w?'#6BBF8A':'#54545C', watchColor:w?'#8E8E99':'#54545C', watchLabel:w?'Watching':'Paused',
        onWatch:()=>this.setState(x=>({watching:{...x.watching,[p.id]:!(x.watching[p.id]!==false)}})),
        rescanText:rescanning?'Rescanning…':'Rescan', onRescan:()=>{ if(st.rescan[p.id])return; this.setState(x=>({rescan:{...x.rescan,[p.id]:true}})); setTimeout(()=>this.setState(x=>({rescan:{...x.rescan,[p.id]:false}})),1000); } }; });

    // add lists
    const mkAdd=(p)=>({glyph:p.glyph,glyphStyle:this.glyphCss(this.tint[p.id],24,9),name:p.name,source:p.source,
      btnText:p.signedOut?'Sign in':'Connected', btnStyle:`font-size:11px;font-weight:600;padding:5px 11px;border-radius:4px;cursor:pointer;border:1px solid ${p.signedOut?'transparent':'#1C1C21'};background:${p.signedOut?A:'transparent'};color:${p.signedOut?'#fff':'#54545C'};flex:none`});
    const addDetected=this.providers.filter(p=>this.detectedIds.includes(p.id)).map(mkAdd);
    const addAll=this.providers.filter(p=>!this.detectedIds.includes(p.id)).map(mkAdd);

    // settings
    const setPlans=this.providers.filter(p=>!p.signedOut).map(p=>({glyph:p.glyph,glyphStyle:this.glyphCss(this.tint[p.id],22,9),name:p.name,
      value:(st.planCost[p.id]!==undefined?st.planCost[p.id]:''), onInput:(e)=>{ const v=e.target.value; this.setState(s=>({planCost:{...s.planCost,[p.id]:v}})); }}));
    const setSources=this.providers.filter(p=>!p.signedOut).map(p=>{ const w=st.watching[p.id]!==false; const rescanning=st.rescan[p.id];
      return {glyph:p.glyph,glyphStyle:this.glyphCss(this.tint[p.id],22,9),name:p.name,path:p.path,
        dot:w?'#6BBF8A':'#54545C', watchColor:w?'#8E8E99':'#54545C', watchLabel:w?'Watching':'Paused',
        onWatch:()=>this.setState(s=>({watching:{...s.watching,[p.id]:!(s.watching[p.id]!==false)}})),
        rescanText:rescanning?'Rescanning…':'Rescan', onRescan:()=>{ if(st.rescan[p.id])return; this.setState(s=>({rescan:{...s.rescan,[p.id]:true}})); setTimeout(()=>this.setState(s=>({rescan:{...s.rescan,[p.id]:false}})),1000); }}; });
    const setVisibility=this.providers.map(p=>{ const on=!st.hidden[p.id]; const tg=this.toggle(on);
      return {glyph:p.glyph,glyphStyle:this.glyphCss(this.tint[p.id],22,9),name:p.name,trackStyle:tg.track,knobStyle:tg.knob,onClick:()=>this.setState(s=>({hidden:{...s.hidden,[p.id]:on}}))}; });
    const setThresholds=[
      {label:'Warn at',value:st.warnAt+'%',dec:()=>this.setState(s=>({warnAt:Math.max(50,s.warnAt-5)})),inc:()=>this.setState(s=>({warnAt:Math.min(s.alertAt-5,s.warnAt+5)}))},
      {label:'Alert at',value:st.alertAt+'%',dec:()=>this.setState(s=>({alertAt:Math.max(s.warnAt+5,s.alertAt-5)})),inc:()=>this.setState(s=>({alertAt:Math.min(100,s.alertAt+5)}))},
    ];
    const swatchHex=['#FF3B70','#5FA88C','#6D93DB','#D2A15C','#B98BD0'];
    const accentSwatches=swatchHex.map(hex=>{ const on=A.toLowerCase()===hex.toLowerCase(); return {onClick:()=>this.setState({accentOverride:hex}),
      style:`width:22px;height:22px;border-radius:50%;background:${hex};cursor:pointer;border:2px solid ${on?'#ECECF1':'transparent'};box-shadow:0 0 0 1px ${on?hex:'transparent'}`}; });
    const setNotif=[
      {label:'Quota alerts',key:'quota'},{label:'Weekly summary',key:'weekly'},
    ].map(n=>{ const on=!!st.notif[n.key]; const tg=this.toggle(on); return {label:n.label,trackStyle:tg.track,knobStyle:tg.knob,onClick:()=>this.setState(s=>({notif:{...s.notif,[n.key]:!s.notif[n.key]}}))}; });
    const updText=st.updChecking?'Checking…':(st.updDone?'You\u2019re up to date':'Last checked 2h ago');
    const updColor=st.updDone?'#6BBF8A':'#54545C';

    // status bar
    const activeAgents=this.providers.filter(p=>!st.hidden[p.id]&&(p.hasTokens||p.quotas.length));
    const confMix = 'reported · local · 1 estimated';
    const status={ dot: st.syncing?'#D2A15C':'#6BBF8A', dotAnim: st.syncing?'animation:tk-blink 1s infinite;':'',
      sync: st.syncing?'Syncing…':('Synced '+st.syncedLabel), conf:'2 reported · 3 local · 1 estimated', hideNarrow:narrow?'display:none;':'',
      path:'~/.tokei/usage.db · 6 sources', btnText: st.syncing?'Syncing…':'Sync now', btnColor: st.syncing?'#54545C':A, onSync:()=>this.doSync() };

    // menu bar
    const gate=st.screen;
    const mbSorted=vis.map(id=>this.providers.find(p=>p.id===id)).sort((a,b)=>b.today-a.today).slice(0,3);
    const mbAgents=mbSorted.map(p=>({glyph:p.glyph,glyphStyle:this.glyphCss(this.tint[p.id],18,8),name:p.name,stat:this.fmtTok(p.today)}));
    const allTime=this.providers.reduce((s,p)=>s+(p.lifetime||0),0);
    const pillBase=`display:inline-flex;align-items:center;gap:6px;padding:2px 8px;border-radius:5px;font-family:ui-monospace,'SF Mono',Menlo,monospace;font-size:11px;font-weight:600;color:#ECECF1;background:rgba(255,59,112,0.12)`;
    const pillPlain=`display:inline-flex;align-items:center;gap:6px;font-family:ui-monospace,'SF Mono',Menlo,monospace;font-size:11px;font-weight:600;color:#ECECF1`;
    let mbPill;
    if(st.mbReadout==='tokens') mbPill={style:pillBase,text:'◷ '+this.fmtTok(todayTotal),showDot:false};
    else if(st.mbReadout==='quota') mbPill={style:pillBase,text:'71%',showDot:true,dot:'#D2A15C'};
    else if(st.mbReadout==='alltime') mbPill={style:pillPlain,text:'Σ '+this.fmtTok(allTime),showDot:false};
    else mbPill={style:pillPlain+';font-size:14px',text:'◷',showDot:false};
    const mbReadoutBtns=[['tokens','Tokens today'],['quota','Tightest quota'],['alltime','All-time'],['icon','Icon only']].map(([k,l])=>({label:l,onClick:()=>this.setState({mbReadout:k}),
      style:`background:${st.mbReadout===k?'#1C1C21':'transparent'};border:1px solid ${st.mbReadout===k?A:'#26262C'};padding:6px 12px;border-radius:5px;cursor:pointer;font-size:11px;color:${st.mbReadout===k?'#ECECF1':'#6E6E78'}`}));

    // dev
    const sizeBtns=[['full','FULL'],['w720','720'],['w640','640×480']].map(([k,l])=>({label:l,onClick:()=>this.setState({sizePreset:k}),
      style:`background:${st.sizePreset===k?'#1C1C21':'transparent'};border:none;padding:4px 9px;border-radius:3px;cursor:pointer;font-family:inherit;font-size:10px;letter-spacing:.05em;color:${st.sizePreset===k?A:'#3E3E45'}`}));
    const devBtns=[['live','LIVE'],['menubar','MENU BAR'],['loading','LOADING'],['error','ERROR'],['empty','EMPTY']].map(([k,l])=>({label:l,onClick:()=>this.setState({screen:k,drillId:null}),
      style:`background:${st.screen===k?'#1C1C21':'transparent'};border:none;padding:4px 9px;border-radius:3px;cursor:pointer;font-family:inherit;font-size:10px;letter-spacing:.05em;color:${st.screen===k?A:'#3E3E45'}`}));

    return {
      frameStyle, accent:A, showApp: gate!=='menubar', showMenubar: gate==='menubar',
      setOverview:()=>this.setState({tab:'overview',drillId:null,kpiMetric:'usage'}), setValue:()=>this.setState({tab:'value',drillId:null}), setConnections:()=>this.setState({tab:'connections',drillId:null}),
      tabOvStyle:tab(isOv&&!st.drillId), tabValStyle:tab(isVal&&!st.drillId), tabConnStyle:tab(isConn&&!st.drillId),
      showRange: gate==='live'&&!st.drillId&&isOv&&st.kpiMetric==='usage', rangeBtns,
      gearStyle:`background:transparent;border:none;width:28px;height:28px;display:flex;align-items:center;justify-content:center;cursor:pointer;color:${st.settingsOpen?A:'#54545C'}`,
      toggleSettings:()=>this.setState({settingsOpen:!st.settingsOpen,addOpen:false}),
      toggleAdd:()=>this.setState({addOpen:!st.addOpen,settingsOpen:false}), contentRef:this.contentRef,
      showEmpty:gate==='empty', showLoading:gate==='loading', showError:gate==='error',
      showDrill:gate==='live'&&!!st.drillId, showOverview:gate==='live'&&!st.drillId&&isOv, showValue:gate==='live'&&!st.drillId&&isVal, showConnections:gate==='live'&&!st.drillId&&isConn,
      showPressure: gate==='live'&&!st.drillId&&!isConn, pressure,
      showStatus: gate==='live', status,
      narrow, skel4:[0,1,2,3,4], retry:()=>this.setState({screen:'live'}),
      selector, heroValue: isOv? heroValueOv : (3.4*t).toFixed(1)+'×', heroSub: md.sub, heroDelta,
      chartEl:this.renderChart(),
      donutEl:this.renderDonut(), donutLegend, splitGrid, weekdayBars, busiestDay, dailyAvg, streakCur, streakBest, heatmapEl:this.renderHeatmap(), peakGlobal, rangeK:this.rangeK(),
      agentCount:this.providers.filter(p=>!st.hidden[p.id]).length, agentGrid, agents,
      tierLabel, tierStyle, valueDelta:'▲ 0.3× vs last month', valueInsight,
      valueGrid, hideNarrow, valueRows,
      valuePlanTotal:'$245.00', valueApiTotal:'$833.40', valueMultipleStatic:'3.4×',
      valueExcluded:'Excluded from total: opencode (usage, no plan cost) · Antigravity (plan set, no token data) · Gemini (not signed in). ~2.8B tokens tracked lifetime.',
      connections, goAgents:()=>this.setState({tab:'connections',drillId:null,settingsOpen:false}),
      ...drill, closeDrill:()=>this.setState({drillId:null}),
      settingsOpen:st.settingsOpen, addOpen:st.addOpen, addDetected, addAll, detectedCount:addDetected.length,
      setPlans, setSources, setVisibility, setThresholds, accentSwatches, setNotif, updText, updColor, checkUpdate:()=>this.checkUpdate(),
      mbTokens:this.fmtTok(todayTotal), mbDelta:'▲ '+(todayTotal/(dt.slice(22,29).reduce((s,v)=>s+v,0)/7)).toFixed(1)+'× avg', mbValue:'3.4×', mbTier:(under.length?'REVIEW':'RIGHT-SIZED'),
      mbQuota:'71%', mbQuotaWho:'Antigravity', mbQuotaDot:'#D2A15C', mbAgents, mbPill, mbReadoutBtns, openFromMenubar:()=>this.setState({screen:'live'}),
      sizeBtns, devBtns,
    };
  }
}
</script>


