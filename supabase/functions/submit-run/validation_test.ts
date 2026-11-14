import {
  averageVelocityKmh,
  evaluateRun,
  gradeRun,
  haversineMeters,
  type LocationPoint,
  maxWindowVelocityKmh,
  parseSubmitRunRequest,
  type SubmitRunRequest,
  termIdentifier,
  ValidationError,
} from "./validation.ts";

// 外部依存を避けるための最小アサーション
function assertEquals<T>(actual: T, expected: T, label = ""): void {
  if (!Object.is(actual, expected)) {
    throw new Error(`${label} expected ${expected}, got ${actual}`);
  }
}

function assertAlmostEquals(
  actual: number,
  expected: number,
  tolerance: number,
  label = "",
): void {
  if (Math.abs(actual - expected) > tolerance) {
    throw new Error(`${label} expected ~${expected}, got ${actual}`);
  }
}

function assertThrowsValidation(fn: () => unknown, label: string): void {
  try {
    fn();
  } catch (e) {
    if (e instanceof ValidationError) return;
    throw new Error(`${label}: expected ValidationError, got ${e}`);
  }
  throw new Error(`${label}: expected ValidationError, but nothing was thrown`);
}

// 金沢大学・角間キャンパス付近を北上する履歴を生成する
function makeHistory({
  seconds,
  metersPerSecond,
  startLat = 36.545,
  startLng = 136.705,
}: {
  seconds: number;
  metersPerSecond: number;
  startLat?: number;
  startLng?: number;
}): LocationPoint[] {
  const points: LocationPoint[] = [];
  for (let t = 0; t <= seconds; t++) {
    points.push({
      lat: startLat + (metersPerSecond * t) / 111_320,
      lng: startLng,
      t,
    });
  }
  return points;
}

function makeRequest(history: LocationPoint[]): SubmitRunRequest {
  return {
    device_identifier: "device-1",
    run_id: "123e4567-e89b-42d3-a456-426614174000",
    nickname: "金大太郎",
    organization_code: "science",
    route_id: "123e4567-e89b-42d3-a456-426614174001",
    location_history: history,
  };
}

// 徒歩: 最大 10 km/h, 平均 8 km/h
const walkRoute = {
  max_velocity_threshold: 10,
  avg_velocity_threshold: 8,
};

Deno.test("haversine: 緯度0.01度の距離は約1112m", () => {
  const d = haversineMeters(
    { lat: 36.545, lng: 136.705, t: 0 },
    { lat: 36.555, lng: 136.705, t: 1 },
  );
  assertAlmostEquals(d, 1111.95, 1.0, "distance");
});

Deno.test("parse: 正常なリクエストを受け付ける", () => {
  const parsed = parseSubmitRunRequest({
    ...makeRequest(makeHistory({ seconds: 3, metersPerSecond: 1.4 })),
  });
  assertEquals(parsed.nickname, "金大太郎");
  assertEquals(parsed.location_history.length, 4);
});

Deno.test("parse: 必須項目不足・UUID形式不正・緯度範囲外・時刻逆行を弾く", () => {
  const base = makeRequest(makeHistory({ seconds: 3, metersPerSecond: 1.4 }));

  assertThrowsValidation(
    () => parseSubmitRunRequest({ ...base, nickname: "" }),
    "empty nickname",
  );
  assertThrowsValidation(
    () => parseSubmitRunRequest({ ...base, run_id: "not-a-uuid" }),
    "bad run_id",
  );
  assertThrowsValidation(
    () =>
      parseSubmitRunRequest({
        ...base,
        location_history: [
          { lat: 91, lng: 136.7, t: 0 },
          { lat: 36.5, lng: 136.7, t: 1 },
        ],
      }),
    "lat out of range",
  );
  assertThrowsValidation(
    () =>
      parseSubmitRunRequest({
        ...base,
        location_history: [
          { lat: 36.5, lng: 136.7, t: 1 },
          { lat: 36.5, lng: 136.7, t: 1 },
        ],
      }),
    "t not increasing",
  );
  assertThrowsValidation(
    () =>
      parseSubmitRunRequest({
        ...base,
        location_history: [{ lat: 36.5, lng: 136.7, t: 0 }],
      }),
    "history too short",
  );
});

Deno.test("検証: 徒歩ペース (1.4m/s) は official になる", () => {
  const history = makeHistory({ seconds: 60, metersPerSecond: 1.4 });
  const result = evaluateRun(makeRequest(history), walkRoute);
  assertEquals(result.status, "official", "status");
  assertEquals(result.total_seconds, 60, "total_seconds");
  assertAlmostEquals(result.avg_velocity_kmh, 5.04, 0.05, "avg kmh");
  assertAlmostEquals(result.max_window_velocity_kmh, 5.04, 0.05, "window kmh");
});

Deno.test("検証: 5秒窓の瞬間的な跳躍は平均が低くても reference になる", () => {
  // 全体を長くし、跳躍を加えても平均速度は閾値未満に収まるようにする
  const history = makeHistory({ seconds: 900, metersPerSecond: 1.4 });
  // 60秒時点から5秒で 500m 跳ぶ（= 360 km/h）
  for (let i = 61; i < history.length; i++) {
    history[i] = { ...history[i], lat: history[i].lat + 500 / 111_320 };
  }
  const result = evaluateRun(makeRequest(history), walkRoute);
  assertEquals(result.status, "reference", "status");
  if (!(result.max_window_velocity_kmh > walkRoute.max_velocity_threshold)) {
    throw new Error("window velocity should exceed max threshold");
  }
  if (!(result.avg_velocity_kmh < walkRoute.avg_velocity_threshold)) {
    throw new Error(
      "avg velocity should stay below avg threshold in this case",
    );
  }
});

Deno.test("検証: 定常的な高速移動は平均速度超過で reference になる", () => {
  // 10m/s = 36 km/h を継続
  const history = makeHistory({ seconds: 60, metersPerSecond: 10 });
  const result = evaluateRun(makeRequest(history), walkRoute);
  assertEquals(result.status, "reference", "status");
  assertAlmostEquals(result.avg_velocity_kmh, 36, 0.1, "avg kmh");
});

Deno.test("窓: 履歴が5秒未満なら窓速度は 0", () => {
  const history = makeHistory({ seconds: 3, metersPerSecond: 1.4 });
  assertEquals(maxWindowVelocityKmh(history), 0);
  assertAlmostEquals(averageVelocityKmh(history), 5.04, 0.05, "avg");
});

Deno.test("階級: 閾値表から最初に当てはまる階級を返し、未設定なら null", () => {
  const thresholds = [
    { grade: "S", max_seconds: 300 },
    { grade: "A", max_seconds: 600 },
  ];
  assertEquals(gradeRun(200, thresholds), "S");
  assertEquals(gradeRun(400, thresholds), "A");
  assertEquals(gradeRun(900, thresholds), null);
  assertEquals(gradeRun(200, null), null);
  assertEquals(gradeRun(200, undefined), null);
});

Deno.test("termIdentifier: UTCの年月を返す", () => {
  assertEquals(
    termIdentifier(new Date("2026-06-30T23:59:59Z")),
    "2026-06",
  );
  assertEquals(
    termIdentifier(new Date("2026-07-01T00:00:00Z")),
    "2026-07",
  );
});
