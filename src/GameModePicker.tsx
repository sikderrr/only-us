import { Heart, Sparkles } from 'lucide-react';
import type { State } from './lib/supabase';

type Props={state:State;userId:string|null;busy:boolean;onChoose:(game:'truth_or_dare'|'this_or_that',rounds:5|10|20,category:'all'|'Romantic'|'Funny'|'Random')=>void};

export default function GameModePicker({state,userId,busy,onChoose}:Props){
  const host=state.players[0]?.id===userId;
  const game=state.game_mode??'truth_or_dare';
  const rounds=(state.round_limit??10) as 5|10|20;
  const category=state.this_that_category??'all';
  const select=(mode:'truth_or_dare'|'this_or_that',count:5|10|20=rounds,filter:'all'|'Romantic'|'Funny'|'Random'=category)=>onChoose(mode,count,filter);
  return <section className="game-mode-picker" aria-labelledby="game-picker-title">
    <div className="game-picker-heading"><span className="social-kicker">PICK YOUR LITTLE ADVENTURE</span><h2 id="game-picker-title">What shall we play?</h2><p>You can change the game before starting.</p></div>
    <div className="game-mode-cards">
      <button type="button" className={`game-mode-card ${game==='truth_or_dare'?'chosen':''}`} disabled={!host||state.players.length!==2||busy} onClick={()=>select('truth_or_dare')} aria-pressed={game==='truth_or_dare'}>
        <span className="game-mode-icon">💌</span><span><b>Truth or Dare</b><small>Write sweet prompts for each other</small></span>{game==='truth_or_dare'&&<Heart size={16} fill="currentColor"/>}
      </button>
      <button type="button" className={`game-mode-card ${game==='this_or_that'?'chosen':''}`} disabled={!host||state.players.length!==2||busy} onClick={()=>select('this_or_that')} aria-pressed={game==='this_or_that'}>
        <span className="game-mode-icon tat-mode-icon">💞</span><span><b>This or That</b><small>Secret picks, revealed together</small></span>{game==='this_or_that'&&<Heart size={16} fill="currentColor"/>}
      </button>
    </div>
    {game==='this_or_that'&&<div className="game-picker-options">
      <div><span className="picker-label">ROUNDS</span><div className="picker-chips">{([5,10,20] as const).map(count=><button key={count} type="button" className={rounds===count?'selected':''} disabled={!host||state.players.length!==2||busy} onClick={()=>select('this_or_that',count,category)} aria-pressed={rounds===count}>{count}</button>)}</div></div>
      <div><span className="picker-label">QUESTION MIX</span><div className="picker-chips">{(['all','Romantic','Funny','Random'] as const).map(value=><button key={value} type="button" className={category===value?'selected':''} disabled={!host||state.players.length!==2||busy} onClick={()=>select('this_or_that',rounds,value)} aria-pressed={category===value}>{value==='all'?'All':value}</button>)}</div></div>
    </div>}
    {state.players.length<2?<p className="picker-note"><Sparkles size={13}/> Your person can join with this room code first.</p>:!host?<p className="picker-note"><Heart size={13}/> The room host is choosing your game.</p>:<p className="picker-note">{game==='this_or_that'?`${rounds} rounds · ${category==='all'?'all question mixes':category}`:'Both can play once the host taps Start.'}</p>}
  </section>;
}
