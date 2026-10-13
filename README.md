# Only Us

Only Us is a private, two-player Truth or Dare game for long-distance couples. Phase 1 includes a one-tap start lobby once both players have joined, player-written Truth and Dare prompts shared with both phones, skip-without-penalty, score tracking, a session summary and rematches. There are no other games, chat, uploads or public profiles.

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
2. Apply the migrations in `supabase/migrations` in order, in the SQL editor or with the Supabase CLI (`supabase link`, then `supabase db push`). The seed migration initializes the original prompt catalog; current gameplay sends the active player's custom prompt to a validated database function, which checks room membership and turn ownership before sharing it as authoritative room state. The client only invokes authenticated RPCs; direct table access is revoked and RLS is enabled.
3. Enable Realtime for private channels. The migration adds `realtime.messages` policies which require the signed-in user to be a member of the room topic. The app sends private change notifications and tracks presence. State refresh also polls every five seconds to recover missed notifications.
4. Set the same URL and public anon/publishable key in local `.env.local` and the GitHub Actions repository secrets `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`.
5. Schedule `public.onlyus_cleanup_expired()` daily using Supabase Cron (or your own scheduled SQL invocation). It deletes expired rooms and cascades player membership. Rooms expire 24 hours after creation and rematch renews that window. Supabase Auth anonymous accounts are managed by Supabase; configure its Auth cleanup policy to remove stale anonymous users if desired.

The app stores only room code/status, names, emoji, readiness, scores, the active player-written prompt, an optional answer (up to 500 characters) for the current Truth prompt and a short recent-prompt history. The prompt is visible to both room members and is cleared when the prompt advances, is skipped, or the room is rematched. A shared answer is also visible to both and cleared at the same time. Names, prompts, answers and scores are removed with an expired room. No message history is stored. Anonymous auth users may persist after a room expires; follow Supabase's anonymous-user cleanup guidance for your project.

## GitHub Pages

The included workflow builds and publishes on pushes to the repository's default branch. In **Settings → Pages**, set **Build and deployment** to **GitHub Actions**. Add the two Actions secrets above before publishing. Vite derives the repository path from `GITHUB_REPOSITORY` in Actions, so project pages use the correct base path. The app is not deployed by this repository setup unless you enable Pages and push to GitHub.

## Security and current limits

Database functions enforce authenticated membership, room capacity, room expiry, the two-player start gate, turn ownership, score award-once behavior, prompt selection and room-specific access to private Realtime topics. After both players join, either player can start the shared game with one tap. Room-code collisions are rejected by a primary-key constraint and retried by the client. This is a prototype security design, not an independently audited production security claim. Presence indicates channel connection; the member list reports persistent membership and not verified device reachability. Anonymous auth rate limiting and abuse controls should be configured before a public launch.

No live Supabase project credentials are included. Therefore remote room creation, RLS policies, Realtime authorization, two-device synchronization and scheduled cleanup have not been integration-tested here.
