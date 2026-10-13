import{describe,it,expect}from'vitest';import{normalizeUsername,usernameError}from'./username';
describe('username rules',()=>{
 it('normalizes whitespace and case',()=>expect(normalizeUsername('  Pink_Rose  ')).toBe('pink_rose'));
 it('accepts the supported format and boundaries',()=>{expect(usernameError('love_123')).toBeNull();expect(usernameError('a'.repeat(20))).toBeNull()});
 it('rejects short, long, spaced, symbolic, reserved and non-letter prefixes',()=>{for(const name of ['ab','a'.repeat(21),'two hearts','love!','_love','admin'])expect(usernameError(name)).not.toBeNull()});
});
