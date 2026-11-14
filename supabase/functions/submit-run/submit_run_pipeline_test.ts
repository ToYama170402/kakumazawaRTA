/**
 * submit-run のパイプライン統合テスト（Issue #10）
 *
 * Edge Function のハンドラが辿る流れ
 * 「入力検証 → 5秒窓検証 → 階級評価 → term_identifier 付与 → runs へ保存する値」
 * を、DBへ接続せずに一連で検証する。異常/正常ケースで期待する
 * status が得られることを確認する。
 */
import {
  evaluateRun,
  type LocationPoint,
  parseSubmitRunRequest,
  termIdentifier,
} from "./validation.ts";

function assertEquals<T>(actual: T, expected: T, label = ""): void {
  if (!Object.is(actual, expected)) {
    throw new Error(`${label} expected ${expected}, got ${actual}`);
  }
}

function makeHistory(
  seconds: number,
  metersPerSecond: number,
): LocationPoint[] {
  const points: LocationPoint[] = [];
  for (let t = 0; t <= seconds; t++) {
    points.push({
      lat: 36.545 + (metersPerSecond * t) / 111_320,
      lng: 136.705,
      t,
    });
  }
  return points;
}

const baseBody = {
  device_identifier: "device-1",
  run_id: "123e4567-e89b-42d3-a456-426614174000",
  nickname: "金大太郎",
  organization_code: "science",
  organization_display_name: "融合学域",
  route_id: "123e4567-e89b-42d3-a456-426614174001",
};

const walkRoute = {
  max_velocity_threshold: 10,
  avg_velocity_threshold: 8,
  rank_thresholds: [
    { grade: "S", max_seconds: 300 },
    { grade: "A", max_seconds: 600 },
  ],
};

/** ハンドラ相当の流れ: 検証済みリクエストから runs へ保存する行を作る */
function buildRunRow(body: unknown, now: Date) {
  const request = parseSubmitRunRequest(body);
  const evaluation = evaluateRun(request, walkRoute);
  return {
    id: request.run_id,
    device_identifier: request.device_identifier,
    nickname: request.nickname,
    organization_code: request.organization_code,
    route_id: request.route_id,
    total_seconds: evaluation.total_seconds,
    status: evaluation.status,
    rank_grade: evaluation.rank_grade,
    term_identifier: termIdentifier(now),
  };
}

Deno.test("パイプライン: 正常な徒歩走行は official で階級と期間が付く", () => {
  const row = buildRunRow(
    { ...baseBody, location_history: makeHistory(240, 1.4) },
    new Date("2026-06-15T10:00:00Z"),
  );
  assertEquals(row.status, "official", "status");
  assertEquals(row.rank_grade, "S", "rank_grade");
  assertEquals(row.total_seconds, 240, "total_seconds");
  assertEquals(row.term_identifier, "2026-06", "term");
});

Deno.test("パイプライン: 車両並みの速さは reference になり順位集計から外れる前提になる", () => {
  const row = buildRunRow(
    { ...baseBody, location_history: makeHistory(60, 12) },
    new Date("2026-06-15T10:00:00Z"),
  );
  assertEquals(row.status, "reference", "status");
});

Deno.test("パイプライン: 月境界 (UTC) で term が切り替わる", () => {
  const body = { ...baseBody, location_history: makeHistory(10, 1.4) };
  const june = buildRunRow(body, new Date("2026-06-30T23:59:59Z"));
  const july = buildRunRow(body, new Date("2026-07-01T00:00:00Z"));
  assertEquals(june.term_identifier, "2026-06");
  assertEquals(july.term_identifier, "2026-07");
});
