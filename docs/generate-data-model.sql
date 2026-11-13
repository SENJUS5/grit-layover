-- =============================================================================
-- Renders docs/data-model.md from the live catalog, so the docs always match
-- the SQL. The COMMENT ON statements in the migrations are the single source.
--
--   psql "$DATABASE_URL" -X -A -t -f docs/generate-data-model.sql > docs/data-model.md
--
-- (In the Supabase SQL Editor: run it and copy the single cell it returns.)
-- =============================================================================

with
tbl as (
  select c.oid, c.relname, c.relkind, obj_description(c.oid, 'pg_class') as descr
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r', 'v')
),
cols as (
  select a.attrelid,
         string_agg(
           format('| `%s` | %s | %s | %s |',
                  a.attname,
                  format_type(a.atttypid, a.atttypmod),
                  case when a.attnotnull then 'yes' else '' end,
                  coalesce(replace(col_description(a.attrelid, a.attnum), '|', '\|'), '')),
           E'\n' order by a.attnum) as body
  from pg_attribute a
  where a.attnum > 0 and not a.attisdropped
  group by a.attrelid
),
rules as (
  -- Constraints and partial/unique indexes: the rules the database enforces.
  select relid, string_agg(line, E'\n' order by kind, line) as body
  from (
    select con.conrelid as relid, 1 as kind,
           format('- `%s`: `%s`', con.conname, pg_get_constraintdef(con.oid)) as line
    from pg_constraint con
    where con.contype in ('c', 'f', 'u', 'x')
    union all
    select i.indrelid, 2,
           format('- `%s`: `%s`', ic.relname,
                  regexp_replace(pg_get_indexdef(i.indexrelid), '^.* USING ', 'USING '))
    from pg_index i
    join pg_class ic on ic.oid = i.indexrelid
    where i.indisunique and not i.indisprimary
      and not exists (select 1 from pg_constraint c where c.conindid = i.indexrelid)
  ) x
  group by relid
),
trg as (
  select t.tgrelid, string_agg(format('`%s`', t.tgname), ', ' order by t.tgname) as body
  from pg_trigger t
  where not t.tgisinternal
  group by t.tgrelid
),
funcs as (
  select string_agg(
           format(E'### `%s(%s)`\n\n%s', p.proname, pg_get_function_identity_arguments(p.oid),
                  coalesce(obj_description(p.oid, 'pg_proc'), '')),
           E'\n\n' order by p.proname) as body
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname !~ '^_' and p.prokind = 'f'
    and obj_description(p.oid, 'pg_proc') is not null
    -- extension functions do not live in public on Supabase, but skip any that do
    and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
)
select concat_ws(E'\n',
  '# GRIT Layover data model',
  '',
  '> Generated from the database catalog by `docs/generate-data-model.sql`. Do not edit by hand:',
  '> change the `COMMENT ON` statements in `supabase/migrations/` and regenerate.',
  '',
  '## Principles',
  '',
  '1. Miles are a passbook: `miles_ledger` rows are only ever inserted. Miles = `SUM(amount)`.',
  '2. Nothing is deleted: badges are revoked, bookings cancelled, contest attempts kept.',
  '3. Every change is recorded in `audit_log` by triggers.',
  '4. The database enforces the rules (constraints, triggers, functions), not just the app.',
  '5. Journey state is derived by the `student_journey` view, never stored.',
  '6. Date logic uses Asia/Kolkata; timestamps are `timestamptz`.',
  '',
  '## Tables',
  '',
  (select string_agg(
            concat_ws(E'\n',
              format('### `%s`', t.relname),
              '',
              coalesce(t.descr, '_No description._'),
              '',
              '| Column | Type | Not null | Notes |',
              '|---|---|---|---|',
              c.body,
              case when r.body is not null then E'\n**Rules enforced**\n\n' || r.body end,
              case when g.body is not null then E'\n**Triggers:** ' || g.body end),
            E'\n\n' order by t.oid)
   from tbl t
   left join cols c  on c.attrelid = t.oid
   left join rules r on r.relid = t.oid
   left join trg g   on g.tgrelid = t.oid
   where t.relkind = 'r'),
  '',
  '## Views',
  '',
  (select string_agg(
            concat_ws(E'\n',
              format('### `%s`', t.relname),
              '',
              coalesce(t.descr, '_No description._'),
              '',
              '| Column | Type | Not null | Notes |',
              '|---|---|---|---|',
              c.body),
            E'\n\n' order by t.oid)
   from tbl t
   left join cols c on c.attrelid = t.oid
   where t.relkind = 'v'),
  '',
  '## Functions',
  '',
  'Public functions are the only write path for the app. Internal helpers (prefixed `_`) are not listed and not granted.',
  '',
  (select body from funcs),
  ''
);
