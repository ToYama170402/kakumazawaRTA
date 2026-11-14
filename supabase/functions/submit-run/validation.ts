/**
 * submit-run の入力検証と不正検証ロジック（純粋関数のみ）。
 *
 * Deno / Supabase への依存を持たないので、`validation_test.ts` で
 * 単体テストできる。参照: docs/detail_design.md 3章・4.2、Issue #2 / #15 / #16
 */

export interface LocationPoint {
  lat: number;
  lng: number;
  /** 走行開始からの経過秒 */
  t: number;
}

export interface SubmitRunRequest {
  device_identifier: string;
  run_id: string;
  nickname: string;
  organization_code: string;
  organization_display_name?: string;
  route_id: string;
  location_history: LocationPoint[];
}

export interface RouteThresholds {
  max_velocity_threshold: number;
  avg_velocity_threshold: number;
  /** 任意。未設定なら階級は付かない */
  rank_thresholds?: RankThreshold[] | null;
}

export interface RankThreshold {
  grade: string;
  max_seconds: number;
}

export type RunStatus = "official" | "reference";

export interface Evaluation {
  status: RunStatus;
  rank_grade: string | null;
  total_seconds: number;
  /** 5秒窓で算出した最大の区間速度 (km/h)。窓が作れない場合は 0 */
  max_window_velocity_kmh: number;
  /** 全区間の移動距離合計 ÷ 全所要時間の平均速度 (km/h) */
  avg_velocity_kmh: number;
}

export class ValidationError extends Error {
  readonly issues: string[];

  constructor(issues: string[]) {
    super(`Invalid submit-run request: ${issues.join("; ")}`);
    this.name = "ValidationError";
    this.issues = issues;
  }
}

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isFiniteNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

/**
 * 受信 JSON を検証し、SubmitRunRequest として返す。
 * 不正な場合は検出した問題をすべて集めて ValidationError を投げる（Issue #15）。
 */
export function parseSubmitRunRequest(body: unknown): SubmitRunRequest {
  const issues: string[] = [];

  if (!isRecord(body)) {
    throw new ValidationError(["body must be a JSON object"]);
  }

  const requireString = (key: string): string => {
    const value = body[key];
    if (typeof value !== "string" || value.trim() === "") {
      issues.push(`${key} is required and must be a non-empty string`);
      return "";
    }
    return value;
  };

  const deviceIdentifier = requireString("device_identifier");
  const runId = requireString("run_id");
  const nickname = requireString("nickname");
  const organizationCode = requireString("organization_code");
  const routeId = requireString("route_id");

  if (runId !== "" && !UUID_PATTERN.test(runId)) {
    issues.push("run_id must be a UUID");
  }
  if (routeId !== "" && !UUID_PATTERN.test(routeId)) {
    issues.push("route_id must be a UUID");
  }

  let organizationDisplayName: string | undefined;
  if (body.organization_display_name !== undefined) {
    if (typeof body.organization_display_name !== "string") {
      issues.push("organization_display_name must be a string");
    } else {
      organizationDisplayName = body.organization_display_name;
    }
  }

  const history: LocationPoint[] = [];
  const rawHistory = body.location_history;
  if (!Array.isArray(rawHistory) || rawHistory.length < 2) {
    issues.push("location_history must be an array with at least 2 points");
  } else {
    rawHistory.forEach((raw, index) => {
      if (!isRecord(raw)) {
        issues.push(`location_history[${index}] must be an object`);
        return;
      }
      const { lat, lng, t } = raw;
      if (!isFiniteNumber(lat) || lat < -90 || lat > 90) {
        issues.push(
          `location_history[${index}].lat must be a number in [-90, 90]`,
        );
        return;
      }
      if (!isFiniteNumber(lng) || lng < -180 || lng > 180) {
        issues.push(
          `location_history[${index}].lng must be a number in [-180, 180]`,
        );
        return;
      }
      if (!isFiniteNumber(t) || t < 0) {
        issues.push(`location_history[${index}].t must be a number >= 0`);
        return;
      }
      if (history.length > 0 && t <= history[history.length - 1].t) {
        issues.push(`location_history[${index}].t must be strictly increasing`);
        return;
      }
      history.push({ lat, lng, t });
    });
  }

  if (issues.length > 0) {
    throw new ValidationError(issues);
  }

  return {
    device_identifier: deviceIdentifier,
    run_id: runId,
    nickname,
    organization_code: organizationCode,
    organization_display_name: organizationDisplayName,
    route_id: routeId,
    location_history: history,
  };
}

/** 2点間の直線距離（メートル）。Haversine 式。 */
export function haversineMeters(a: LocationPoint, b: LocationPoint): number {
  const earthRadiusMeters = 6_371_000;
  const toRad = (deg: number) => (deg * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * earthRadiusMeters * Math.asin(Math.sqrt(h));
}

export const WINDOW_SECONDS = 5;

/**
 * 5秒移動窓の最大速度 (km/h)。
 * 1秒周期の取得を前提に、各始点からちょうど5秒後の点との
 * 直線距離 ÷ 5秒 で算出する（docs/detail_design.md 4.2）。
 * 5秒後の点が存在しない始点は窓を作らない。
 */
export function maxWindowVelocityKmh(history: LocationPoint[]): number {
  let max = 0;
  for (let i = 0; i < history.length; i++) {
    const start = history[i];
    const end = history.find(
      (p, j) => j > i && Math.abs(p.t - start.t - WINDOW_SECONDS) < 1e-9,
    );
    if (!end) continue;
    const kmh = (haversineMeters(start, end) / WINDOW_SECONDS) * 3.6;
    if (kmh > max) max = kmh;
  }
  return max;
}

/** 経路の移動距離合計 ÷ 全所要時間の平均速度 (km/h) */
export function averageVelocityKmh(history: LocationPoint[]): number {
  const totalSeconds = history[history.length - 1].t - history[0].t;
  if (totalSeconds <= 0) return 0;
  let distance = 0;
  for (let i = 1; i < history.length; i++) {
    distance += haversineMeters(history[i - 1], history[i]);
  }
  return (distance / totalSeconds) * 3.6;
}

/**
 * 階級評価。rank_thresholds（max_seconds 昇順）から最初に当てはまる階級を返す。
 * 閾値が未設定・該当なしの場合は null。
 * ※ 詳細設計に階級の数値基準が無いため、閾値は routes 側で保持する設計にした。
 */
export function gradeRun(
  totalSeconds: number,
  rankThresholds?: RankThreshold[] | null,
): string | null {
  if (!rankThresholds || rankThresholds.length === 0) return null;
  const sorted = [...rankThresholds].sort((a, b) =>
    a.max_seconds - b.max_seconds
  );
  for (const threshold of sorted) {
    if (totalSeconds <= threshold.max_seconds) return threshold.grade;
  }
  return null;
}

/** 期間識別子。サーバー側 UTC 基準の年月（例: "2026-06"） */
export function termIdentifier(now: Date): string {
  return now.toISOString().slice(0, 7);
}

/**
 * 走行を検証し、確定結果を返す。
 * max / avg のどちらか一方でも閾値を超過したら 'reference'（Issue #16）。
 */
export function evaluateRun(
  request: SubmitRunRequest,
  route: RouteThresholds,
): Evaluation {
  const history = request.location_history;
  const totalSeconds = history[history.length - 1].t - history[0].t;
  const maxWindow = maxWindowVelocityKmh(history);
  const avg = averageVelocityKmh(history);
  const exceeded = maxWindow > route.max_velocity_threshold ||
    avg > route.avg_velocity_threshold;

  return {
    status: exceeded ? "reference" : "official",
    rank_grade: gradeRun(totalSeconds, route.rank_thresholds),
    total_seconds: totalSeconds,
    max_window_velocity_kmh: maxWindow,
    avg_velocity_kmh: avg,
  };
}
