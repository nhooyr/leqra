package Leqra::Network;
use strict;
use warnings;
use Exporter 'import';
our @EXPORT_OK = qw(ordered_delay_script);
sub ordered_delay_script { return <<'JAVASCRIPT';
(()=>{
 window.__lag={base:60,jitter:[0,45,8,27,65,2,30,12],enabled:true};
 window.__sockets=[];const Native=window.WebSocket;
 class OrderedDelay{
  constructor(){this.items=[];this.due=0;this.timer=null;this.n=0;}
  push(run){
   const l=window.__lag,delay=l.enabled?l.base+l.jitter[this.n++%l.jitter.length]:0;
   this.due=Math.max(performance.now()+delay,this.due);
   this.items.push({due:this.due,run});
   if(this.timer===null)this.drain();
  }
  drain(){
   this.timer=null;
   while(this.items.length&&this.items[0].due<=performance.now())this.items.shift().run();
   if(this.items.length)this.timer=setTimeout(()=>this.drain(),Math.max(1,this.items[0].due-performance.now()));
  }
 }
 window.WebSocket=class extends Native{
  constructor(...args){super(...args);this._incoming=new OrderedDelay();this._outgoing=new OrderedDelay();
   window.__sockets.push(this);
   this.addEventListener('message',e=>this._incoming.push(()=>{
    if(this.readyState===Native.OPEN&&this._message)this._message.call(this,e);
   }));
  }
  set onmessage(fn){this._message=fn}get onmessage(){return this._message}
  send(data){this._outgoing.push(()=>{if(this.readyState===Native.OPEN)super.send(data)});}
 };
 window.__record=false;window.__frames=[];
 function capture(at){
  if(window.__record&&window.leqra){const s=leqra.getState();window.__frames.push({at,phase:s.phase,tanks:s.tanks,net:s.online});}
  requestAnimationFrame(capture);
 }
 requestAnimationFrame(capture);
})();
JAVASCRIPT
}
1;
