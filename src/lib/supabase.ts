import {createClient} from'@supabase/supabase-js';
import type{LudoState}from'../ludo';
const url=import.meta.env.VITE_SUPABASE_URL as string|undefined;const key=import.meta.env.VITE_SUPABASE_ANON_KEY as string|undefined;
export const configured=Boolean(url&&key);export const supabase=configured?createClient(url!,key!,{auth:{persistSession:true,autoRefreshToken:true}}):null;
export type Player={id:string;name:string;avatar:string;ready:boolean;connected:boolean;last_seen_at:string|null};
export type ThisOrThatState={question_id:string|null;question:string|null;option_a:string|null;option_b:string|null;category:string|null;revealed:boolean;submitted:boolean;answers:{seat:number;choice:'A'|'B'}[]|null;matched:boolean|null};
export type State={room_code:string;status:'lobby'|'playing'|'finished';players:Player[];turn_index:number;round:number;scores:number[];category:string;prompt_kind:string|null;prompt_id:string|null;prompt_text:string|null;prompt_category:string|null;prompt_player:number|null;prompt_response:string|null;prompt_done:boolean;recent_ids:string[];game_mode?:'truth_or_dare'|'this_or_that'|'ludo';round_limit?:5|10|20;this_that_category?:'all'|'Romantic'|'Funny'|'Random';this_or_that?:ThisOrThatState|null;ludo_state?:LudoState|null};
export async function ensureAuth(){if(!supabase)throw Error('Add your Supabase URL and anon key to connect.');const{data,error}=await supabase.auth.getSession();if(error)throw error;if(!data.session){const result=await supabase.auth.signInAnonymously();if(result.error)throw result.error;} }
export async function rpc<T>(name:string,args:Record<string,unknown>):Promise<T>{if(!supabase)throw Error('Supabase is not configured yet. Add the two VITE_SUPABASE environment variables.');const{data,error}=await supabase.rpc(name,args);if(error)throw error;return data as T;}
export function friendlyError(error:unknown){
 let msg='Something went wrong while updating your room. Please try again.';
 if(typeof error==='string')msg=error;
 else if(error instanceof Error)msg=error.message;
 else if(error&&typeof error==='object'){
  const detail=error as {message?:unknown;details?:unknown;hint?:unknown};
  const parts=[detail.message,detail.details,detail.hint].filter((part):part is string=>typeof part==='string'&&part.trim().length>0);
  if(parts.length)msg=parts.join(' ');
 }
 if(/invalid|not found/i.test(msg))return'That room code did not work. Double-check it and try again.';
 if(/full|two players/i.test(msg))return'This room already has two players.';
 if(/started/i.test(msg))return'This room has already started.';
 if(/expired/i.test(msg))return'This room has expired.';
 if(/ready/i.test(msg))return'Both hearts need to be ready before the game begins.';
 if(/unauthorized|membership|permission|jwt/i.test(msg))return'Your room connection needs a refresh. Please reload and try again.';
 return msg;
}
