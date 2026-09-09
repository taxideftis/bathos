# Credits & Acknowledgment

> βάθος — *depth*. What follows is where that depth begins, and to whom it is owed.

## Prior art — BMAD-METHOD

BATHOS is a distinct, independently implemented work. Its method design was re-implemented from first principles following a rigorous reverse analysis of **[BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD)** (MIT License, © 2025 BMad Code, LLC), from which it inherits its foundational design vocabulary — the wave pipeline, the specialist-role model, and the discipline of separating generation from verification.

We record this lineage by choice, not by obligation. A method whose central premise is that *generation must remain answerable to verification* would contradict its own thesis by obscuring the prior art on which it stands. So we state it plainly and with genuine respect: **BMAD-METHOD charted the terrain that BATHOS set out to deepen.** The foundational ideas are theirs; the independent re-implementation, and any faults within it, are ours.

In accordance with the MIT License, BMAD-METHOD's copyright and permission notice are preserved in [`LICENSE`](LICENSE). BATHOS does not use the trademarks "BMAD", "BMad Method", "BMad Builder", "BMB", "TEA", "CIS", "GDS", or "WDS" in its product name or marketing.

## Operating philosophy — gstack

BATHOS's ETHOS (User Sovereignty · Boil the Ocean · Search Before Building) adapts the principles of Garry Tan's **gstack**. See [`ETHOS.md`](ETHOS.md).

## Implementation discipline (Wave 5) — ponytail

The W5 ladder adapts engineering principles from **[ponytail](https://github.com/DietrichGebert/ponytail)** by Dietrich Gebert (MIT) — the YAGNI-first rung ladder, the "when not to be lazy" boundaries, and the deferred-simplification marker convention (`ponytail: <ceiling>, <upgrade path>`).

BATHOS absorbs the **principles only**. The persona, tone, and branding are deliberately not adopted, and the rules were rewritten for the wave/role context with an explicit precedence rule against ETHOS *Boil the Ocean* (the ladder governs scope; Boil the Ocean governs completeness). The reverse analysis and scope decision are recorded in [`_recon/ponytail-analysis.md`](_recon/ponytail-analysis.md); the rules themselves live in [`.claude/agents/_preamble/ponytail-inject-kr.md`](.claude/agents/_preamble/ponytail-inject-kr.md) (canonical KR, with `-en` / `-ja` / `-es` editions).

## Runtime — Claude Code

BATHOS is a method package; it runs on **Claude Code** (v2.1.32+, Agent Teams). It ships no runtime of its own.

---

# 크레딧 & 헌사

> βάθος — *깊이*. 아래는 그 깊이가 어디서 시작되었고, 누구에게 빚졌는지에 대한 기록이다.

## 선행 작업 — BMAD-METHOD

BATHOS는 독립적으로 구현된 별개의 저작물이다. 그 메서드 설계는 **[BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD)**(MIT License, © 2025 BMad Code, LLC)를 정밀하게 역분석한 뒤 제1원리에서 다시 구현한 것으로, 그 근간이 되는 설계 어휘 — 웨이브 파이프라인, 전문 역할 모델, 그리고 생성과 검증을 분리하는 규율 — 를 물려받았다.

이 계보를 의무가 아니라 선택으로 명시한다. *생성은 검증에 답해야 한다*는 명제를 핵심으로 삼은 체계가 정작 자신이 딛고 선 선행 작업을 가린다면, 그것은 스스로의 명제와 모순된다. 그러므로 분명하고 정중하게 밝힌다: **BMAD-METHOD는 BATHOS가 더 깊이 파고들고자 한 지형을 앞서 그려낸 작업이다.** 그 근간이 된 아이디어는 그들의 것이며, 독립 재구현과 그 안의 결함은 우리의 것이다.

MIT 라이선스에 따라 BMAD-METHOD의 저작권·라이선스 고지는 [`LICENSE`](LICENSE)에 보존한다. BATHOS는 "BMAD", "BMad Method", "BMad Builder", "BMB", "TEA", "CIS", "GDS", "WDS" 상표를 제품명·마케팅에 사용하지 않는다.

## 운영 철학 — gstack

BATHOS의 ETHOS(User Sovereignty · Boil the Ocean · Search Before Building)는 Garry Tan의 **gstack** 원칙을 적응한 것이다. [`ETHOS.md`](ETHOS.md) 참조.

## 구현 규율(Wave 5) — ponytail

W5의 사다리는 Dietrich Gebert의 **[ponytail](https://github.com/DietrichGebert/ponytail)**(MIT)에서 엔지니어링 원칙을 차용했다 — YAGNI를 첫 단에 두는 사다리, "게으르면 안 되는 것"의 경계, 그리고 유예된 단순화의 마커 규약(`ponytail: <ceiling>, <upgrade path>`).

BATHOS는 **원칙만** 흡수한다. 페르소나·톤·브랜딩은 의도적으로 도입하지 않았고, 규칙은 웨이브·역할 맥락에 맞게 재작성하면서 ETHOS *Boil the Ocean*과의 우선순위 규칙을 명시했다(사다리는 스코프를, Boil the Ocean은 완전성을 지배). 역분석과 범위 결정은 [`_recon/ponytail-analysis.md`](_recon/ponytail-analysis.md)에, 규율 본문은 [`.claude/agents/_preamble/ponytail-inject-kr.md`](.claude/agents/_preamble/ponytail-inject-kr.md)(정본 kr, `-en`/`-ja`/`-es` 판 병치)에 있다.

## 런타임 — Claude Code

BATHOS는 메서드 패키지이며 **Claude Code**(v2.1.32+, Agent Teams) 위에서 동작한다. 자체 런타임을 포함하지 않는다.
