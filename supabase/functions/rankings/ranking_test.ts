import { parseRankingQuery, RankingQueryError } from "./ranking.ts";

function assertEquals<T>(actual: T, expected: T, label = ""): void {
  if (!Object.is(actual, expected)) {
    throw new Error(`${label} expected ${expected}, got ${actual}`);
  }
}

function assertThrowsRanking(fn: () => unknown, label: string): void {
  try {
    fn();
  } catch (e) {
    if (e instanceof RankingQueryError) return;
    throw new Error(`${label}: expected RankingQueryError, got ${e}`);
  }
  throw new Error(`${label}: expected RankingQueryError, nothing thrown`);
}

const now = new Date("2026-07-15T12:00:00Z");
const params = (s: string) => new URLSearchParams(s);

Deno.test("period未指定は今月 (UTC) になる", () => {
  const q = parseRankingQuery(params(""), now);
  assertEquals(q.termIdentifier, "2026-07");
  assertEquals(q.organizationCode, null);
  assertEquals(q.routeId, null);
  assertEquals(q.limit, 100);
});

Deno.test("period=all は全期間 (null) になる", () => {
  const q = parseRankingQuery(params("period=all"), now);
  assertEquals(q.termIdentifier, null);
});

Deno.test("period=YYYY-MM はその月を指定できる", () => {
  const q = parseRankingQuery(params("period=2026-06"), now);
  assertEquals(q.termIdentifier, "2026-06");
});

Deno.test("月境界: UTC月初は新しい term になる", () => {
  const q = parseRankingQuery(
    params(""),
    new Date("2026-08-01T00:00:00Z"),
  );
  assertEquals(q.termIdentifier, "2026-08");
});

Deno.test("組織フィルタと limit を解決する", () => {
  const q = parseRankingQuery(
    params("organization_code=science&limit=10"),
    now,
  );
  assertEquals(q.organizationCode, "science");
  assertEquals(q.limit, 10);
});

Deno.test("limit は 1000 に丸められる", () => {
  const q = parseRankingQuery(params("limit=99999"), now);
  assertEquals(q.limit, 1000);
});

Deno.test("不正な period / route_id / limit を弾く", () => {
  assertThrowsRanking(
    () => parseRankingQuery(params("period=2026/07"), now),
    "bad period",
  );
  assertThrowsRanking(
    () => parseRankingQuery(params("route_id=abc"), now),
    "bad route_id",
  );
  assertThrowsRanking(
    () => parseRankingQuery(params("limit=0"), now),
    "limit 0",
  );
  assertThrowsRanking(
    () => parseRankingQuery(params("limit=1.5"), now),
    "limit non-integer",
  );
  assertThrowsRanking(
    () => parseRankingQuery(params("organization_code="), now),
    "empty organization_code",
  );
});
