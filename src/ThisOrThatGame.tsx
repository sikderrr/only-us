import { motion } from 'framer-motion';
import { Heart, LoaderCircle, RotateCcw, Sparkles } from 'lucide-react';
import type { State } from './lib/supabase';
import { compatibilityPercent } from './thisOrThatCatalog';

type Props = {
  state: State;
  userId: string;
  busy: boolean;
  connected: boolean;
  onChoose: (choice: 'A' | 'B') => void;
  onNext: () => void;
  onRematch: () => void;
};

export default function ThisOrThatGame({state,userId,busy,connected,onChoose,onNext,onRematch}:Props) {
  const roundLimit=state.round_limit??10;
  const game=state.this_or_that;
  const players=[state.players[0],state.players[1]];
  const answers=game?.answers??[];
  const choiceFor=(seat:number)=>answers.find(answer=>answer.seat===seat)?.choice;
  const percent=compatibilityPercent(Math.min(state.scores[0]??0,state.scores[1]??0),roundLimit);

  if(state.status==='finished') return <motion.section className="panel tat-panel" initial={{opacity:0,y:12}} animate={{opacity:1,y:0}}>
    <div className="tat-sparkle" aria-hidden="true">💞</div>
    <p className="eyebrow">YOUR LITTLE LOVE LAB</p>
    <h1 className="tat-result-title">A perfect little match</h1>
    <p className="muted">You chose alike in {Math.min(state.scores[0]??0,state.scores[1]??0)} of {roundLimit} rounds.</p>
    <div className="tat-compatibility" role="img" aria-label={`${percent}% compatibility`}><strong>{percent}%</strong><span>on the same wavelength</span></div>
    <div className="tat-result-scores">{players.map((player,seat)=>player&&<div key={player.id}><span>{player.avatar}</span><b>{player.name}</b><strong>{state.scores[seat]??0}<small> hearts</small></strong></div>)}</div>
    <p className="tat-footnote">Every answer is a little way to learn each other. 💗</p>
    <button className="button primary" disabled={busy} onClick={onRematch}><RotateCcw size={16}/> Play again</button>
  </motion.section>;

  if(!game?.question||!game.option_a||!game.option_b) return <section className="panel tat-panel"><div className="tat-wait"><LoaderCircle className="spin" size={20}/> Getting your next question…</div></section>;

  return <motion.section className="panel gamepanel tat-panel" initial={{opacity:0,y:12}} animate={{opacity:1,y:0}}>
    <div className="gamehead"><span className="round">ROUND {state.round} OF {roundLimit}</span><span className="score">{players.map((player,seat)=>player&&<span key={player.id}>{player.avatar} {state.scores[seat]??0}</span>)}</span></div>
    <div className="tat-status"><span className={`tat-status-dot ${connected?'connected':''}`}/>{connected?'In sync together':'Reconnecting…'}<span className="tat-category">{game.category??'A little mix'}</span></div>
    <motion.div key={game.question_id??state.round} className="tat-question-card" initial={{opacity:0,scale:.96,y:7}} animate={{opacity:1,scale:1,y:0}} transition={{duration:.24}}>
      <span className="tat-hearts" aria-hidden="true">✦　♡　✦</span>
      <p className="tat-question-kicker">PICK WHAT FEELS MORE YOU</p>
      <h1>{game.question}</h1>
    </motion.div>
    <div className="tat-options" aria-label="Choose your answer">
      <button className={`tat-option tat-option-a ${game.submitted?'locked':''}`} onClick={()=>onChoose('A')} disabled={busy||game.submitted||game.revealed}>
        <span className="tat-option-label">A</span><span>{game.option_a}</span>
      </button>
      <span className="tat-or">OR</span>
      <button className={`tat-option tat-option-b ${game.submitted?'locked':''}`} onClick={()=>onChoose('B')} disabled={busy||game.submitted||game.revealed}>
        <span className="tat-option-label">B</span><span>{game.option_b}</span>
      </button>
    </div>
    <div className="tat-private-status" aria-live="polite">
      {game.revealed? <>
        <div className={`tat-reveal ${game.matched?'matched':''}`}>
          <motion.span initial={{scale:.5,opacity:0}} animate={{scale:1,opacity:1}} transition={{type:'spring',stiffness:260,damping:15}}>{game.matched?'💞':'💫'}</motion.span>
          <div><b>{game.matched?'Hearts in sync!':'Two lovely choices'}</b><small>{game.matched?'You both picked the same — one heart each!':'Different answers, just as lovely.'}</small></div>
          {game.matched&&<Heart className="tat-earned-heart" fill="currentColor" size={18}/>}
        </div>
        <div className="tat-reveal-summary" aria-label="Both answers revealed">
          {players.map((player,seat)=>player&&<span key={player.id}><b>{player.avatar} {player.name}</b><small>{choiceFor(seat)==='A'?game.option_a:game.option_b}</small></span>)}
        </div>
        <button className="button primary" disabled={busy} onClick={onNext}>{busy?<><LoaderCircle size={16} className="spin"/> One moment…</>:state.round>=roundLimit?'See your results ✨':'Next little question →'}</button>
      </>:game.submitted?<div className="tat-wait"><span className="tat-lock">🔒</span><span>Your choice is tucked away. Waiting for {players.find(player=>player?.id!==userId)?.name??'your person'}…</span></div>:<div className="tat-hint"><Sparkles size={14}/><span>Choose quietly — you’ll reveal together after both hearts lock in.</span></div>}
    </div>
    <p className="tat-skip-note">No wrong answers. Just pick what feels right for you. 💗</p>
  </motion.section>;
}
