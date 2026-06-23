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
