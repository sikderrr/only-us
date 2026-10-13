export type LudoTokens = [number[], number[]];
export type LudoMove = {
  seat: number;
  roll: number;
  piece: number | null;
  from?: number;
  to?: number;
  captured?: number[];
  no_moves?: boolean;
  winner?: number;
};
export type LudoState = {
  tokens: LudoTokens;
  dice: number | null;
  last_move: LudoMove | null;
  winner: number | null;
};

export const LUDO_TRACK: readonly [number, number][] = [
  [6,1],[6,2],[6,3],[6,4],[6,5],[5,6],[4,6],[3,6],[2,6],[1,6],[0,6],[0,7],
  [0,8],[1,8],[2,8],[3,8],[4,8],[5,8],[6,9],[6,10],[6,11],[6,12],[6,13],[6,14],
  [7,14],[8,14],[8,13],[8,12],[8,11],[8,10],[8,9],[9,8],[10,8],[11,8],[12,8],[13,8],
  [14,8],[14,7],[14,6],[13,6],[12,6],[11,6],[10,6],[9,6],[8,5],[8,4],[8,3],[8,2],
  [8,1],[8,0],[7,0],[6,0],
];
export const LUDO_SAFE_SQUARES = new Set([0,8,13,21,26,34,39,47]);
export const LUDO_COLORS = ['#e8798f','#7b6bba'] as const;

export function legalLudoPieces(tokens: LudoTokens, seat: number, dice: number | null): number[] {
  if (dice === null || (seat !== 0 && seat !== 1)) return [];
  return tokens[seat].flatMap((progress, piece) => {
    if (progress === -1) return dice === 6 ? [piece] : [];
    return progress + dice <= 57 ? [piece] : [];
  });
}

export function ludoTrackIndex(seat: number, progress: number): number {
  return (seat * 26 + progress) % 52;
}
