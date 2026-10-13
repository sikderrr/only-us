import { motion } from 'framer-motion';
import { RotateCcw, Trophy, Wifi, WifiOff } from 'lucide-react';
import type { State } from './lib/supabase';
import { legalLudoPieces, LUDO_COLORS, LUDO_SAFE_SQUARES, LUDO_TRACK, ludoTrackIndex, type LudoState } from './ludo';

type Props = {
  state: State;
  userId: string;
  busy: boolean;
  connected: boolean;
  onRoll: () => void;
  onMove: (piece: number) => void;
  onRematch: () => void;
};

const CELL = 36;
const START = 30;
const center = (point: readonly [number, number]) => [START + point[0] * CELL + CELL / 2, START + point[1] * CELL + CELL / 2] as const;
const HOME_SPOTS: readonly (readonly [number, number])[][] = [
  [[2,2],[4,2],[2,4],[4,4]],
  [[10,10],[12,10],[10,12],[12,12]],
];
const LANES: readonly (readonly [number, number][])[] = [
  [[7,1],[7,2],[7,3],[7,4],[7,5]],
  [[7,13],[7,12],[7,11],[7,10],[7,9]],
];

function ludo(state: State): LudoState {
  return state.ludo_state ?? { tokens: [[-1,-1,-1,-1],[-1,-1,-1,-1]], dice: null, last_move: null, winner: null };
}

export default function LudoGame({ state, userId, busy, connected, onRoll, onMove, onRematch }: Props) {
  const data = ludo(state);
  const seat = state.players.findIndex(player => player.id === userId);
  const activeSeat = state.turn_index;
  const isMyTurn = seat === activeSeat;
  const legal = legalLudoPieces(data.tokens, seat, isMyTurn ? data.dice : null);
  const winner = data.winner;
  const pointFor = (playerSeat: number, progress: number, piece: number): readonly [number, number] => {
    if (progress < 0) return HOME_SPOTS[playerSeat][piece];
    if (progress < 52) return LUDO_TRACK[ludoTrackIndex(playerSeat, progress)];
    if (progress < 57) return LANES[playerSeat][progress - 52];
    const goals: readonly (readonly [number, number])[] = playerSeat === 0
      ? [[6,6],[7,6],[6,7],[7,7]] : [[8,8],[7,8],[8,7],[7,7]];
    return goals[piece];
  };
  const tokenPositions = (playerSeat: number, progress: number, piece: number) => {
    const point = pointFor(playerSeat, progress, piece);
    const stacked = data.tokens[playerSeat].filter((other, otherPiece) => otherPiece < piece && other === progress).length;
    const nudge = stacked ? (piece % 2 ? 3 : -3) * stacked : 0;
    return center([point[0] + (nudge ? (piece % 2 ? .18 : -.18) : 0), point[1] + (nudge ? (piece % 2 ? -.18 : .18) : 0)]);
  };
  const lastMove = data.last_move;
  const diceFace = ['','⚀','⚁','⚂','⚃','⚄','⚅'];

  return <motion.section className="panel ludo-panel" initial={{ opacity: 0, y: 14 }} animate={{ opacity: 1, y: 0 }}>
    <div className="ludo-topline"><span className="ludo-brand"><span>🎲</span><span><small>ONLY US · TWO PLAYER</small><b>Ludo</b></span></span><span className={`ludo-connection ${connected ? 'online' : ''}`}>{connected ? <Wifi size={14}/> : <WifiOff size={14}/>} {connected ? 'In sync' : 'Reconnecting'}</span></div>
    <div className="ludo-player-row">{state.players.map((player, playerSeat) => <div key={player.id} className={`ludo-player ${playerSeat === activeSeat && !winner ? 'active' : ''}`} style={{ '--piece-color': LUDO_COLORS[playerSeat] } as React.CSSProperties}><span className="ludo-avatar">{player.avatar}</span><span className="ludo-player-name"><b>{player.name}</b><small>{winner !== null ? winner === playerSeat ? 'Winner ✨' : 'Well played' : playerSeat === activeSeat ? 'Your turn' : 'Waiting'}</small></span><span className="ludo-token-count">{data.tokens[playerSeat].filter(token => token === 57).length}/4 home</span></div>)}</div>

    <div className="ludo-board-shell"><svg className="ludo-board" viewBox="0 0 600 600" role="img" aria-label="Ludo board. Tap a highlighted token to move it.">
      <rect x="1" y="1" width="598" height="598" rx="31" fill="#fff" stroke="#ece2e7" strokeWidth="2"/>
      <rect x="18" y="18" width="216" height="216" rx="25" fill="#fff0f3"/><rect x="366" y="18" width="216" height="216" rx="25" fill="#fff8e9"/>
      <rect x="18" y="366" width="216" height="216" rx="25" fill="#eff8f2"/><rect x="366" y="366" width="216" height="216" rx="25" fill="#f2efff"/>
      {HOME_SPOTS.map((spots, playerSeat) => spots.map((point, piece) => { const [cx,cy] = center(point); return <circle key={`home-${playerSeat}-${piece}`} cx={cx} cy={cy} r="15" fill="#fff" stroke={LUDO_COLORS[playerSeat]} strokeOpacity=".27" strokeWidth="3"/>; }))}
      {LUDO_TRACK.map((point, index) => { const [cx,cy] = center(point); const safe = LUDO_SAFE_SQUARES.has(index); const startSeat: 0 | 1 | null = index === 0 ? 0 : index === 26 ? 1 : null; return <g key={`track-${index}`}><rect x={cx-15} y={cy-15} width="30" height="30" rx="7" fill={safe ? startSeat!==null ? LUDO_COLORS[startSeat] : '#fff4d7' : '#fff'} stroke={safe && startSeat!==null ? LUDO_COLORS[startSeat] : '#eadfe5'} strokeWidth="1.5"/>{safe&&startSeat===null&&<text x={cx} y={cy+5} textAnchor="middle" fontSize="14" fill="#d39c62">✦</text>}</g>; })}
      {LANES.map((lane, playerSeat) => lane.map((point,index) => {const [cx,cy]=center(point);return <rect key={`lane-${playerSeat}-${index}`} x={cx-15} y={cy-15} width="30" height="30" rx="7" fill={`${LUDO_COLORS[playerSeat]}${index===4?'ff':'35'}`} stroke="#fff" strokeWidth="1.5"/>;}))}
      <path d="M300 264 L336 300 L300 336 L264 300 Z" fill="#fff" stroke="#eadfe5" strokeWidth="2"/><path d="M300 264 L300 300 L264 300 Z" fill={LUDO_COLORS[0]}/><path d="M300 264 L336 300 L300 300 Z" fill="#efb44f"/><path d="M264 300 L300 300 L300 336 Z" fill="#72b287"/><path d="M336 300 L300 300 L300 336 Z" fill={LUDO_COLORS[1]}/>
      {data.tokens.map((playerTokens, playerSeat) => playerTokens.map((progress, piece) => {
        const [cx,cy] = tokenPositions(playerSeat,progress,piece);
        const playable = playerSeat === seat && legal.includes(piece) && winner === null;
        return <g key={`token-${playerSeat}-${piece}`} className={playable ? 'ludo-token playable' : 'ludo-token'} role={playable ? 'button' : undefined} tabIndex={playable ? 0 : undefined} aria-label={playable ? `Move token ${piece+1}` : `${state.players[playerSeat]?.name ?? 'Player'} token ${piece+1}`} onClick={playable ? () => onMove(piece) : undefined} onKeyDown={playable ? event => { if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); onMove(piece); } } : undefined}>
          {playable&&<circle cx={cx} cy={cy} r="20" fill={LUDO_COLORS[playerSeat]} opacity=".16"></circle>}
          <circle cx={cx} cy={cy} r="13" fill={LUDO_COLORS[playerSeat]} stroke="#fff" strokeWidth="3"/><text x={cx} y={cy+4} textAnchor="middle" fontSize="10" fontWeight="800" fill="#fff">{piece+1}</text>
        </g>;
      }))}
    </svg></div>

    {winner !== null ? <div className="ludo-finish"><Trophy size={25}/><h2>{state.players[winner]?.name} wins!</h2><p>Four tokens made it home. Fancy one more round?</p><button className="button primary" disabled={busy} onClick={onRematch}><RotateCcw size={16}/> Play again</button></div> : <div className="ludo-controls"><div className="ludo-turn-message">{isMyTurn ? data.dice ? legal.length ? data.dice === 6 ? 'A six! Pick a token and take another roll 💗' : 'Choose one of your glowing tokens.' : 'No move this time — the turn has passed.' : 'Roll the dice to begin your turn.' : `${state.players[activeSeat]?.name ?? 'Your person'} is playing…`}</div><div className="ludo-dice-row"><div className={`ludo-die ${data.dice ? 'rolled' : ''}`}>{data.dice ? diceFace[data.dice] : '🎲'}</div>{isMyTurn&&<button className="button primary ludo-roll" disabled={busy||data.dice!==null} onClick={onRoll}>{busy?'Rolling…':data.dice===null?'Roll dice':'Choose a token'}</button>}</div>{lastMove&&<p className="ludo-last-move">{lastMove.no_moves ? `${state.players[lastMove.seat]?.name} rolled ${lastMove.roll} but had no legal move.` : `${state.players[lastMove.seat]?.name} moved token ${(lastMove.piece??0)+1}${lastMove.captured?.length ? ` and captured ${lastMove.captured.length} token${lastMove.captured.length===1?'':'s'}!` : ''}${lastMove.roll===6 || (lastMove.captured?.length??0)>0 ? ' — bonus roll!' : ''}`}</p>}</div>}
  </motion.section>;
}
