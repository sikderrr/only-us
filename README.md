# Only Us

Only Us is a private, two-player Truth or Dare game for long-distance couples. Phase 1 includes a one-tap start lobby once both players have joined, private room chat in the lobby and during play, shared player-written Truth and Dare prompts, skip-without-penalty, score tracking, a session summary and rematches. On each round, one player chooses Truth or Dare, the other writes the prompt, and the chooser responds. Truth answers are typed and shared in the room; Dare responses are confirmed with “I did it!” or skipped. There are no other games, uploads or public profiles.

## Local development

Requirements: Node.js 20.19+ or 22.12+ and npm.

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

Never put a service-role key in this file or any browser environment variable. Without these settings, the welcome page runs but room actions are disabled.

## Supabase setup

1. Create a Supabase project and enable **Anonymous Sign-Ins** under Authentication providers. Auth user sessions identify each player; room codes are not credentials.
2. Apply the migrations in `supabase/migrations` in order, in the SQL editor or with the Supabase CLI (`supabase link`, then `supabase db push`). The original seed migration initializes the prompt catalog; current turns use a validated database flow: the chooser selects Truth or Dare, their partner submits a custom prompt, and only the chooser can answer, complete or skip it. Truth completion requires a shared typed answer. Room chat is read and written only through authenticated member-checked database functions; direct table access is revoked and RLS is enabled.
3. Enable Realtime for private channels. The migration adds `realtime.messages` policies which require the signed-in user to be a member of the room topic. The app sends private game/chat change notifications and tracks presence; Presence supplies online and typing status. A heartbeat updates each player's last-seen time. Game state polls every five seconds and chat reloads on chat events to recover missed notifications.
4. Set the same URL and public anon/publishable key in local `.env.local` and the GitHub Actions repository secrets `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`.
5. Schedule `public.onlyus_cleanup_expired()` daily using Supabase Cron (or your own scheduled SQL invocation). It deletes expired rooms and cascades player membership. Rooms expire 24 hours after creation and rematch renews that window. Supabase Auth anonymous accounts are managed by Supabase; configure its Auth cleanup policy to remove stale anonymous users if desired.

The app stores only room code/status, names, emoji, readiness, last-seen timestamps, scores, the active player-written prompt, an optional answer (up to 500 characters) for the current Truth prompt, and private chat messages (up to 1,000 characters each). The app loads the latest 100 messages; chat history remains available only to room members during that room and is deleted when the 24-hour room expires. The prompt and shared answer are cleared when a turn advances, is skipped, or the room is rematched. Anonymous auth users may persist after a room expires; follow Supabase's anonymous-user cleanup guidance for your project.

## GitHub Pages

The included workflow builds and publishes on pushes to the repository's default branch. In **Settings → Pages**, set **Build and deployment** to **GitHub Actions**. Add the two Actions secrets above before publishing. Vite derives the repository path from `GITHUB_REPOSITORY` in Actions, so project pages use the correct base path. The app is not deployed by this repository setup unless you enable Pages and push to GitHub.

## Security and current limits

Database functions enforce authenticated membership, room capacity, room expiry, the two-player start gate, alternating chooser/prompt-writer roles, typed Truth answers, response ownership, score award-once behavior, member-only chat reads and writes, and room-specific access to private Realtime topics. After both players join, either player can start the shared game with one tap. Room-code collisions are rejected by a primary-key constraint and retried by the client. This is a prototype security design, not an independently audited production security claim. Presence indicates channel connection; last seen is the time of the most recent active room heartbeat. Anonymous auth rate limiting and abuse controls should be configured before a public launch.

The repository does not include private Supabase credentials. The chat migration is applied to the configured project, but a complete two-phone chat, typing and reconnect session has not been independently verified here.
