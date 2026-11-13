# GRIT Layover

Interview scheduling for NIAT's GRIT program. Students book badge interviews,
interviewers record results, badges award Miles, and admins handle malpractice
cases. This repo holds the **database layer** (Supabase / Postgres 15+). The
frontend comes later.

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
| `supabase/seed.sql` | GRIT reference data + one demo student per journey state |
| `supabase/tests/checks.sql` | Rule checks; prints a PASS/FAIL table and rolls everything back |
| `supabase/reset.sql` | Drops all GRIT objects (destroys data) |
| `docs/generate-data-model.sql` | Regenerates `docs/data-model.md` from the SQL comments |

## Run it (Supabase SQL Editor)

Paste and run each file, **in this order**:

1. `supabase/migrations/001_schema.sql`
2. `supabase/migrations/002_functions.sql`
3. `supabase/migrations/003_views.sql`
4. `supabase/migrations/004_security.sql`
5. `supabase/seed.sql`
6. `supabase/tests/checks.sql`: every row should say `PASS`

Or with psql:

```sh
for f in supabase/migrations/00{1,2,3,4}_*.sql supabase/seed.sql supabase/tests/checks.sql; do
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
2. Run steps 1 to 6 above again.

## Regenerate the data-model doc

```sh
psql "$DATABASE_URL" -X -A -t -f docs/generate-data-model.sql > docs/data-model.md
```

## Security model (prototype)

There is no login yet. The app's role switcher passes `p_actor_role` /
`p_actor_id` to every function. The functions enforce what each role may do,
but they trust the caller about who they are. `anon` and `authenticated` can:

- read the reference tables and the views
- call the public functions

They cannot write to any table, and they cannot read `malpractice_cases` or
`audit_log` (admins use `admin_list_cases()` / `admin_audit_log()`).

In production, use Supabase Auth: derive the actor from `auth.uid()` and add
per-role RLS policies. See the header of `004_security.sql`.
