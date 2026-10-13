# Only Us

Only Us is a private social space for people who want to stay close. Accounts use Supabase Auth; each account has a unique username, optional display name and emoji avatar. People can find one another by username, send and accept friend requests, and have persistent private direct conversations. Two people can play Truth or Dare or the synchronized **This or That 💞** game in the same private two-player rooms. There are no public feeds or uploads.

## Local development

Requirements: Node.js 20.19+ or 22.12+ and pnpm.

```sh
pnpm install
pnpm dev
pnpm test
pnpm build
```

Create `.env.local` with the public Supabase project URL and anon/publishable key:

```dotenv
VITE_SUPABASE_URL=https://YOUR_PROJECT.supabase.co
VITE_SUPABASE_ANON_KEY=YOUR_PUBLIC_ANON_OR_PUBLISHABLE_KEY
```

Never put a service-role key in this file or any browser environment variable. The public key is safe to expose only with the restrictive database policies and functions in these migrations.

## Supabase setup

1. Create a Supabase project and enable the **Email** provider under Authentication → Providers. Players use email for account recovery and a password with at least eight characters. Configure email delivery and add `https://sikderrr.github.io/only-us/` under Authentication → URL Configuration → Redirect URLs so password reset links can return to the live app. For local development, also allow `http://localhost:5173/`. Existing anonymous sessions from an earlier version can be upgraded to email/password accounts without losing their user identity.
2. Apply every migration in `supabase/migrations` in filename order, using the SQL editor or Supabase CLI (`supabase link`, then `supabase db push`). Migration `20261013000008_accounts_and_couple_chat.sql` adds the existing private couple-chat feature. Migration `20261013000009_social_profiles_friends_and_dm.sql` adds usernames, friend requests, friendships, persistent direct conversations, read cursors and private Realtime topic policies. Migration `20261013000010_username_login_rate_limits.sql` creates private, short-lived hashed rate-limit records for username sign-in. Migration `20261013000012_this_or_that.sql` adds the second room game mode, its 135 question rows, private locked answers and membership-checked game transitions. Existing profiles keep their Auth identity and game history; users without usernames are routed to profile setup after login. Existing room messages and the pre-existing linked-couple chat are retained.
3. Deploy the `username-login` Supabase Edge Function with `supabase functions deploy username-login` after linking the project. The function uses Supabase's server-managed privileged client only to resolve a username to its Auth user, then checks the password through Supabase Auth. It returns the resulting session but never returns the account email. Keep function JWT verification enabled, never add a secret/service-role key to the frontend, and do not deploy the frontend's username-login UI before the function is deployed. The function applies short-lived hashed IP/username attempt limits; it does not log usernames, passwords or raw addresses.
4. Keep Realtime enabled for private channels. Room and couple policies from earlier migrations remain in place. The social migration restricts direct-message topics to conversation members and user topics to the profile owner, friends, or pending request partners. Presence supplies online and typing status; a profile heartbeat updates last-seen. Social lists poll as a recovery path if a broadcast is missed.
5. Set the same URL and public anon/publishable key in local `.env.local` and the GitHub Actions repository secrets `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`.
6. Schedule `public.onlyus_cleanup_expired()` daily using Supabase Cron or another scheduled SQL invocation. Rooms expire after 24 hours; rematch renews that period. Expired rooms and room membership are deleted. Social search throttling records are retained only while the Auth account exists and are deleted by Auth-user cascade. Username-login rate-limit fingerprints are purged after 24 hours. Friendships, requests, profiles, direct conversations and direct messages persist until a user deletes their Auth account or a project-owner retention process removes them. Removing a friend keeps the old direct conversation readable but prevents new messages until friendship is restored. Supabase Auth account records are managed by Supabase.

The app stores account identity with Supabase Auth, username/display name/avatar, friend relationships, direct messages (up to 2,000 characters), the existing linked-couple chat (up to 1,000 characters), and game-room state. Direct message history is loaded in batches of up to 60; the existing account chat displays up to 300 messages. Auth-user deletion cascades through social records. Rooms continue to expire through the existing cleanup function. Current game prompt and optional Truth answer are cleared when a turn advances, is skipped or the room is rematched. Avoid sharing sensitive information in chat.

## This or That 💞

The room host can select Truth or Dare or This or That in the shared room lobby. For This or That, the host chooses 5, 10 or 20 rounds and a Romantic, Funny, Random or mixed question set. The prompt catalog contains 135 bundled and seeded questions (45 per category); Supabase selects each round's prompt and keeps a rolling recent-question list to reduce repeats. Both room members must lock an A/B answer before either choice is returned in the authorized room-state RPC. Direct table access to the answer records is revoked for browser roles; scores update once, inside the answer RPC, only when both choices match. Either player can advance a revealed round. The final summary shows matched answers as both players' hearts and a compatibility percentage.

Unrevealed answer rows are available only through security-definer functions that verify room membership. They are deleted when a round advances, when the room is rematched, or when its room row expires; the last round's answers remain until rematch or room cleanup. The question catalog and category are not private. The frontend uses the private `room:CODE` channel only for a content-free change signal; it never broadcasts choices. Apply migration `20261013000012_this_or_that.sql` before selecting This or That in a live room. The existing Truth or Dare default remains available for rooms created before the migration.

## GitHub Pages

The included workflow builds and publishes on pushes to the repository's default branch. In **Settings → Pages**, set **Build and deployment** to **GitHub Actions**. Add the two Actions secrets above. Vite derives the project path from `GITHUB_REPOSITORY` in Actions, so project pages use the repository base path. The app is not deployed unless Pages is enabled and a change is pushed to GitHub.

## Security and current limits

Database functions enforce username format/uniqueness, profile ownership, friend-request transitions, unique pair friendships and conversations, accepted-friend checks for message sends, participant-bound message ownership, read-cursor ownership, and social Realtime topic membership. Discover search is authenticated, debounced in the UI, capped at 20 results, and database-throttled to one query per 300 ms per user. The earlier game functions continue enforcing room capacity/expiry, two-player start, game turn ownership and score award-once behavior. The older first-shared-room couple chat remains separate and is still linked permanently by its existing design. This design has not had an independent security audit; configure Supabase Auth rate limits and abuse monitoring before a public launch.

Automated local checks cover username rules, existing Truth or Dare logic, the 135-question This or That catalog, matching-score rules and compatibility calculation; they do not emulate PostgreSQL transactions, RLS or Realtime. Remote social/game integration testing requires the relevant migrations to be applied to Supabase and two confirmed accounts. It was not run during this change. Test friend discovery, room regression, simultaneous hidden-answer submissions, reveal isolation, duplicate/stale actions, reconnects, scoring and rematches with two separate accounts before relying on the hosted multiplayer flow. Do not interpret a successful local build as verification of Supabase policies or multiplayer security.
