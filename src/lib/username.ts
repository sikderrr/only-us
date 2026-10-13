export const usernamePattern=/^[a-z][a-z0-9_]{2,19}$/;
const reserved=new Set(['admin','administrator','support','help','onlyus','only_us','system','moderator','null','undefined','root','official']);
export function normalizeUsername(value:string){return value.trim().toLowerCase()}
export function usernameError(value:string){const name=normalizeUsername(value);if(!usernamePattern.test(name))return 'Use 3–20 letters, numbers or underscores. Start with a letter.';if(reserved.has(name))return 'Please choose a different username.';return null}
