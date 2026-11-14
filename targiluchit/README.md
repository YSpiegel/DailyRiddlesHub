# תרגילוחית

A daily number puzzle. The hosted game uses a Supabase project for Google sign-in, shared daily riddles, and the daily leaderboard. Until configured it runs as a browser-local guest game and clearly marks the leaderboard as unconnected.

## Set up Supabase

1. Create or select a Supabase project. Run `supabase/schema.sql` and then `supabase/normalize_equations.sql` in its SQL editor. These create protected tables and RPC functions, including equivalent-equation counting. The daily riddle is generated in the database on demand using the date in `Asia/Jerusalem`; it needs no scheduled job.
2. Enable Google in Supabase Authentication and configure the Google OAuth client in Google Cloud. Use the callback URL displayed by Supabase in the Google client. Add the deployed site origin and any local development origin to Supabase Auth URL configuration and its redirect allowlist. Google may require app verification or test users, depending on the client settings.
3. Set `supabaseUrl` and `supabaseAnonKey` in `dist/config.js` to the project's URL and publishable/anon key. These values are public browser configuration. Never use a service-role or secret key there.
4. Deploy `dist/` to a static host. The production site is hosted on Cloudflare Workers. Configure Supabase Auth's Site URL and redirect allowlist for the production Worker URL. The site must be accessible to intended players separately from Google sign-in.

For an existing installation, run `supabase/fractional_division.sql` in the SQL editor to update division validation. Previously saved solutions were validated using integer division and may no longer be valid under the new rules.

A signed-in player's solutions are validated and deduplicated server-side. Only valid expressions using all five daily digits exactly once can enter the leaderboard. Guest solutions remain on the device and are not automatically imported into an account. The current day changes at midnight in Jerusalem.
