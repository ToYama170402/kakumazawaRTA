# 『角間坂RTA』詳細設計仕様書

## 1. システム構成概観

本システムは、端末側の走行制御の即応性と、管理用計算機側の維持管理負担の最小化を両立するため、**Flutter**および**Supabase**を基盤として構築する。

* **移動体応用プログラム（アプリ）**：Flutter
* **後方機能提供基盤（BaaS）**：Supabase（PostgreSQL、Edge Functions）
* **利用者認証**：事前登録なしの匿名利用方式（端末生成の一意な識別子による紐付け）

---

## 2. データベース設計

### 2.1. 管理用計算機側（Supabase / PostgreSQL）

#### routes（経路定義表）

各種目および走行経路の判定基準、不正足切りの閾値を保持する。

| 列名 | 型 | 説明 |
| --- | --- | --- |
| `id` | uuid (主鍵) | 経路の一意な識別子 |
| `category` | text | 種目区分（'徒歩'、'自転車'等） |
| `route_name` | text | 経路名 |
| `goal_bounds` | jsonb | 終点領域の境界長方形座標 |
| `start_bounds` | jsonb | 計測開始用：開始地点の境界長方形座標（開始はボタン押下後、領域内でのみ許可） |
| `max_velocity_threshold` | numeric | 不正検知用：許容最高速度（km/h） |
| `avg_velocity_threshold` | numeric | 不正検知用：許容平均速度（km/h） |

#### runs（走行記録表）

検証済みの走行結果を蓄積する。

| 列名 | 型 | 説明 |
| --- | --- | --- |
| `id` | uuid (主鍵) | 走行一意の識別子（端末生成の `run_id`） |
| `device_identifier` | text | 端末一意の識別子（UUID） |
| `nickname` | text | 利用者の名乗り（ニックネーム） |
| `organization_code` | text | 所属の内部コード（organizations参照） |
| `route_id` | uuid (外部鍵) | `routes.id` への参照 |
| `total_seconds` | numeric | 検証後の確定走行時間（秒） |
| `status` | text | 記録状態（'official' [公認]、'reference' [参考]） |
| `rank_grade` | text | 確定評価階級（'S'、'A'、'B'等） |
| `term_identifier` | text | 期間識別子（'2026-06' 等の年月形式、サーバーUTC基準で生成） |
| `created_at` | timestamp | 記録日時 |

#### 索引定義（Index）

順位表の動的集計を高速化するため、以下の複合索引を設定する。

```sql
-- 主な集計索引（表示性能向上のため最小化）
CREATE INDEX idx_runs_ranking ON runs (term_identifier, total_seconds);
-- 組織別フィルタ用索引
CREATE INDEX idx_runs_org ON runs (organization_code);

```

### 2.2. 端末側局所記憶（Flutter / SQLite等）

#### pending_runs（未送信記録表）

通信圏外等で送信が保留されている走行データを一時蓄積する。

| 列名 | 型 | 説明 |
| --- | --- | --- |
| `run_id` | text (主鍵) | 走行一意の識別子（UUID） |
| `request_payload` | text | 境界関数への送信要求JSON文字列全体 |
| `retry_count` | integer | 送信試行回数（初期値：0） |
| `next_attempt_at` | text | 次回送信試行日時 |

---

### 2.3. ルート同期と更新

* 端末は**アプリ起動時**および**ユーザーが押した更新ボタン**で `routes` を同期する。計測中は同期を行わない。同期成功時のみローカルキャッシュを差し替える。
* ルートの更新頻度は非常に低い想定で、自動更新は行わない。更新しないユーザーを考慮し、任意更新（ユーザー操作）で反映できるUIを提供する。

## 3. 通信界面（API）仕様

走行終了時、端末からSupabaseの境界関数（Edge Functions）へ一括送信を行う。

* **通信方式**：HTTPS POST
* **端点（エンドポイント）**：`/functions/v1/submit-run`

### 3.1. 要求（Request）構造

```json
{
  "device_identifier": "端末固有のUUID",
  "run_id": "走行固有のUUID",
  "nickname": "金大太郎",
  "organization_code": "所属の内部ID",
  "organization_display_name": "理工学域・電子情報学類",
  "route_id": "経路UUID",
  "location_history": [
    {"lat": 36.5450, "lng": 136.7050, "t": 0},
    {"lat": 36.5455, "lng": 136.7055, "t": 1}
  ]
}
```

* `location_history` は検証のためにサーバーへ送信されるが、**サーバー側では検証完了後に破棄する**（永続保存しない）。
* 端末は送信時に同期的にサーバーの検証結果を待ち、**確定した `status` / `rank_grade` / `total_seconds` を受け取って表示する**。通信が不安定で応答が得られない場合は、ローカルの `pending_runs` に保存して再送する。

### 3.2. 応答（Response）構造

```json
{
  "success": true,
  "status": "official",
  "rank_grade": "S",
  "total_seconds": 345.2
}
```

---

## 4. 主要処理制御方式

### 4.1. 位置情報取得と自動停止判定（端末側）

1. **取得周期**：1秒間隔の定時取得を実行。電力消費と判定精度の均衡を担保する。
2. **計測開始条件**：ユーザーが「走行開始」ボタンを押した後、端末が `routes.start_bounds`（長方形領域）を通過した場合にのみ計測を開始する。計測中は1秒周期で位置を記録する。
3. **局所保護と鍵管理**：各走行について、計測開始時に**その走行専用の暗号鍵を生成**し、OSのKeystore/Keychainに保管する。取得した位置履歴はこの鍵で暗号化してローカル（SQLiteの `pending_runs`）へ格納する。送信前に端末側で復号してHTTPSで送信する。
4. **ゴール判定**：ゴールは `routes.goal_bounds`（長方形）による判定とし、端末がゴール領域に入った瞬間に計測を停止する。

### 4.2. 不正検証および階級評価（管理用計算機側）

1. **二段階評価**：走行終了直後、端末側は暫定階級を表示しつつ、サーバー検証の完了を同期的に待機して確定階級を表示する。
2. **移動窓検証（サーバー側）**：受信した `location_history` に対し、**5秒窓を1秒刻みでスライド**させながら区間速度を算出する。速度は各窓の**始点と終点の直線距離 ÷ 5秒**で計算する。
3. **閾値判定**：`max_velocity_threshold`（瞬間的な上限）および `avg_velocity_threshold`（長時間平均）のいずれかを超過した場合に **`status` を 'reference'** に設定して順位集計から除外する（OR条件）。問題がなければ `status` を 'official' とし、確定した `rank_grade` と `total_seconds` を端末へ返却する。

### 4.3. 再送制御（端末側）

1. **ローカルキュー**：`pending_runs` は **SQLite** で管理する。`request_payload` は送信要求のJSON文字列（暗号化済）を保持する。
2. **再送トリガー**：再送は主に以下のタイミングで試行する。
   * アプリ起動時
   * 計測終了直後の送信試行
   * ユーザー操作（再送ボタンなど）
   * OSが許す範囲での定期バックグラウンド処理

* 起動時はアプリ root で 1 回だけ `pending_runs` の期限到来分を処理する

3. **指数関数的退避と上限**：再送間隔は `retry_count` によって5分、15分、1時間とし、**最大試行回数は3回**でいったん打ち切る（その後はアプリ起動時に再挑戦）。
2. **重複排除**：サーバー側は `run_id` の主キー制約により重複を排除する。

### 4.4. 順位表の自動運用周期

1. **期間識別子**：期間識別子（例：`2026-06`）はサーバー側の現在時刻（**UTC基準**）から生成して `runs.term_identifier` に保存する。
2. **動的集計**：表示時は `term_identifier` で絞り込み、必要に応じて `organization_code` でフィルターする。履歴データは削除せず「歴代殿堂」として保持する。
