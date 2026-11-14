/**
 * rankings API のパラメータ解決ロジック（純粋関数のみ）。
 *
 * 参照: docs/detail_design.md 4.4、Issue #9
 * - 期間は term_identifier（UTC基準の年月）で絞る。「今月」は表示上の
 *   初期化であり、過去データは削除せず「歴代」として残す。
 */

import { termIdentifier } from "../submit-run/validation.ts";

export interface RankingQuery {
  /** 絞り込む期間。null は全期間（歴代殿堂） */
  termIdentifier: string | null;
  organizationCode: string | null;
  routeId: string | null;
  limit: number;
}

export class RankingQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "RankingQueryError";
  }
}

const TERM_PATTERN = /^[0-9]{4}-[0-9]{2}$/;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export const DEFAULT_LIMIT = 100;
export const MAX_LIMIT = 1000;

/**
 * クエリパラメータを解決する。
 *
 * - period: "current"（既定、今月） | "all"（歴代） | "YYYY-MM"（月指定）
 * - organization_code: 任意。組織フィルタ
 * - route_id: 任意。UUID形式
 * - limit: 任意。1〜1000 に丸める（既定100）
 */
export function parseRankingQuery(
  params: URLSearchParams,
  now: Date,
): RankingQuery {
  const period = params.get("period") ?? "current";
  let term: string | null;
  if (period === "current") {
    term = termIdentifier(now);
  } else if (period === "all") {
    term = null;
  } else if (TERM_PATTERN.test(period)) {
    term = period;
  } else {
    throw new RankingQueryError(
      `period must be "current", "all", or YYYY-MM: ${period}`,
    );
  }

  const organizationCode = params.get("organization_code");
  if (organizationCode !== null && organizationCode.trim() === "") {
    throw new RankingQueryError("organization_code must not be empty");
  }

  const routeId = params.get("route_id");
  if (routeId !== null && !UUID_PATTERN.test(routeId)) {
    throw new RankingQueryError("route_id must be a UUID");
  }

  let limit = DEFAULT_LIMIT;
  const rawLimit = params.get("limit");
  if (rawLimit !== null) {
    const parsed = Number(rawLimit);
    if (!Number.isInteger(parsed) || parsed < 1) {
      throw new RankingQueryError("limit must be a positive integer");
    }
    limit = Math.min(parsed, MAX_LIMIT);
  }

  return {
    termIdentifier: term,
    organizationCode,
    routeId,
    limit,
  };
}
