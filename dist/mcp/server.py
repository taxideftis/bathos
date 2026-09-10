#!/usr/bin/env python3
# =============================================================================
# BATHOS Dynamis — dist/mcp/server.py
# CF-B6 / SS10 (Should · LD-2 승격) — MCP 최소공통 배포 채널(레퍼런스 어댑터).
#
# 이 서버는 "실행 표면"이 아니라 read-only 열화 계층이다(ADR-D-0004, LD-2).
# 훅·게이트 강제는 여기서 동작하지 않는다 — 항상 always-on 주입과 동등하지
# 않음을 사용자에게 알린다(surface-formats-kr.md §b-3 "열화 계층 고지").
#
# 제공 표면(경량 제약 — 이 3개를 초과하지 않는다, AC4):
#   - prompt: bathos-mcp      (사용자 호출 — 역할 instruction·웨이브 상태 안내)
#   - tool:   bathos_instructions  (read-only, canonical 소스 텍스트 그대로 반환)
#   - tool:   bathos_wave_state    (read-only, `bathos state show` JSON 중계)
#
# 포인터 원칙(B1 계승, 위반=포크): 이 서버는 behavior 텍스트를 재작성하지 않고
# canonical 소스(.claude/agents 등)를 그대로 로드해 반환한다. 아래 순수 로직
# 함수(load_instruction_text 등)는 mcp 패키지 없이도 단위테스트 가능하도록
# SDK 배선과 분리했다(dist/tests/test_mcp_server.py 참조).
#
# 런타임 언어 결정(R-B1, docs/agent-portability-kr.md §5): Python.
#   - 공식 MCP Python SDK 존재(Anthropic) — Search Before Building(2026-07-08,
#     story-b6 인용): MCP 스펙 revision 2025-11-25, ToolAnnotations
#     (readOnlyHint/openWorldHint)는 2025-03-26 도입된 표준 필드.
#   - 주의(CONCERNS, story-b6 §6): annotation은 "hint"일 뿐 프로토콜 강제가
#     아니다 — read-only 보장은 이 서버의 구현 자체(쓰기 코드 부재)가 담당한다.
#   - SDK 정확한 API 표면(예: 저수준 Server vs FastMCP 데코레이터)은 설치된
#     `mcp` 패키지 버전에 따라 달라질 수 있어 (추정) 표기를 유지한다. 이 파일은
#     저수준 `mcp.server.Server` API를 기준으로 작성했다(구조적으로 가장 안정적
#     이라 판단 — FastMCP 데코레이터형보다 명시적).
# =============================================================================
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Optional

# -----------------------------------------------------------------------------
# 1. 순수 로직 (mcp 패키지 불필요 — 단위테스트 대상)
# -----------------------------------------------------------------------------

# canonical 소스 하위 경로 매핑(docs/agent-portability-kr.md §0과 동일 규약)
CANON_SUBDIRS = {
    "role": "agents/_base",
    "preamble": "agents/_preamble",
    "skill": "skills",
    "command": "commands",
}

VALID_KINDS = tuple(CANON_SUBDIRS.keys())


def resolve_canon_root(bathos_root: Optional[Path] = None) -> Path:
    """canonical .claude 루트를 해석한다.

    LD-5(최종 조립은 W5 이후 Paul이 수행) 갭 처리: 제품 트리에 아직
    .claude/agents 가 없으면(구현자는 변경분만 커밋) 원본 bathos/.claude로
    폴백한다. 이 폴백은 임시이며 조립 후에는 제품 트리 경로가 우선된다.
    (check-rule-copies.sh의 resolve_canon_root()와 동일 규칙 — bash/python
    경계상 별도 구현이나 규칙은 동일하게 맞췄다.)
    """
    root = bathos_root or Path(__file__).resolve().parents[2]  # dist/mcp -> root
    product_tree = root / ".claude"
    if (product_tree / "agents").is_dir():
        return product_tree
    orig = root.parent.parent / "bathos" / ".claude"
    if (orig / "agents").is_dir():
        return orig
    raise FileNotFoundError(
        "canonical .claude 소스를 찾을 수 없습니다(제품 트리·원본 bathos/ 모두 부재). "
        "다음 행동: 최종 조립(LD-5) 후 재실행하거나 BATHOS_ROOT를 확인하세요."
    )


def list_available(kind: str, bathos_root: Optional[Path] = None) -> list[str]:
    """지정 kind(role/preamble/skill/command)에서 사용 가능한 이름 목록을 반환.

    포크 방지: 파일을 파싱/가공하지 않고 파일명만 나열한다.
    """
    if kind not in VALID_KINDS:
        raise ValueError(f"알 수 없는 kind: {kind} (허용: {', '.join(VALID_KINDS)})")
    canon = resolve_canon_root(bathos_root)
    base = canon / CANON_SUBDIRS[kind]
    if not base.is_dir():
        return []
    if kind == "skill":
        # 스킬은 <name>/SKILL.md 구조
        return sorted(p.parent.name for p in base.glob("*/SKILL.md"))
    return sorted(p.stem for p in base.glob("*.md"))


def load_instruction_text(kind: str, name: str, bathos_root: Optional[Path] = None) -> str:
    """canonical 소스 파일을 바이트 그대로 읽어 반환한다(AC1: 바이트 동일 보장).

    산문을 재작성/요약/번역하지 않는다 — 그대로 반환해야 스냅샷 테스트가
    "포크 0"을 검증할 수 있다.
    """
    if kind not in VALID_KINDS:
        raise ValueError(f"알 수 없는 kind: {kind} (허용: {', '.join(VALID_KINDS)})")
    canon = resolve_canon_root(bathos_root)
    if kind == "skill":
        path = canon / CANON_SUBDIRS[kind] / name / "SKILL.md"
    else:
        path = canon / CANON_SUBDIRS[kind] / f"{name}.md"
    if not path.is_file():
        available = list_available(kind, bathos_root)
        raise FileNotFoundError(
            f"'{kind}/{name}' 을(를) canonical 소스에서 찾을 수 없습니다. "
            f"사용 가능: {available}"
        )
    return path.read_text(encoding="utf-8")


def get_wave_state(bathos_bin: Optional[str] = None) -> dict:
    """`bathos state show`의 JSON 출력을 read-only로 중계한다.

    AC2(정직성): 바이너리가 없으면 **날조된 상태를 반환하지 않고** 명시적
    에러 구조를 돌려준다. fail-open이 아니라 "정직한 실패"다(B6 §5-3).
    """
    binary = bathos_bin or os.environ.get("BATHOS_BIN", "bathos")
    try:
        proc = subprocess.run(
            [binary, "state", "show"],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
    except FileNotFoundError:
        return {
            "error": "bathos_binary_not_found",
            "message": (
                f"'{binary}' 실행파일을 찾을 수 없습니다. bathos-cli가 빌드/설치되어 "
                "있는지 확인하세요(core/crates/bathos-cli, Phillip 소유). "
                "상태를 임의로 생성하지 않았습니다(날조 금지)."
            ),
        }
    except subprocess.TimeoutExpired:
        return {
            "error": "bathos_binary_timeout",
            "message": f"'{binary} state show' 가 10초 내에 응답하지 않았습니다.",
        }

    if proc.returncode != 0:
        return {
            "error": "bathos_state_show_failed",
            "message": f"'{binary} state show' 종료코드 {proc.returncode}: {proc.stderr.strip()}",
        }

    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        return {
            "error": "bathos_state_show_invalid_json",
            "message": "출력이 유효한 JSON이 아닙니다(원문 일부): " + proc.stdout[:200],
        }


DEGRADED_LAYER_NOTICE = (
    "[bathos mcp] ! 이 채널은 always-on 주입과 동등하지 않은 열화 계층입니다 — "
    "훅·게이트 물리 강제가 없습니다. 실행 표면이 아니라 read-only 조회 채널입니다 "
    "(ADR-D-0004, docs/agent-portability-kr.md §3-1)."
)


# -----------------------------------------------------------------------------
# 2. MCP 서버 배선 (mcp 패키지 필요 — 지연 임포트로 순수 로직과 분리)
# -----------------------------------------------------------------------------

def build_server():
    """mcp SDK로 저수준 Server 인스턴스를 구성한다.

    (추정) API 표면: 설치된 `mcp` 패키지 버전에 따라 세부 시그니처가 다를 수
    있음 — 이 함수는 여기서만 mcp를 임포트하므로, mcp 미설치 환경에서도
    위의 순수 로직 함수는 정상적으로 단위테스트 가능하다.
    """
    from mcp.server import Server
    from mcp.server.stdio import stdio_server
    from mcp.types import (
        Prompt,
        PromptMessage,
        TextContent,
        Tool,
        ToolAnnotations,
        GetPromptResult,
    )

    server = Server("bathos-dynamis-mcp")

    @server.list_prompts()
    async def list_prompts() -> list[Prompt]:
        return [
            Prompt(
                name="bathos-mcp",
                description=(
                    "BATHOS 역할 instruction과 웨이브 상태를 안내합니다. "
                    + DEGRADED_LAYER_NOTICE
                ),
                arguments=[],
            )
        ]

    @server.get_prompt()
    async def get_prompt(name: str, arguments: dict | None) -> GetPromptResult:
        if name != "bathos-mcp":
            raise ValueError(f"알 수 없는 prompt: {name}")
        state = get_wave_state()
        body = (
            DEGRADED_LAYER_NOTICE
            + "\n\n"
            + "사용 가능한 role/skill/command 목록은 bathos_instructions 도구로, "
            + "웨이브 상태는 bathos_wave_state 도구로 조회하세요.\n\n"
            + "현재 웨이브 상태(중계): "
            + json.dumps(state, ensure_ascii=False)
        )
        return GetPromptResult(
            description="BATHOS role instruction + wave state 안내",
            messages=[
                PromptMessage(role="user", content=TextContent(type="text", text=body))
            ],
        )

    READ_ONLY = ToolAnnotations(readOnlyHint=True, openWorldHint=False)

    @server.list_tools()
    async def list_tools() -> list[Tool]:
        return [
            Tool(
                name="bathos_instructions",
                description=(
                    "canonical 소스(.claude/agents|skills|commands)의 역할/스킬/"
                    "커맨드 산문을 바이트 그대로 반환합니다(read-only, 포크 없음). "
                    + DEGRADED_LAYER_NOTICE
                ),
                inputSchema={
                    "type": "object",
                    "properties": {
                        "kind": {"type": "string", "enum": list(VALID_KINDS)},
                        "name": {"type": "string"},
                    },
                    "required": ["kind", "name"],
                },
                annotations=READ_ONLY,
            ),
            Tool(
                name="bathos_wave_state",
                description=(
                    "`bathos state show`의 JSON 출력을 read-only로 중계합니다. "
                    "바이너리 부재 시 날조 없이 명시적 에러를 반환합니다. "
                    + DEGRADED_LAYER_NOTICE
                ),
                inputSchema={"type": "object", "properties": {}},
                annotations=READ_ONLY,
            ),
        ]

    @server.call_tool()
    async def call_tool(name: str, arguments: dict):
        if name == "bathos_instructions":
            kind = arguments.get("kind", "")
            iname = arguments.get("name", "")
            try:
                text = load_instruction_text(kind, iname)
            except (ValueError, FileNotFoundError) as exc:
                return [TextContent(type="text", text=f"오류: {exc}")]
            return [TextContent(type="text", text=text)]
        if name == "bathos_wave_state":
            state = get_wave_state()
            return [TextContent(type="text", text=json.dumps(state, ensure_ascii=False, indent=2))]
        raise ValueError(f"알 수 없는 tool: {name}")

    return server, stdio_server


async def main() -> None:
    server, stdio_server = build_server()
    from mcp.server.models import InitializationOptions
    # SEC-04 fix: pass a real NotificationOptions() instance. The mcp SDK (1.28.1)
    # dereferences notification_options.prompts_changed during get_capabilities(),
    # so passing None crashes at startup (AttributeError). NotificationOptions is
    # exported from mcp.server alongside the low-level Server used in build_server().
    from mcp.server import NotificationOptions

    async with stdio_server() as (read_stream, write_stream):
        await server.run(
            read_stream,
            write_stream,
            InitializationOptions(
                server_name="bathos-dynamis-mcp",
                server_version="0.4.0",
                capabilities=server.get_capabilities(
                    notification_options=NotificationOptions(),
                    experimental_capabilities={},
                ),
            ),
        )


if __name__ == "__main__":
    try:
        import asyncio

        asyncio.run(main())
    except ModuleNotFoundError as exc:
        sys.stderr.write(
            "[bathos mcp] ✗ 'mcp' 패키지가 설치되어 있지 않습니다 "
            f"({exc}). 다음 행동: `pip install mcp` 후 재실행하세요.\n"
        )
        sys.exit(1)
