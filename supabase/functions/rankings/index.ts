/**
 * GET /functions/v1/rankings （Issue #9）
 *
 * 順位表の集計API。DB側の get_rankings 関数（マイグレーション
 * 20260627000000）を rpc で呼び、結果をそのまま返す。
 *
 * クエリパラメータ:
 * - period: "current"（既定） | "all" | "YYYY-MM"
 * - organization_code: 組織フィルタ（任意）
 * - route_id: ルートフィルタ（任意、UUID）
 * - limit: 件数（任意、既定100、最大1000）
 *
 * 集計対象は status = 'official' のみ。過去月データは削除されず、
 * period=all で「歴代殿堂」として取得できる。
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { parseRankingQuery, RankingQueryError } from "./ranking.ts";

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method !== "GET") {
    return jsonResponse({ success: false, error: "method_not_allowed" }, 405);
  }

  const url = new URL(req.url);
  let query;
  try {
    query = parseRankingQuery(url.searchParams, new Date());
  } catch (e) {
    if (e instanceof RankingQueryError) {
      return jsonResponse(
        { success: false, error: "validation_failed", details: [e.message] },
        400,
      );
    }
    throw e;
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
  );

  const { data, error } = await supabase.rpc("get_rankings", {
    p_term_identifier: query.termIdentifier,
    p_organization_code: query.organizationCode,
    p_route_id: query.routeId,
    p_limit: query.limit,
  });

  if (error) {
    console.error("get_rankings failed:", error.code, error.message);
    return jsonResponse({ success: false, error: "internal_error" }, 500);
  }

  return jsonResponse(
    {
      success: true,
      term_identifier: query.termIdentifier,
      rankings: data ?? [],
    },
    200,
  );
});
