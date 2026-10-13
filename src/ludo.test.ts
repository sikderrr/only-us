import { describe, expect, it } from 'vitest';
import { legalLudoPieces, ludoTrackIndex, type LudoTokens } from './ludo';

describe('Ludo movement rules', () => {
  const tokens: LudoTokens = [[-1, 4, 55, 57], [-1, 12, 56, 57]];

  it('requires a six to bring a token out of the yard', () => {
    expect(legalLudoPieces(tokens, 0, 5)).toEqual([1]);
    expect(legalLudoPieces(tokens, 0, 6)).toEqual([0, 1]);
  });

  it('requires an exact roll to reach home and never moves a finished token', () => {
    expect(legalLudoPieces(tokens, 0, 2)).toEqual([1, 2]);
    expect(legalLudoPieces(tokens, 0, 3)).toEqual([1]);
    expect(legalLudoPieces(tokens, 0, null)).toEqual([]);
  });

  it('maps each player onto opposite halves of the shared 52-square track', () => {
    expect(ludoTrackIndex(0, 0)).toBe(0);
    expect(ludoTrackIndex(1, 0)).toBe(26);
    expect(ludoTrackIndex(1, 26)).toBe(0);
  });
});
