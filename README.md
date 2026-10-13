# Only Us

Only Us is a private, two-player Truth or Dare game for long-distance couples. Players create an account with a name, email and password, then use a six-character room code to meet in the game. Their first shared room links their two profiles, after which their private chat and message history remain available from the account screen between game sessions. The game includes player-written Truth and Dare prompts, skip-without-penalty, scores, session results and rematches. There are no other games, uploads or public profiles.

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
2. Apply every migration in `supabase/migrations` in filename order, using the SQL editor or Supabase CLI (`supabase link`, then `supabase db push`). Migration `20261013000008_accounts_and_couple_chat.sql` adds private profile records and a lasting couple conversation. The two profiles link when the second person joins their first shared room; existing room messages are copied into their shared conversation at that point. Game prompts and state continue to use validated database functions.
3. Enable Realtime for private channels. Policies require the signed-in user to be a member of the relevant game room or linked couple topic. Presence supplies online and typing status. Profile heartbeats update last-seen; game state polls every five seconds and chat reloads on events to recover missed notifications.
4. Set the same URL and public anon/publishable key in local `.env.local` and the GitHub Actions repository secrets `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`.
5. Schedule `public.onlyus_cleanup_expired()` daily using Supabase Cron or another scheduled SQL invocation. Rooms expire after 24 hours; rematch renews that period. Expired rooms and room membership are deleted. Linked profiles and couple messages persist until the project owner or a player deletion workflow removes them. Supabase Auth account records are managed by Supabase.

The app stores account identity with Supabase Auth, display name/avatar, couple membership, private chat messages (up to 1,000 characters), and game room state. The account chat displays the latest 300 messages. Chat history stays available between game sessions and is private to the two linked accounts. Current game prompt and optional Truth answer are cleared when a turn advances, is skipped or the room is rematched. Avoid sharing sensitive information in chat.

## GitHub Pages

The included workflow builds and publishes on pushes to the repository's default branch. In **Settings → Pages**, set **Build and deployment** to **GitHub Actions**. Add the two Actions secrets above. Vite derives the project path from `GITHUB_REPOSITORY` in Actions, so project pages use the repository base path. The app is not deployed unless Pages is enabled and a change is pushed to GitHub.

## Security and current limits

Database functions enforce authenticated membership, room capacity/expiry, two-player start, game turn ownership, score award-once behavior, couple membership for persistent chat, and room/couple-specific private Realtime topics. On the first shared room, the two accounts are linked permanently; linked accounts cannot be paired with another account through a new room. This is a prototype security design, not an independently audited production security claim. Configure Auth rate limits and abuse controls before public launch.

Remote account/chat testing requires the Supabase project to have the latest migration applied and email authentication configured. Do not interpret a successful local build as verification of the hosted Supabase integration.
