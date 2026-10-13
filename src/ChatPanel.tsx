import {useEffect,useRef,useState} from 'react';
import {Heart,Send} from 'lucide-react';
import type {Player} from './lib/supabase';

export type ChatMessage={id:number;player_id:string;body:string;created_at:string};
type Props={messages:ChatMessage[];meId:string|null;partner?:Player;online:boolean;typing:boolean;lastSeen:string|null;sending:boolean;onSend:(body:string)=>void;onTyping:()=>void};

function seenLabel(value:string|null){
 if(!value)return 'Not seen yet';
 const ago=Math.max(0,Date.now()-new Date(value).getTime());
 if(ago<60_000)return 'Last seen just now';
 if(ago<3_600_000)return `Last seen ${Math.floor(ago/60_000)}m ago`;
 if(ago<86_400_000)return `Last seen ${Math.floor(ago/3_600_000)}h ago`;
 return `Last seen ${new Date(value).toLocaleDateString([], {month:'short',day:'numeric'})}`;
}

export default function ChatPanel({messages,meId,partner,online,typing,lastSeen,sending,onSend,onTyping}:Props){
 const [draft,setDraft]=useState('');
 const endRef=useRef<HTMLDivElement>(null);
 useEffect(()=>{endRef.current?.scrollIntoView({behavior:'smooth',block:'end'});},[messages]);
 const send=()=>{const body=draft.trim();if(!body||sending)return;onSend(body);setDraft('')};
 return <section className="chat-panel" aria-label="Private room chat">
  <header className="chat-header"><div className="chat-avatar">{partner?.avatar??'💌'}<span className={`chat-online-dot ${online?'is-online':''}`}/></div><div className="chat-contact"><b>{partner?.name??'Your person'}</b><small aria-live="polite">{typing?'typing…':online?'online':seenLabel(lastSeen)}</small></div><Heart className="chat-heart" size={17} fill="currentColor"/></header>
  <div className="chat-messages" role="log" aria-live="polite" aria-label="Chat messages">
   {messages.length===0&&<div className="chat-empty"><span>💌</span><b>This little chat is just for you two</b><small>Send your first message whenever you like.</small></div>}
   {messages.map(message=><div key={message.id} className={`chat-line ${message.player_id===meId?'mine':'theirs'}`}><div className="chat-bubble"><p>{message.body}</p><time dateTime={message.created_at}>{new Date(message.created_at).toLocaleTimeString([], {hour:'numeric',minute:'2-digit'})}</time></div></div>)}
   {typing&&<div className="chat-line theirs"><div className="chat-typing" aria-label={`${partner?.name??'Your person'} is typing`}><i/><i/><i/></div></div>}
   <div ref={endRef}/>
  </div>
  <form className="chat-compose" onSubmit={e=>{e.preventDefault();send()}}><input aria-label="Write a message" value={draft} maxLength={1000} onChange={e=>{setDraft(e.target.value);onTyping()}} placeholder="Message your person…"/><button type="submit" disabled={sending||!draft.trim()} aria-label="Send message"><Send size={17}/></button></form>
 </section>;
}
