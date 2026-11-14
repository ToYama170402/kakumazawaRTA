/**
 * POST /functions/v1/submit-run （Issue #2）
 *
 * 端末から走行データを受け取り、検証して runs へ保存し、
 * 確定した status / rank_grade / total_seconds を返す。
 *
 * - location_history は検証にだけ使い、保存・ログ出力はしない。
 * - runs.id の主キー制約で run_id の重複を排除する（23505 → 409）。
 * - 保存には service role を使う（RLS の書き込みポリシーは作っていない）。
 *
 * 参照: docs/detail_design.md 3章・4.2
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  evaluateRun,
  parseSubmitRunRequest,
  termIdentifier,
  ValidationError,
} from "./validation.ts";

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return jsonResponse({ success: false, error: "method_not_allowed" }, 405);
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ success: false, error: "invalid_json" }, 400);
  }

  let request;
  try {
    request = parseSubmitRunRequest(body);
  } catch (e) {
    if (e instanceof ValidationError) {
      return jsonResponse(
        { success: false, error: "validation_failed", details: e.issues },
        400,
      );
    }
    throw e;
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  const { data: route, error: routeError } = await supabase
    .from("routes")
    .select("*")
    .eq("id", request.route_id)
    .single();

  if (routeError || !route) {
    return jsonResponse({ success: false, error: "route_not_found" }, 404);
  }

  const evaluation = evaluateRun(request, {
    max_velocity_threshold: Number(route.max_velocity_threshold),
    avg_velocity_threshold: Number(route.avg_velocity_threshold),
    // routes.rank_thresholds は任意列。無い / NULL の場合は階級なし。
    rank_thresholds: route.rank_thresholds ?? null,
  });

  const now = new Date();
  const { error: insertError } = await supabase.from("runs").insert({
    id: request.run_id,
    device_identifier: request.device_identifier,
    nickname: request.nickname,
    organization_code: request.organization_code,
    route_id: request.route_id,
    total_seconds: evaluation.total_seconds,
    status: evaluation.status,
    rank_grade: evaluation.rank_grade,
    term_identifier: termIdentifier(now),
    created_at: now.toISOString(),
  });

  if (insertError) {
    // 主キー重複 = 同じ run_id の再送。重複保存せず 409 で排除する。
    if (insertError.code === "23505") {
      return jsonResponse({ success: false, error: "duplicate_run_id" }, 409);
    }
    console.error(
      "failed to insert run:",
      insertError.code,
      insertError.message,
    );
    return jsonResponse({ success: false, error: "internal_error" }, 500);
  }

  return jsonResponse(
    {
      success: true,
      status: evaluation.status,
      rank_grade: evaluation.rank_grade,
      total_seconds: evaluation.total_seconds,
    },
    200,
  );
});
