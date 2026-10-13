import { describe, expect, it } from 'vitest';
import { compatibilityPercent, scoreAnswers, thisOrThatCategories, thisOrThatQuestions } from './thisOrThatCatalog';

describe('This or That question catalog', () => {
  it('includes 120 or more original questions across all three categories', () => {
    expect(thisOrThatQuestions).toHaveLength(135);
    for (const category of thisOrThatCategories) {
      const questions=thisOrThatQuestions.filter(question => question.category === category);
      expect(questions).toHaveLength(45);
      expect(questions.every(question=>question.question&&question.a&&question.b&&question.a!==question.b)).toBe(true);
    }
  });

  it('gives both players one point only when both answers match', () => {
    expect(scoreAnswers([2, 4], ['A', 'A'])).toEqual([3, 5]);
    expect(scoreAnswers([2, 4], ['A', 'B'])).toEqual([2, 4]);
  });

  it('calculates compatibility from matched answers and round count', () => {
    expect(compatibilityPercent(4, 5)).toBe(80);
    expect(compatibilityPercent(0, 0)).toBe(0);
  });
});
