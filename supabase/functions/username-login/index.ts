import { withSupabase } from 'npm:@supabase/server@1'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Content-Type': 'application/json',
}

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: corsHeaders })

async function fingerprint(value: string) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value))
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, '0')).join('')
}

const handleLogin = withSupabase({ auth: 'none' }, async (request, context) => {
  if (request.method !== 'POST') return json({ message: 'Method not allowed' }, 405)

  let payload: { username?: unknown; password?: unknown }
  try {
    const text = await request.text()
    if (text.length > 4096) return json({ message: 'Invalid sign-in details.' }, 400)
    payload = JSON.parse(text)
  } catch {
    return json({ message: 'Invalid sign-in details.' }, 400)
  }

  const username = typeof payload.username === 'string' ? payload.username.trim().replace(/^@/, '').toLowerCase() : ''
  const password = typeof payload.password === 'string' ? payload.password : ''
  if (!/^[a-z][a-z0-9_]{2,19}$/.test(username) || password.length < 8 || password.length > 256) {
    return json({ message: 'That username and password did not match.' }, 401)
  }

  // Supabase's proxy supplies the caller address. Only hashed, short-lived
  // fingerprints are stored; credentials and raw addresses are never logged.
  const address = request.headers.get('cf-connecting-ip')
    ?? request.headers.get('x-forwarded-for')?.split(',')[0]?.trim()
    ?? 'unknown'
  const rateKeys = await Promise.all([
    fingerprint(`ip:${address}`),
    fingerprint(`username:${address}:${username}`),
  ])
  const admin = context.supabaseAdmin

  for (const key of rateKeys) {
    const { data, error } = await admin.rpc('onlyus_username_login_limit', {
      p_fingerprint: key,
      p_action: 'check',
    })
    if (error) return json({ message: 'Sign-in is temporarily unavailable. Please try again shortly.' }, 503)
    if (data !== true) return json({ message: 'Too many attempts. Please wait 15 minutes and try again.' }, 429)
  }

  const failAttempt = async () => {
    for (const key of rateKeys) {
      await admin.rpc('onlyus_username_login_limit', { p_fingerprint: key, p_action: 'failure' })
    }
  }

  const { data: profile, error: profileError } = await admin
    .from('onlyus_profiles')
    .select('user_id')
    .eq('username', username)
    .maybeSingle()

  if (profileError) return json({ message: 'Sign-in is temporarily unavailable. Please try again shortly.' }, 503)

  let email = ''
  if (profile?.user_id) {
    const { data: account, error: accountError } = await admin.auth.admin.getUserById(profile.user_id)
    if (accountError) return json({ message: 'Sign-in is temporarily unavailable. Please try again shortly.' }, 503)
    email = account.user?.email ?? ''
  }

  // Send an unknown username through the same Auth password endpoint to avoid
  // returning an email address or giving a direct username-existence signal.
  const signIn = await context.supabase.auth.signInWithPassword({
    email: email || 'unknown-account@only-us.invalid',
    password,
  })

  if (signIn.error || !signIn.data.session) {
    await failAttempt()
    return json({ message: 'That username and password did not match.' }, 401)
  }

  // Clear the per-username bucket after a valid login. Keep the per-IP bucket
  // so repeated successful sign-ins cannot erase a password-spray throttle.
  for (const key of rateKeys.slice(1)) {
    await admin.rpc('onlyus_username_login_limit', { p_fingerprint: key, p_action: 'success' })
  }

  return json({
    access_token: signIn.data.session.access_token,
    refresh_token: signIn.data.session.refresh_token,
  })
})

export default {
  fetch(request: Request) {
    if (request.method === 'OPTIONS') return Promise.resolve(new Response('ok', { headers: corsHeaders }))
    return handleLogin(request)
  },
}
