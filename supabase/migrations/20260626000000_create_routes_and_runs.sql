-- Issue #1 / #12 / #13 / #14
-- 角間坂RTA: routes / runs テーブルの初期マイグレーション
--
-- 参照: docs/detail_design.md 2.1
-- 適用手順は README.md の「Supabase マイグレーション」を参照。

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- routes（経路定義表）
--
-- start_bounds / goal_bounds は境界長方形を以下の JSON 形式で保持する。
--   {"min_lat": number, "max_lat": number, "min_lng": number, "max_lng": number}
--
-- rank_thresholds は詳細設計で未定義だった階級評価用に任意で追加した列。
-- 形式: [{"grade": "S", "max_seconds": 300}, {"grade": "A", "max_seconds": 600}]
-- （max_seconds 昇順。total_seconds が最初に当てはまる階級を返す）
-- NULL の場合は階級を付けず、submit-run は rank_grade = null を返す。
-- ---------------------------------------------------------------------------
create table public.routes (
  id uuid primary key default gen_random_uuid(),
  category text not null,
  route_name text not null,
  goal_bounds jsonb not null,
  start_bounds jsonb not null,
  max_velocity_threshold numeric not null,
  avg_velocity_threshold numeric not null,
  rank_thresholds jsonb,
  constraint routes_goal_bounds_shape check (
    jsonb_typeof(goal_bounds) = 'object'
    and goal_bounds ?& array['min_lat', 'max_lat', 'min_lng', 'max_lng']
  ),
  constraint routes_start_bounds_shape check (
    jsonb_typeof(start_bounds) = 'object'
    and start_bounds ?& array['min_lat', 'max_lat', 'min_lng', 'max_lng']
  ),
  constraint routes_max_velocity_positive check (max_velocity_threshold > 0),
  constraint routes_avg_velocity_positive check (avg_velocity_threshold > 0)
);

comment on table public.routes is '経路定義。種目・境界長方形・不正検知の速度閾値を保持する。';
comment on column public.routes.goal_bounds is '終点領域の境界長方形 {min_lat, max_lat, min_lng, max_lng}';
comment on column public.routes.start_bounds is '開始地点の境界長方形 {min_lat, max_lat, min_lng, max_lng}。計測開始はボタン押下後にこの領域内でのみ許可する。';
comment on column public.routes.rank_thresholds is '任意。階級閾値 [{grade, max_seconds}]（昇順）。NULL なら階級なし。';

-- ---------------------------------------------------------------------------
-- runs（走行記録表）
-- location_history は検証後に破棄するため、この表には保存しない。
-- ---------------------------------------------------------------------------
create table public.runs (
  id uuid primary key,
  device_identifier text not null,
  nickname text not null,
  organization_code text not null,
  route_id uuid not null references public.routes (id),
  total_seconds numeric not null,
  status text not null,
  rank_grade text,
  term_identifier text not null,
  created_at timestamptz not null default now(),
  constraint runs_status_valid check (status in ('official', 'reference')),
  constraint runs_total_seconds_positive check (total_seconds > 0),
  constraint runs_term_identifier_format check (term_identifier ~ '^[0-9]{4}-[0-9]{2}$')
);

comment on table public.runs is '検証済みの走行結果。id は端末生成の run_id で、主キー制約により重複送信を排除する。';
comment on column public.runs.term_identifier is '期間識別子（例: 2026-06）。サーバー側 UTC 基準で生成する。';

-- 順位集計用索引（docs/detail_design.md 2.1）
create index idx_runs_ranking on public.runs (term_identifier, total_seconds);
create index idx_runs_org on public.runs (organization_code);

-- ---------------------------------------------------------------------------
-- RLS
-- - routes / runs の読み取りは順位表・ルート同期のため公開する。
-- - 書き込みポリシーは作らない。runs へのinsertは service role を使う
--   Edge Function (submit-run) のみが行い、RLS をバイパスする。
-- ---------------------------------------------------------------------------
alter table public.routes enable row level security;
alter table public.runs enable row level security;

create policy "routes are publicly readable"
  on public.routes for select
  using (true);

create policy "runs are publicly readable"
  on public.runs for select
  using (true);
