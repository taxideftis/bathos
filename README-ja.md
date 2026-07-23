<p align="center">
  <!-- BATHOS_LANDING_URL — replace href="#" with the landing-page URL once the landing page is live (same marker in all language READMEs) -->
  <a href="#"><img src=".github/assets/bathos-lockup-transparent.png" alt="BATHOS" width="480"></a>
</p>

# BATHOS

[English](README.md) · [한국어](README-kr.md) · [Español](README-es.md) · [Deutsch](README-de.md) · **日本語**

> **βάθος**（ギリシャ語）— *「深さ、深淵」。* 表層的な AI 支援とは意図的に対をなす、圧倒的な深さを備えた AI Workflow Agent メソッド。

![version](https://img.shields.io/badge/version-0.2.0-0e9aa1)
![license](https://img.shields.io/badge/license-MIT-blue)
![engine](https://img.shields.io/badge/engine-Rust-d2691e)
![runtime](https://img.shields.io/badge/runtime-Claude%20Code%20v2.1.32%2B-7b61ff)
![status](https://img.shields.io/badge/status-v0.2.0%20early%20%C2%B7%20dogfood--verified-c8841a)

BATHOS は、**単一の Claude Code セッションを規律ある製品チームへと変える** — 17 の専門ロール、7 ウェーブのデリバリーパイプライン、スケール適応型ルーティング、そして厳格な品質ゲートを備え、その裏側では小さな **Rust エンジン** が重要な不変条件を「雰囲気」ではなく決定論的に成立させます。

> **한국어:** BATHOS는 Claude Code 위에서 **17역할 × 7웨이브 × Scale-Adaptive Lv0~4**로 제품 개발을 오케스트레이션하는 메서드 패키지입니다. 처음이라면 **[활용 사례(새 서비스 만들기)](docs/USECASE-kr.md)** → **[특징·구동원리](docs/FEATURES-kr.md)** → **[사용 가이드](docs/USAGE-kr.md)** 순서를 권장합니다. (운영 규칙: [`CLAUDE.md`](CLAUDE.md) · 원칙: [`ETHOS.md`](ETHOS.md))

---

## 目次

- [ドキュメント](#ドキュメント)
- [なぜ BATHOS か](#なぜ-bathos-か)
- [仕組み: 2 つのプレーン](#仕組み-2-つのプレーン)
- [必要要件](#必要要件)
- [クイックスタート](#クイックスタート)
- [7 ウェーブのパイプライン](#7-ウェーブのパイプライン)
- [スケール適応型ルーティング (Lv0–4)](#スケール適応型ルーティング-lv04)
- [品質ゲート](#品質ゲート)
- [CLI リファレンス (`bathos` エンジン)](#cli-リファレンス-bathos-エンジン)
- [スラッシュコマンド](#スラッシュコマンド)
- [17 のロール](#17-のロール)
- [プラグインモジュール](#プラグインモジュール)
- [セーフティフック](#セーフティフック)
- [リポジトリ構成](#リポジトリ構成)
- [設定](#設定)
- [プロジェクトの状態](#プロジェクトの状態)
- [BATHOS はどう作られたか (ドッグフーディング)](#bathos-はどう作られたか-ドッグフーディング)
- [コントリビューション](#コントリビューション)
- [ライセンスと帰属](#ライセンスと帰属)

---

## ドキュメント

| ドキュメント | English | 한국어 | Español | 用途 |
|-----|:----------:|:---------:|:---------:|---------------|
| **ユースケース** — 新しいサービスをステップバイステップで構築 | [`docs/USECASE-en.md`](docs/USECASE-en.md) | [`docs/USECASE-kr.md`](docs/USECASE-kr.md) | [`docs/USECASE-es.md`](docs/USECASE-es.md) | まずはここから: 実践的なウォークスルー（自分のプロジェクトに導入し、「ReadShelf」を端から端まで構築） |
| **特徴と運用原則** | [`docs/FEATURES-en.md`](docs/FEATURES-en.md) | [`docs/FEATURES-kr.md`](docs/FEATURES-kr.md) | [`docs/FEATURES-es.md`](docs/FEATURES-es.md) | BATHOS を特徴づけるものと、エンジンが内部でどう動くか |
| **使用ガイド** | [`docs/USAGE-en.md`](docs/USAGE-en.md) | [`docs/USAGE-kr.md`](docs/USAGE-kr.md) | [`docs/USAGE-es.md`](docs/USAGE-es.md) | リファレンス: インストール、CLI、ウェーブ、ゲート、フック、トラブルシューティング |
| **トークンとクォータの管理** | [`docs/QUOTA-en.md`](docs/QUOTA-en.md) | [`docs/QUOTA-kr.md`](docs/QUOTA-kr.md) | [`docs/QUOTA-es.md`](docs/QUOTA-es.md) | コストの制御、ウェーブのシーケンス、使用量制限からの復帰 |
| **カスタムモジュールの作成** | [`docs/MODULE-GUIDE-en.md`](docs/MODULE-GUIDE-en.md) | [`docs/MODULE-GUIDE-kr.md`](docs/MODULE-GUIDE-kr.md) | [`docs/MODULE-GUIDE-es.md`](docs/MODULE-GUIDE-es.md) | コアに触れずに自作プラグインを書く（module.yaml、トリガー DSL、W4） |
| **ロールのカスタマイズ** | [`docs/ROLE-GUIDE-en.md`](docs/ROLE-GUIDE-en.md) | [`docs/ROLE-GUIDE-kr.md`](docs/ROLE-GUIDE-kr.md) | [`docs/ROLE-GUIDE-es.md`](docs/ROLE-GUIDE-es.md) | 3 層オーバーライド（base → team → user）で 17 のロールを調整 |
| **アーキテクチャ**（コントリビューター向け） | [`docs/ARCHITECTURE-en.md`](docs/ARCHITECTURE-en.md) | [`docs/ARCHITECTURE-kr.md`](docs/ARCHITECTURE-kr.md) | [`docs/ARCHITECTURE-es.md`](docs/ARCHITECTURE-es.md) | クレートマップ、不変条件（A9、ゲート、監査）、終了/エラーコード、コントリビューション |
| **FAQ** | [`docs/FAQ-en.md`](docs/FAQ-en.md) | [`docs/FAQ-kr.md`](docs/FAQ-kr.md) | [`docs/FAQ-es.md`](docs/FAQ-es.md) | よくある質問とトラブルシューティング |
| **運用ルール / 原則** | [`CLAUDE.md`](CLAUDE.md) · [`ETHOS.md`](ETHOS.md) | | | チーム運用ルールと gstack 由来の ETHOS |

> **はじめての方へ** **ユースケース** → **特徴** → **使用ガイド** の順にお読みください。

---

## なぜ BATHOS か

長大な単一 LLM 会話はドリフトします。「設計」と「構築」の間でコンテキストが失われ、品質チェックは飛ばされ、同じモデルが自分の作業を書きつつ自分で承認します。BATHOS はそれを構造で置き換えます。

| 素の LLM チャット | BATHOS |
|---|---|
| 一つの会話、増大するコンテキストドリフト | **7 ウェーブ** パイプラインにまたがる **17 の専門ロール** |
| 設計 ↔ 実装の間でコンテキストが喪失 | **Zero-Context-Loss** な自己完結型ストーリーファイル（Wave 3） |
| 暗黙的で一律の労力 | **スケール適応型ルーター** — 明示的な Lv0–4 |
| 実装がいつでも始まってしまう | **厳格なレディネスゲート** が `FAIL` のとき構築を物理的にブロック |
| 作者自身が「検証」も行う | **独立したレビュアー** + 改ざん検知可能な監査チェーン |
| こっそりあなたを上書きする助言 | **User Sovereignty** — AI が提案し、決めるのは *あなた* |

その結果: 一人でも、ディスカバリー → 設計 → 実装 → 検証 を通して AI チームを走らせられ、各ステップにトレーサビリティとゲートが伴います。

---

## 仕組み: 2 つのプレーン

これが最も重要な概念です。BATHOS は **2 つのレイヤー** の上で動きます。

| プレーン | 実体 | 役割 | 誰が動かすか |
|---|---|---|---|
| **Orchestration** | `.claude/` 配下の Markdown による **スラッシュコマンド**、**ロール**、**フック** | ウェーブを実行し、チームメイトをスポーン / レビュー / シャットダウン | **リード（Paul）** — あなたのメイン Claude Code セッション |
| **Engine** | 単一の静的 Rust バイナリ **`bathos`** | 状態、ゲート、ウェーブ遷移、ルーティング、ストーリーの鮮度、プラグインを計算し *強制* する | フックとコマンドによって自動的に呼ばれる（`bathos <subcommand>`） |

あなたが主にタイプするのは **スラッシュコマンド**（例: `/wave1-discovery`）です。`bathos` バイナリは、それらのコマンドとフックが裏で呼び出す決定論的コアであり、直接実行することもできます。

---

## 必要要件

- **[Claude Code](https://claude.com/claude-code) v2.1.32+**、**Agent Teams** 実験的機能を有効化すること
  （`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`; 同梱の `.claude/settings.json` が既に設定済み）
- **Rust toolchain**（cargo 1.92+ で検証済み）— エンジンのビルドに必要
- **`jq`** — セーフティフックが JSON パースに使用
- POSIX シェル環境（macOS/Linux）; フックは bash

---

## クイックスタート

### 1. コードを取得してエンジンをビルド

```bash
git clone <your-fork-url> bathos && cd bathos

# Build the single static engine binary (~5.9 MB)
cd core
cargo build --release          # → core/target/release/bathos
cargo test                     # 510 tests, all green (optional sanity check)
cd ..

# Make the engine discoverable by hooks/commands:
export BATHOS_BIN="$(pwd)/core/target/release/bathos"
#   …or add core/target/release to your PATH
```

### 2. BATHOS をプロジェクトで使う

**オプション A — このリポジトリを作業ディレクトリとして使う。** `.claude/` ディレクトリ（コマンド、エージェント、フック、設定）は既に配線済みです。ここで Claude Code を開くだけです。

**オプション B — 自分のプロジェクトに導入する。** `.claude/`（コマンド、エージェント、フック、`settings.json`）、`assets/`、`modules/` を自分のプロジェクトルートにコピーし、上記のように `BATHOS_BIN` を設定します。

### 3. パイプラインを駆動する（Claude Code 内のスラッシュコマンド）

```text
/team-kickoff                       # scaffold .agent-team/ + charter + manifest
/route        /abs/path/to/project  # analyze "stakes" → recommend Lv0–4 (you confirm)
/wave1-discovery   /abs/path        # discovery + market research
/wave2-design      /abs/path        # planning · architecture · design
/wave3-story-gate  /abs/path        # ★ condense to story files + readiness gate
/wave5-implement   /abs/path        # implementation
/wave6-verify-report /abs/path      # verification · docs · report
/team-confirm                       # final sign-off + cleanup
```

### エンジンを直接試す

```bash
# Recommend a Scale-Adaptive level from "stakes" (recommend only; does not commit)
echo '{"scope":"feature","novelty":true,"regulation_ip":false,"team_size":"medium"}' \
  | bathos --state-dir .agent-team/_state route decide
#   → {"recommended_level":2,"wave_set":[...],"role_set":[...],"requires_confirmation":true}
```

---

## 7 ウェーブのパイプライン

```
(pre) kickoff → W0 Analysis → W1 Discovery → W2 Design
        → W3 Story Gate ★ → W5 Implementation → W6 Verify → (post) Confirm
                                  ↑
                       W4 IP & Research  (optional plug-in, off the critical path)
```

メインラインの依存関係: **W0 → W1 → W2 → W3 → W5 → W6**。W4（IP と研究）はオプションのプラグインで、W2 以降であればいつでも実行できます。

| コマンド | ウェーブ | チーム（並列） | ゲート |
|---|---|---|---|
| `/team-kickoff` | (pre) | リードのみ | — |
| `/wave0-analysis` | **W0** Analysis（オプション） | Caleb | Brief Readiness |
| `/wave1-discovery` | **W1** Discovery & market | John ∥ Caleb | USP Readiness |
| `/wave2-design` | **W2** Plan · architecture · design | Joshua → (James, Jonnathan) | Plan Readiness |
| `/wave3-story-gate` | **W3** Story engineering ★ | Matthew + Thomas · Matthias + Timothy | **Implementation Readiness** |
| `/wave4-ip-research` | **W4** IP & research（プラグイン） | Mark ∥ Nathanael | — |
| `/wave5-implement` | **W5** Implementation | Phillip, Andrew, Stephen | ストーリー単位の完了 |
| `/wave6-verify-report` | **W6** Verify · docs · report | (Thomas, Timothy, Matthias) → Michael → Hananiah → Martin | Release Readiness |
| `/team-confirm` | (post) | リードのみ | — |

**なぜ W3 が心臓部なのか。** Wave 3 は設計→構築のコンテキストギャップを塞ぎます。ロール #17 **Matthew** が上流の作業を **自己完結型の dev ストーリーファイル** に凝縮し（9 セクション、あらゆる技術的主張に `[Source: …]` タグを付与）、Thomas と Matthias がそれを独立してレビューし、判定が `FAIL` の場合は `gate-enforce` フックが W5 への入場を **物理的にブロック** します。

---

## スケール適応型ルーティング (Lv0–4)

BATHOS はタスクが実際に必要とするウェーブだけを起動します。レベルはあなたが確定し（User Sovereignty）、`manifest.json` に記録されます。

| Lv | 作業タイプ | 起動ウェーブ | #17 Matthew | W4 |
|----|-----------|--------------|:---:|:--:|
| **0** | バグ修正 / 些細 | W5（+ 最小限の W6） | ✗ | ✗ |
| **1** | 小機能 / 局所リファクタ | 軽量 W2 + W3（slim）+ W5 + 軽量 W6 | ✓ (slim) | ✗ |
| **2** | 標準機能 / モジュール | W1 + W2 + W3 + W5 + W6 | ✓ | 選択 |
| **3** | 新製品 / 大規模 | W0–W6（W4 選択） | ✓ | 推奨 |
| **4** | エンタープライズ / ディープテック / 規制対象 | フル W0–W6 + W4 | ✓ | 必須 |

推奨値は 4 つの stakes 軸 — `scope`、`novelty`、`regulation_ip`、`team_size` — からルーターが計算します。

---

## 品質ゲート

すべてのウェーブゲートは一つの語彙を使います。

| 判定 | 意味 | 効果 |
|---|---|---|
| **PASS** | 基準を満たし、ブロッカーなし | 次のウェーブへ進む |
| **CONCERNS** | 条件付き通過（非ブロッキングリスク） | `_state/` にリスクを記録し、進む |
| **FAIL** | ブロッキング欠陥 | 入場をブロック; 是正して再ゲート |

ゲートは **generator ではなく facilitator** です — 根拠のない自動 PASS はありません。W3 ゲートはフックによって強制されます（終了コード `2` が W5 をブロック）。判定の真実の源はエンジンです: `bathos gate show`。

---

## CLI リファレンス (`bathos` エンジン)

グローバルオプション: `-s, --state-dir <PATH>`（デフォルト `./_state`）、`--modules-dir <PATH>`（デフォルト `./modules`）、`-h/--help`、`-V/--version`。
終了コード: `0` 成功 · `1` エラー · `2` ゲート FAIL（フックがブロックに使用）。

| コマンド | サブコマンド | 目的 |
|---|---|---|
| `state` | `init`, `validate`, `show` | 信頼できる唯一の情報源 `manifest.json` の作成・検証・表示 |
| `route` | `decide`, `show` | スケール適応型レベルの推奨（stdin/`--stakes-json`; `--confirm <0-4>` で記録） |
| `wave` | `init`, `activate`, `show` | 7 ウェーブの状態遷移（並列度 ≤ 3 を強制） |
| `gate` | `verdict`, `show` | ゲート判定の記録 / 読み取り（PASS/CONCERNS/FAIL; FAIL → 終了 2） |
| `story` | `compile`, `check-stale` | ストーリーファイルの完全性（D1）、ソーストレース（D2）、鮮度（D3） |
| `plug` | `list`, `enable`, `disable` | プラグインモジュールの切り替え（IP パック、研究パック、…） |
| `audit` | `append`, `verify` | 改ざん検知可能な監査ハッシュチェーンへの追記 / **検証**（`verify` → `E-AUDIT-TAMPER` で終了 1） |
| `doctor` | — | **インストール/配線のプリフライト** — `BATHOS_BIN`、`jq`、Agent Teams フラグ、`settings.json` の hooks ブロック（コメントキーによるハング）、フックの実行ビット、manifest スキーマ、監査チェーン |

```bash
bathos -s _state state init --codename MYPROJECT       # スキーマ準拠の manifest seed を作成
bathos -s _state state validate                       # validate manifest.json
bathos -s _state gate verdict Implementation PASS Matthew
bathos -s _state gate show                            # latest Implementation gate (JSON)
bathos --modules-dir modules plug list                # modules + enabled state
bathos -s _state audit append --actor hook --action tool.write --target manifest.json
```

例付きの完全なリファレンス: **[`docs/USAGE-kr.md`](docs/USAGE-kr.md)**（韓国語）。

---

## スラッシュコマンド

`.claude/commands/` 配下に 34 のコマンドが同梱されています。

- **ウェーブ:** `wave0-analysis`, `wave1-discovery`, `wave2-design`, `wave3-story-gate`, `wave4-ip-research`, `wave5-implement`, `wave6-verify-report`
- **ルーティング:** `route`
- **チーム:** `team-kickoff`, `team-status`, `team-confirm`, `team-cleanup`
- **プランレビュー（W2 強化）:** `autoplan`, `plan-ceo-review`, `plan-design-review`, `plan-eng-review`, `plan-devex-review`
- **セッションの保存/復元:** `save-session`, `cold-start`（正本 — 完全保存とフルコールドスタート復元）; `save` / `resume`（短縮エイリアス）; `context-save` / `context-restore`（gstack エイリアス）
- **クロスプロジェクトメモリ:** `project-handoff`（このプロジェクトを `~/.bathos/registry/` に蒸留）、`recall`（関連する過去プロジェクトのコンテキストを新プロジェクトに引き込む）
- **エンジニアリング運用:** `review`, `investigate`, `cso`（OWASP + STRIDE）, `retro`, `health`, `guard`, `unfreeze`, `context-save`, `context-restore`

---

## 17 のロール

リード（#0 Paul）はあなたのメインセッションであり、決してスポーンされません。ロール #1–#17 はウェーブごとにスポーンされ、並列度は 3 に制限されます。

| # | 名前 | ロール | モデル | ウェーブ |
|---|------|------|-------|------|
| 0 | Paul | リード / 最終確認 | Opus 4.8 | 全て（メインセッション） |
| 1 | John | リバーススペシャリスト | Opus 4.8 | W1 (+W0) |
| 2 | Caleb | 市場分析 / USP（+W0 アナリスト） | Opus 4.8 | W1 (+W0) |
| 3 | Joshua | サービス企画 | Opus 4.8 | W2（ゲート） |
| 4 | James | SW / クラウドアーキテクト | Opus 4.8 | W2 |
| 5 | Mark | IP スペシャリスト（特許） | Opus 4.8 | W4 |
| 6 | Nathanael | 論文執筆（abstract/intro） | Sonnet 5 | W4 |
| 7 | Jonnathan | チーフデザイナー（UX/UI） | Opus 4.8 | W2 |
| 8 | Phillip | バックエンド & データリード | Sonnet 5 | W5 |
| 9 | Andrew | フロントエンド & モバイルリード | Sonnet 5 | W5 |
| 10 | Stephen | AI/ML リード | Sonnet 5 | W5 |
| 11 | Timothy | 開発定義ドキュメント | Sonnet 5 | W6 (+W3) |
| 12 | Thomas | コードレビュアー | Sonnet 5 | W6 (+W3) |
| 13 | Michael | セキュリティスペシャリスト（防御的なウェブ/サイバー監査とハードニング） | Sonnet 5 | W6（Thomas の後） |
| 14 | Hananiah | リファクタリングスペシャリスト（動作保存） | Sonnet 5 | W6（Michael の後） |
| 15 | Matthias | QA / 検証（E2E） | Sonnet 5 | W6 (+W3) |
| 16 | Martin | モニタリング / HTML レポート | Sonnet 5 | W6 |
| **17** | **Matthew** | **スクラムマスター / ストーリーエンジニア** | Opus 4.8 | **W3 のみ（それ以外はアイドル）** |

ロール定義は `.claude/agents/_base/` にあり、3 層オーバーライド（base → team → user）をサポートします。

---

## プラグインモジュール

コアはスリムなまま保たれ、ドメイン能力は `modules/` 配下のオプトインプラグインです（コアがモジュールに依存することは決してありません — A9）。各モジュールは `module.yaml` で自らを宣言します。

```yaml
module_id: ip                    # ip | research | game | security ...
name: IP Pack
wave: W4
trigger: "Lv>=3 OR domain=ip"    # auto-enable condition
enabled_default: false
provides:
  workflows: [patent-spec-draft]
  templates: [patent-spec]
outputs: ".agent-team/05-ip/"
evidence_trace: true
```

同梱: **`ip-pack`**（特許明細書のドラフト作成）と **`research-pack`**（学術的な abstract/introduction）。`bathos plug enable <id>` / `disable <id>` で切り替えます。

---

## セーフティフック

`.claude/settings.json` は、6 つの決定論的でフェイルセーフなフックを Claude Code のイベント（`PreToolUse`, `PostToolUse`, `TaskCompleted`, `SubagentStop`, `TeammateIdle`）にバインドします。

| フック | イベント | 目的 |
|---|---|---|
| `careful-guard.sh` | PreToolUse(Bash) | 破壊的コマンドをブロック（`rm -rf`, `DROP TABLE`, `git push --force`, `WHERE` なしの `DELETE`, `TRUNCATE`） |
| `freeze-guard.sh` | PreToolUse(Write/Edit) | 編集を所有パスに限定 |
| `audit-log.sh` | PostToolUse | すべてのツール使用を監査チェーンに追記 |
| `artifact-verify.sh` | TaskCompleted / SubagentStop | 必須成果物 / ストーリーファイルの完全性を検証 |
| `gate-enforce.sh` | TaskCompleted | **W3 判定が FAIL のとき W5 入場をブロック** |
| `next-action.sh` | TeammateIdle | 次のアクションを提案 |

> `settings.json` の `hooks` ブロック内には **有効なフックイベント名のみ** を保ってください — そこに紛れ込んだコメントキーはサブエージェントの起動をハングさせます。

---

## リポジトリ構成

```
bathos/
├── core/                       # Rust workspace (the engine, 7 crates, ~9,200 LOC)
│   ├── Cargo.toml
│   └── crates/
│       ├── bathos-state/       # state SSOT: manifest.json + tamper-evident audit chain
│       ├── bathos-router/      # scale-adaptive Lv0–4 router
│       ├── bathos-wave-engine/ # 7-wave transitions, concurrency ≤ 3
│       ├── bathos-gate-engine/ # PASS/CONCERNS/FAIL verdicts
│       ├── bathos-story-engine/# story compilation, staleness (zero-context-loss)
│       ├── bathos-plug/        # plugin module manager
│       └── bathos-cli/         # the `bathos` binary
├── .claude/
│   ├── agents/_base/           # 17 role definitions (00-paul … 17-matthew-story-engineer)
│   ├── commands/               # 34 slash commands
│   ├── hooks/                  # 6 safety/event hooks + test harness
│   └── settings.json           # hook bindings + Agent Teams flag
├── assets/                     # templates, workflows, checklists, glossary
├── modules/                    # plugin modules: ip-pack, research-pack
├── docs/USAGE-kr.md            # detailed usage guide (Korean)
├── CLAUDE.md  ETHOS.md  VERSION  README.md
```

実行が生成するチーム成果物は `.agent-team/` 配下に置かれます（plan、discovery、architecture、story engineering、reviews、QA、reports、そして `_state/`）。実際の製品ソースコードは、あなたのプロジェクトの通常のパス（`src/` など）に置かれたままです。

---

## 設定

- **エンジン state ディレクトリ** — `--state-dir`（デフォルト `./_state`）; SSOT は `<state-dir>/manifest.json`（JSON-Schema で検証、アトミック書き込み、監査ハッシュチェーン）。
- **modules ディレクトリ** — `--modules-dir`（デフォルト `./modules`）。
- **フック用のエンジンパス** — `BATHOS_BIN` 環境変数（`core/target/debug/bathos` にフォールバック）。
- **ロールのオーバーライド** — 3 層マージ: `base`（固定のアイデンティティ/モデル）→ `team`（プロジェクトの所有パス）→ `user`（言語/ファシリテーション）。スカラーは上書き、配列は追記。

---

## プロジェクトの状態

**v0.2.0 — 早期だが機能する。** BATHOS は今日、端から端までビルドされ動作します。導入者への正直な注意点。

- これは **Claude Code 上で動くメソッドパッケージ** であり、スタンドアロンのアプリではなく、**実験的な Agent Teams** 機能に依存します。
- エンジンは検証済み: **510 の Rust テスト + 86 のフック決定論性チェック、すべて green**; `cargo clippy -D warnings` はクリーン; リリースビルドは再現可能。
- **まだ本番向けにハードニングされていません**; API、スキーマ、コマンド名は 1.0 より前に変わる可能性があります。
- 一部のウェーブコマンドは、リードが Claude Code 内で実行する **オーケストレーションプロンプト**（チームメイトをスポーン/レビューする）であり、完全に自律的なエンジンフローではありません。

検証の証跡は `_state/signoff.md` と `12-report/` を参照してください。

---

## BATHOS はどう作られたか (ドッグフーディング)

BATHOS は自らを実装し、その後 **自分自身のコードに対して自らの Wave 6 独立検証を実行** しました。そのパスは意図的に *作者* と *レビュアー* を分離しました。機能 QA は green に見えましたが、独立したコードレビューは **作者が見落としていたブロッキングな不変条件の欠陥** を浮かび上がらせました（例: Rust エンジンと bash フックが同じ監査チェーンに *互換性のない* フォーマットを書き込んでおり、改ざん検知を静かに無効化していた）。それらのブロッカーは是正され、再ゲートされ、リグレッション/バックログは解消されました — 既知のレビュー欠陥はすべて解決済みです。

その教訓こそが本製品のテーゼです: **生成 ≠ 検証。** 完全な証跡は `.agent-team/` にあります（`10-review/`, `11-qa/`, `12-report/`, `_state/signoff.md`）。

---

## コントリビューション

コントリビューションを歓迎します。BATHOS はそれ自体が開発メソッドなので、ぜひそれ自身に対して使ってください。

1. 変更内容とそのスケール（Lv0–4）を記述した issue を開く。
2. コアをスリムに保つ — 新しいドメイン能力はコアではなく `modules/` に属します（プラグインへの逆依存なし）。
3. エンジンの変更については: `cd core && cargo test && cargo clippy --all-targets -- -D warnings` が green でなければなりません; 不変条件のテストを追加してください。
4. フックの変更については: `bash .claude/hooks/_test-hooks.sh` を実行; フックを決定論的かつフェイルセーフに保ってください。
5. ゲートの語彙（PASS/CONCERNS/FAIL）とセーフティフック（`careful`, `freeze`）を尊重してください。

3 つの運用原則（`ETHOS.md` より）: **User Sovereignty**（AI が提案し、あなたが決める）· **Boil the Ocean**（あと数分で完了するなら完全に仕上げる）· **Search Before Building**。

---

## ライセンスと帰属

**MIT License** の下でリリースされています — 全文は下記を参照してください。

```
MIT License

Copyright (c) 2026 BATHOS

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```

**系譜と謝辞。** BATHOS は独立に実装された作品です。そのメソッド設計は、**[BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD)**（MIT © 2025 BMad Code, LLC）の厳密なリバース分析を経て、第一原理から再実装されたものであり、そこからその基礎的な設計語彙を受け継いでいます。

私たちはこの系譜を、義務からではなく選択として明示します。*生成は検証に対して答責的であり続けねばならない* ことを中心的信条とするシステムが、自らが立脚する先行技術を覆い隠せば、自己矛盾に陥ります。ゆえに BATHOS は、BMAD-METHOD への負債を率直に、そして心からの敬意をもって記録します — それは BATHOS が深めようとした地形を切り拓きました。MIT License に従い、BMAD-METHOD の著作権とライセンス表示は [`LICENSE`](LICENSE) に保存されています; 完全な謝辞は [`CREDITS.md`](CREDITS.md) にあります。

BATHOS は別個の、独立に実装されたプロジェクトであり、製品名やマーケティングにおいて商標「BMAD」、「BMad Method」、「BMad Builder」、「BMB」、「TEA」、「CIS」、「GDS」、「WDS」を使用**しません**。

---

<div align="center">

**BATHOS** · βάθος — 表層よりも深さを
한국어 문서: [`docs/USECASE-kr.md`](docs/USECASE-kr.md) · [`docs/FEATURES-kr.md`](docs/FEATURES-kr.md) · [`docs/USAGE-kr.md`](docs/USAGE-kr.md) · [`docs/QUOTA-kr.md`](docs/QUOTA-kr.md) · [`docs/MODULE-GUIDE-kr.md`](docs/MODULE-GUIDE-kr.md) · [`CLAUDE.md`](CLAUDE.md) · [`ETHOS.md`](ETHOS.md)

</div>
