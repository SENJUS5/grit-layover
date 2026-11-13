# GRIT Layover

Interview scheduling for NIAT's GRIT program. Students book badge interviews,
interviewers record results, badges award Miles, and admins handle malpractice
cases. This repo holds the **database** (Supabase / Postgres 15+) and the
**web app** (Next.js) on top of it.

The database enforces the rules itself: an append-only Miles ledger, no
deletes, audit triggers on every change, and journey state that a view
derives instead of storing. See [docs/data-model.md](docs/data-model.md).

## Layout

| File | What it does |
|---|---|
| `supabase/migrations/001_schema.sql` | Extensions, tables, constraints, indexes |
| `supabase/migrations/002_functions.sql` | Guard + audit triggers, business functions (the only write path) |
| `supabase/migrations/003_views.sql` | `student_journey`, `leaderboard`, admin and interviewer views |
| `supabase/migrations/004_security.sql` | Grants and Row Level Security |
| `supabase/migrations/005_app_reads.sql` | Read-only views and functions for the app's screens (passbook, trip checklist, "what changed", ...) |
| `supabase/seed.sql` | GRIT reference data + one demo student per journey state |
| `supabase/tests/checks.sql` | Rule checks; prints a PASS/FAIL table and rolls everything back |
| `supabase/reset.sql` | Drops all GRIT objects (destroys data) |
| `docs/generate-data-model.sql` | Regenerates `docs/data-model.md` from the SQL comments |
| `app/` | The app's routes (one thin page per screen) |
| `components/screens/` | The screens: student, interviewer and admin |
| `lib/api.ts` | Every database call the app makes |
| `lib/messages.ts` | **All message text students read.** Edit the wording here |
| `.env.example` | The two settings the app needs |

## Run it (Supabase SQL Editor)

Paste and run each file, **in this order**:

1. `supabase/migrations/001_schema.sql`
2. `supabase/migrations/002_functions.sql`
3. `supabase/migrations/003_views.sql`
4. `supabase/migrations/004_security.sql`
5. `supabase/migrations/005_app_reads.sql`
6. `supabase/seed.sql`
7. `supabase/tests/checks.sql`: every row should say `PASS`

Or with psql:

```sh
for f in supabase/migrations/00{1,2,3,4,5}_*.sql supabase/seed.sql supabase/tests/checks.sql; do
  psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -f "$f" || break
done
```

The seed uses times relative to `now()`, so the demo works whenever you seed
it. As days pass, the demo ages: Sneha's "tomorrow" booking turns into
"Waiting for result", for example. Reset and re-seed to refresh it.
If the badge deadline (31 Dec 2026) has already passed when you seed, the
seed moves it 30 days ahead. Otherwise every student without a badge would
show "Not eligible".

## Reset

`seed.sql` only runs on an empty database. To start over:

1. Run `supabase/reset.sql`. **This deletes all GRIT data.** It drops the
   tables, views, functions and domains. Dropping is the only way to clear
   the ledger, because its guard triggers block DELETE and TRUNCATE by design.
2. Run steps 1 to 7 above again.

## Regenerate the data-model doc

```sh
psql "$DATABASE_URL" -X -A -t -f docs/generate-data-model.sql > docs/data-model.md
```

## The app

Next.js 16 (App Router, TypeScript), Tailwind CSS 4 and `@supabase/supabase-js`.
The app only reads views and calls the database functions: it never writes to
a table, and it shows database error messages exactly as written.

Screens, by who you choose in **View as** (top bar, remembered in the browser):

- **Student:** Dashboard (journey, Miles and rank, "What changed", trip
  checklist), Interviews (readiness, book, reschedule, cancel, Robotics
  project), Miles passbook, Leaderboard, Messages.
- **Interviewer:** Schedule (record results, same-day corrections),
  Availability (add and withdraw slots), Projects (Robotics project review).
- **Admin:** Bookings, At risk, Cases (malpractice), Audit log.

### Run it locally

Needs Node.js 20.9 or newer, and the database set up as above (001-005 + seed).

```sh
npm install
cp .env.example .env.local   # then fill in the two values
npm run dev                  # http://localhost:3000
```

Before you commit: `npm run lint`, `npx tsc --noEmit` and `npm run build`.

### Environment variables

| Name | Value |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Your project URL, e.g. `https://abcd.supabase.co` |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | The anon key (or the new publishable key, `sb_publishable_...`) |

Find both in the Supabase dashboard under **Connect** (or Project Settings >
API). Both are public by design: Next.js copies `NEXT_PUBLIC_` values into the
browser code at build time, so a change needs a rebuild (or a redeploy on
Vercel). Never use the `service_role` / secret key; the app does not need it.
`.env.local` is ignored by git.

### Demo path

1. Choose **Karthik Menon · interviewer** in View as.
2. On **Schedule**, under "Needs a result", pick **Pass** for **Rahul Verma**,
   add feedback, and press **Save result**.
3. Switch to **Rahul Verma**. The Dashboard's "What changed" card shows Miles
   100 → 250 (+150), Pre-Qualiflyer → Qualiflyer with the new rank, and
   "One badge by 31 Dec 2026" going from not ticked to ticked. The Novice card
   says Passed and the trip checklist ticks the badge condition. **Miles** has a
   +150 row, **Leaderboard** shows Rahul in Qualiflyers (highlighted, with his
   old place), and **Messages** has "Here's your result".
4. The removal version: as Karthik, under "Results you recorded today", press
   **Correct this result** on Rahul's pass, choose **Fail**, give a reason and
   save. As Rahul you now see -150 Miles, Qualiflyer → Pre-Qualiflyer, the
   badge condition unticked, and "Your badge has been removed".
5. The malpractice version, with the cascade: **Ishita Gupta** is seeded in
   that state. Or as **Admin**, open **Cases** and confirm Aditya Kulkarni's
   open case.

More to try: **Priya Sharma** can book, reschedule and cancel. **Arjun Reddy**
shows "3 of 4 skills cleared — clear UI Engineering L2 to book". **Rohan Das**
(Robotics) waits for project approval: approve it as an interviewer under
**Projects**. **Aditya Kulkarni** sees the private "Under review" notice.
Ranks in the demo depend on what you did before; reset and re-seed the
database for a clean start.

### Deploy on Vercel

1. Run `supabase/migrations/005_app_reads.sql` on your Supabase project if you
   have not yet, then `supabase/tests/checks.sql`: every row should say `PASS`.
2. On [vercel.com](https://vercel.com): **Add New… > Project**, import this
   GitHub repository. Vercel detects Next.js; keep the default build settings
   and root directory.
3. Under **Environment Variables**, add `NEXT_PUBLIC_SUPABASE_URL` and
   `NEXT_PUBLIC_SUPABASE_ANON_KEY` (for Production, and Preview if you want
   preview deployments to work).
4. Press **Deploy**, open the URL, and choose someone in View as.

If you change a variable later, redeploy so the new value is built in.

## Security model (prototype)

There is no login yet. The app's role switcher passes `p_actor_role` /
`p_actor_id` to every function. The functions enforce what each role may do,
but they trust the caller about who they are. `anon` and `authenticated` can:

- read the reference tables and the views
- call the public functions, including the read functions in `005_app_reads.sql`
  (a student may read only their own data, an interviewer theirs, an admin anyone's)

They cannot write to any table, and they cannot read `malpractice_cases` or
`audit_log` (admins use `admin_list_cases()` / `admin_audit_log()`).

**This means anyone who can open the app can act as any student, interviewer
or the admin.** That is fine for a demo with the seeded data, but do not put
real student data behind it.

In production, use Supabase Auth: derive the actor from `auth.uid()` and add
per-role RLS policies. See the header of `004_security.sql`.
