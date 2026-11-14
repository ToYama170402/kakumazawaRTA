-- Issue #9
-- 順位集計関数 get_rankings
--
-- - status = 'official' の記録だけを集計対象にする（reference は順位表から除外）
-- - p_term_identifier が NULL の場合は全期間（歴代殿堂）
-- - p_organization_code / p_route_id が NULL の場合はその条件で絞らない
-- - 順位は total_seconds 昇順、同タイムは同順位（rank()）
--
-- 参照: docs/detail_design.md 4.4

create or replace function public.get_rankings(
  p_term_identifier text default null,
  p_organization_code text default null,
  p_route_id uuid default null,
  p_limit integer default 100
)
returns table (
  rank bigint,
  run_id uuid,
  nickname text,
  organization_code text,
  route_id uuid,
  total_seconds numeric,
  rank_grade text,
  term_identifier text,
  created_at timestamptz
)
language sql
stable
as $$
  select
    rank() over (order by r.total_seconds asc) as rank,
    r.id as run_id,
    r.nickname,
    r.organization_code,
    r.route_id,
    r.total_seconds,
    r.rank_grade,
    r.term_identifier,
    r.created_at
  from public.runs r
  where r.status = 'official'
    and (p_term_identifier is null or r.term_identifier = p_term_identifier)
    and (p_organization_code is null or r.organization_code = p_organization_code)
    and (p_route_id is null or r.route_id = p_route_id)
  order by r.total_seconds asc
  limit greatest(1, least(coalesce(p_limit, 100), 1000));
$$;

comment on function public.get_rankings(text, text, uuid, integer)
  is '順位集計。official のみ、期間・組織・ルートで絞り込み可能。期間 NULL は歴代。';

-- Edge Function (rankings) は anon キーで rpc を呼ぶため実行権限を付与する。
-- runs テーブル自体にも select ポリシーがあるため、読み取り範囲は変わらない。
grant execute on function public.get_rankings(text, text, uuid, integer) to anon, authenticated;
