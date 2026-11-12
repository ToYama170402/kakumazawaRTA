# kakumazawaRTA

## 概要

`kakumazawaRTA` は金沢大学の登学をタイムアタックするプラットフォーム/モバイルアプリです。

## 前提条件

- Git
- Nix flake
- direnv

## 開発環境のセットアップ

```bash
git clone <repo-url>
cd kakumazawaRTA
direnv allow
```

### Nix devShell (推奨)

このリポジトリには `flake.nix` が含まれており、開発環境を `nix` のdevShellで再現できます。Nixを使うと `flutter`、`jdk`、Android SDK等の依存がシェル内で利用可能になります。

### direnv / .envrc

このリポジトリには `.envrc` が含まれており、`direnv` を使ってシェル環境を自動設定できます。`direnv` を有効にしておくと、ディレクトリ移動時に `use flake` などの環境設定が自動で読み込まれます。

`direnv` を併用することで `nix develop` によるdevShellのセットアップがスムーズになります。

## プロジェクト構成（主要ディレクトリ）

- `lib/` — アプリのDartソースコード（エントリ: `lib/main.dart`）
- `android/` — Androidネイティブ周りの設定とビルドファイル
- `ios/` — iOSネイティブ周りの設定とビルドファイル
- `test/` — ユニット・ウィジェットテスト
- `pubspec.yaml` — 依存関係とメタデータ

主要ファイル: `lib/main.dart` を参照してアプリの入口を確認してください。

- `docs/` — 設計書（詳細・外部・内部）と [実装順序](docs/implementation_order.md)
- `supabase/migrations/` — PostgreSQL マイグレーション
- `supabase/functions/submit-run/` — 走行送信を受ける Edge Function

## Supabase マイグレーション

`routes` / `runs` テーブルと順位集計用索引（`idx_runs_ranking` / `idx_runs_org`）は
`supabase/migrations/20260626000000_create_routes_and_runs.sql` で定義しています。

適用手順（どちらか）:

```bash
# Supabase CLI を使う場合
supabase link --project-ref <project-ref>
supabase db push

# または Supabase ダッシュボードの SQL Editor に
# マイグレーションSQLの内容を貼って実行する
```

## API: submit-run

走行終了時、端末は Supabase Edge Function へ走行データを一括送信します。

- 端点: `POST /functions/v1/submit-run`
- 要求: `device_identifier`, `run_id` (UUID), `nickname`, `organization_code`,
  `organization_display_name`（任意）, `route_id` (UUID),
  `location_history`（`{lat, lng, t}` の配列。`t` は開始からの経過秒で単調増加）
- 検証: 位置履歴を5秒移動窓で評価し、`routes` の
  `max_velocity_threshold` / `avg_velocity_threshold` のどちらかを超過したら
  `status` は `reference`、問題なければ `official` になります。
  位置履歴は検証後に破棄し、保存しません。
- 応答: `{ "success": true, "status": "official", "rank_grade": "S", "total_seconds": 345.2 }`
  （`rank_grade` は `routes.rank_thresholds` 未設定なら `null`）
- 重複した `run_id` は主キー制約で排除され、`409 duplicate_run_id` を返します。

デプロイと検証ロジックのテスト:

```bash
supabase functions deploy submit-run
deno test supabase/functions/submit-run/validation_test.ts
```
