# Only Us

Only Us is a private social space for people who want to stay close. Accounts use Supabase Auth; each account has a unique username, optional display name and emoji avatar. People can find one another by username, send and accept friend requests, and have persistent private direct conversations. The existing two-player Truth or Dare rooms and in-game chat remain separate and available. There are no public feeds, uploads or other games.

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
2. Apply every migration in `supabase/migrations` in filename order, using the SQL editor or Supabase CLI (`supabase link`, then `supabase db push`). Migration `20261013000008_accounts_and_couple_chat.sql` adds the existing private couple-chat feature. Migration `20261013000009_social_profiles_friends_and_dm.sql` adds username claims, friend requests, canonical friendships, persistent direct conversations, message read cursors, and private Realtime topic policies. Existing profiles keep their Auth identity and game history; users without usernames are routed to profile setup after login. Existing room messages and the pre-existing linked-couple chat are retained.
3. Keep Realtime enabled for private channels. Room and couple policies from earlier migrations remain in place. The latest migration restricts direct-message topics to conversation members and user topics to the profile owner, friends, or pending request partners. Presence supplies online and typing status; a profile heartbeat updates last-seen. Social lists poll as a recovery path if a broadcast is missed.
4. Set the same URL and public anon/publishable key in local `.env.local` and the GitHub Actions repository secrets `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`.
5. Schedule `public.onlyus_cleanup_expired()` daily using Supabase Cron or another scheduled SQL invocation. Rooms expire after 24 hours; rematch renews that period. Expired rooms and room membership are deleted. Social search throttling records are retained only while the Auth account exists and are deleted by Auth-user cascade. Friendships, requests, profiles, direct conversations and direct messages persist until a user deletes their Auth account or a project-owner retention process removes them. Removing a friend keeps the old direct conversation readable but prevents new messages until friendship is restored. Supabase Auth account records are managed by Supabase.

The app stores account identity with Supabase Auth, username/display name/avatar, friend relationships, direct messages (up to 2,000 characters), the existing linked-couple chat (up to 1,000 characters), and game-room state. Direct message history is loaded in batches of up to 60; the existing account chat displays up to 300 messages. Auth-user deletion cascades through social records. Rooms continue to expire through the existing cleanup function. Current game prompt and optional Truth answer are cleared when a turn advances, is skipped or the room is rematched. Avoid sharing sensitive information in chat.

## GitHub Pages

The included workflow builds and publishes on pushes to the repository's default branch. In **Settings → Pages**, set **Build and deployment** to **GitHub Actions**. Add the two Actions secrets above. Vite derives the project path from `GITHUB_REPOSITORY` in Actions, so project pages use the repository base path. The app is not deployed unless Pages is enabled and a change is pushed to GitHub.

## Security and current limits

Database functions enforce username format/uniqueness, profile ownership, friend-request transitions, unique pair friendships and conversations, accepted-friend checks for message sends, participant-bound message ownership, read-cursor ownership, and social Realtime topic membership. Discover search is authenticated, debounced in the UI, capped at 20 results, and database-throttled to one query per 300 ms per user. The earlier game functions continue enforcing room capacity/expiry, two-player start, game turn ownership and score award-once behavior. The older first-shared-room couple chat remains separate and is still linked permanently by its existing design. This design has not had an independent security audit; configure Supabase Auth rate limits and abuse monitoring before a public launch.

Automated local checks cover username normalization/rules and the existing game logic; they do not emulate PostgreSQL transactions, RLS or Realtime. Remote social integration testing requires migration `20261013000009` to be applied to the Supabase project and two confirmed accounts. It was not run as part of local development. Test discovery, friend requests under concurrent actions, room regression, two-user message isolation, read cursors, reconnects, presence and removing/re-adding friends with two separate accounts before relying on the hosted integration. Do not interpret a successful local build as verification of Supabase policies or hosted multiplayer.
