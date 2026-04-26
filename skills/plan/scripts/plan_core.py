#!/usr/bin/env python3
"""Portable planning core shared by the plan skill and other adapters."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shlex
import sys
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

VALID_KINDS = {"software", "universal"}
VALID_STATUSES = {"planned", "in_progress", "blocked", "done"}
VALID_MODES = {
    "feature",
    "fix",
    "refactor",
    "investigation",
    "writing",
    "strategy",
    "trip",
    "study",
    "runbook",
    "proposal",
}

PLAN_PATH_RE = re.compile(r"@?(?P<path>[\w./-]+\.md)\b")
CODE_PATH_RE = re.compile(
    r"[\w./-]+\.(?:py|ts|tsx|js|jsx|rb|go|rs|java|kt|swift|c|cc|cpp|h|hpp|"
    r"sh|bash|zsh|fish|sql|proto|graphql|tf|toml|json|ya?ml)\b"
)

SOFTWARE_PATTERNS: Tuple[Tuple[str, re.Pattern[str]], ...] = (
    ("refactor", re.compile(r"\b(refactor|rewrite|cleanup|simplify|rename|extract)\b", re.IGNORECASE)),
    ("fix", re.compile(r"\b(bug|fix|regression|error|stack trace|exception|crash|flaky)\b", re.IGNORECASE)),
    ("feature", re.compile(r"\b(feature|implement|build|add|support|auth|endpoint|migration|cli)\b", re.IGNORECASE)),
    ("investigation", re.compile(r"\b(investigate|diagnose|root cause|trace|why is|audit)\b", re.IGNORECASE)),
)

UNIVERSAL_PATTERNS: Tuple[Tuple[str, re.Pattern[str]], ...] = (
    ("trip", re.compile(r"\b(trip|travel|itinerary|vacation|flight|hotel|disney)\b", re.IGNORECASE)),
    ("proposal", re.compile(r"\b(proposal|pitch|candidate memo|product proposal)\b", re.IGNORECASE)),
    ("strategy", re.compile(r"\b(strategy|proposal|positioning|go-to-market|roadmap|candidate)\b", re.IGNORECASE)),
    ("writing", re.compile(r"\b(article|essay|post|draft|outline|write this|rewrite)\b", re.IGNORECASE)),
    ("study", re.compile(r"\b(study|syllabus|curriculum|learn|course)\b", re.IGNORECASE)),
    ("runbook", re.compile(r"\b(runbook|playbook|incident|operational|on-call|checklist)\b", re.IGNORECASE)),
    ("investigation", re.compile(r"\b(research this|investigate this|look into)\b", re.IGNORECASE)),
)

SOFTWARE_HINTS = re.compile(
    r"\b(repo|repository|code|codebase|test|tests|lint|compile|branch|diff|pr|issue|"
    r"api|library|framework|sdk|module|package|cli)\b",
    re.IGNORECASE,
)
UNIVERSAL_HINTS = re.compile(
    r"\b(transcript|meeting|notes|proposal|strategy|trip|travel|article|outline|"
    r"syllabus|runbook|itinerary|vacation|flight|hotel)\b",
    re.IGNORECASE,
)
EXTERNAL_RESEARCH_HINTS = re.compile(
    r"\b(vs|versus|compare|should we adopt|choose|pick|vendor|library|framework|"
    r"pricing|current|latest|recent|travel|trip)\b",
    re.IGNORECASE,
)
FANOUT_RESEARCH_HINTS = re.compile(
    r"\b("
    r"large|complex|ambiguous|unclear|unknown|cross[- ]?cutting|multi[- ]?step|"
    r"project|epic|architecture|architectural|migration|integrat(?:e|ion)|"
    r"legacy|monorepo|codebase|unfamiliar|risky|high[- ]?risk|system|workflow"
    r")\b",
    re.IGNORECASE,
)
SMALL_CHANGE_HINTS = re.compile(
    r"\b(typo|one[- ]?line|small|tiny|simple|quick|trivial)\b",
    re.IGNORECASE,
)
SOFTWARE_COMPARISON_HINTS = re.compile(
    r"\b(vs|versus|compare|should we adopt|choose|pick|library|framework|tool|"
    r"sdk|api|playwright|browser)\b",
    re.IGNORECASE,
)
STOPWORDS = {
    "a",
    "an",
    "and",
    "the",
    "this",
    "that",
    "to",
    "for",
    "of",
    "on",
    "in",
    "with",
    "from",
    "into",
    "plan",
    "create",
    "make",
    "turn",
    "rough",
    "should",
    "we",
    "adopt",
    "vs",
    "versus",
}
SOURCE_REFERENCE_HINTS = re.compile(
    r"\b(this|these)\s+(transcript|screenshot|screenshots|notes|doc|document|"
    r"meeting transcript|recording)\b",
    re.IGNORECASE,
)
GUIDANCE_FILES = ("AGENTS.md", "CLAUDE.md", "README.md")
BACKTICK_PLAN_PATH_RE = re.compile(r"`([^`]*plans[^`]*)`", re.IGNORECASE)
PLAIN_PLAN_PATH_RE = re.compile(
    r"(?<![\w/.-])((?:\.{1,2}/)?(?:[\w.-]+/)*[\w.-]*plans[\w.-]*(?:/[\w.-]+)*)/?(?![\w/.-])",
    re.IGNORECASE,
)

SHARED_REQUIRED_SECTIONS = ["Goal", "Context", "Constraints", "Approach", "Open Questions"]
SOFTWARE_REQUIRED_SECTIONS = [
    "Existing Patterns",
    "Files",
    "Tasks",
    "Acceptance Criteria",
    "Validation",
    "Risks",
]
SOFTWARE_OPTIONAL_SECTIONS = ["Implementation Units"]
SOFTWARE_INVESTIGATION_OPTIONAL_SECTIONS = [
    "Decision",
    "Options",
    "Evaluation Criteria",
    "Evidence",
    "Recommendation",
    "Next Experiment",
]
UNIVERSAL_MODE_SECTIONS = {
    "trip": ["Itinerary", "Reminders", "Budget"],
    "proposal": ["Proposal", "Recommendation", "Open Risks"],
    "study": ["Syllabus", "Milestones", "Resources"],
    "strategy": ["Options", "Recommendation", "Success Metrics"],
    "writing": ["Outline", "Drafts", "References"],
    "runbook": ["Timeline", "Responsibilities", "Checklist"],
    "investigation": ["Questions", "Sources", "Findings"],
}


@dataclass(frozen=True)
class ExistingPlan:
    path: Path
    kind: Optional[str]
    mode: Optional[str]


@dataclass(frozen=True)
class Frontmatter:
    values: Dict[str, Any]
    body: str
    errors: List[str]


def skill_root_from_script() -> Path:
    return Path(__file__).resolve().parents[1]


def resolve_path(path_text: str, base: Path) -> Path:
    path = Path(path_text).expanduser()
    return path if path.is_absolute() else base / path


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def read_json(path_text: str) -> Dict[str, Any]:
    if path_text == "-":
        return json.load(sys.stdin)
    with Path(path_text).expanduser().open(encoding="utf-8") as handle:
        return json.load(handle)


def strip_quotes(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        return value[1:-1]
    return value


def parse_frontmatter(text: str) -> Frontmatter:
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return Frontmatter({}, text, ["missing opening frontmatter delimiter"])

    end_index: Optional[int] = None
    for index, line in enumerate(lines[1:], start=1):
        if line.strip() == "---":
            end_index = index
            break

    if end_index is None:
        return Frontmatter({}, text, ["missing closing frontmatter delimiter"])

    values: Dict[str, Any] = {}
    errors: List[str] = []
    current_list_key: Optional[str] = None
    key_re = re.compile(r"^([A-Za-z_][A-Za-z0-9_-]*):(?:\s*(.*))?$")
    item_re = re.compile(r"^\s+-\s*(.*)$")

    for lineno, line in enumerate(lines[1:end_index], start=2):
        if not line.strip():
            continue

        item_match = item_re.match(line)
        if item_match:
            if current_list_key is None:
                errors.append(f"frontmatter line {lineno}: list item without a list key")
                continue
            values.setdefault(current_list_key, []).append(strip_quotes(item_match.group(1)))
            continue

        if line.startswith((" ", "\t")):
            errors.append(f"frontmatter line {lineno}: unexpected indentation")
            continue

        key_match = key_re.match(line)
        if not key_match:
            errors.append(f"frontmatter line {lineno}: expected key: value")
            current_list_key = None
            continue

        key, raw_value = key_match.group(1), key_match.group(2)
        if raw_value is None or raw_value == "":
            values[key] = []
            current_list_key = key
        else:
            values[key] = strip_quotes(raw_value)
            current_list_key = None

    body = "\n".join(lines[end_index + 1 :])
    return Frontmatter(values, body, errors)


def frontmatter_field(text: str, key: str) -> Optional[str]:
    parsed = parse_frontmatter(text)
    value = parsed.values.get(key)
    return value if isinstance(value, str) else None


def find_existing_plan(request_text: str, repo_root: Path) -> Optional[ExistingPlan]:
    for match in PLAN_PATH_RE.finditer(request_text):
        raw_path = Path(match.group("path"))
        candidate = raw_path if raw_path.is_absolute() else repo_root / raw_path
        if not candidate.exists() or not candidate.is_file():
            continue

        text = read_text(candidate)
        kind = frontmatter_field(text, "kind")
        mode = frontmatter_field(text, "mode")
        if candidate.name.endswith("-plan.md") or kind in VALID_KINDS:
            return ExistingPlan(path=candidate, kind=kind, mode=mode)

    return None


def detect_mode(request_text: str, kind: Optional[str]) -> str:
    patterns = SOFTWARE_PATTERNS if kind == "software" else UNIVERSAL_PATTERNS
    for mode, pattern in patterns:
        if pattern.search(request_text):
            return mode
    return "investigation" if kind == "software" else "strategy"


def classify_kind(request_text: str, explicit_kind: str) -> Tuple[Optional[str], Optional[str], str]:
    if explicit_kind != "auto":
        mode = detect_mode(request_text, explicit_kind)
        return explicit_kind, mode, f"explicit kind override: {explicit_kind}"

    has_universal_hints = bool(UNIVERSAL_HINTS.search(request_text))
    has_software_hints = bool(SOFTWARE_HINTS.search(request_text))

    if has_universal_hints and not has_software_hints:
        return "universal", detect_mode(request_text, "universal"), "universal planning language detected"

    if CODE_PATH_RE.search(request_text):
        return "software", detect_mode(request_text, "software"), "file or code path detected"

    if has_software_hints and not has_universal_hints:
        return "software", detect_mode(request_text, "software"), "software planning language detected"

    if SOFTWARE_COMPARISON_HINTS.search(request_text) and not has_universal_hints:
        return "software", "investigation", "software comparison language detected"

    if has_universal_hints and not SOFTWARE_COMPARISON_HINTS.search(request_text):
        return "universal", detect_mode(request_text, "universal"), "universal planning language detected"

    for mode, pattern in SOFTWARE_PATTERNS:
        if pattern.search(request_text):
            return "software", mode, f"software mode detected: {mode}"

    for mode, pattern in UNIVERSAL_PATTERNS:
        if pattern.search(request_text):
            return "universal", mode, f"universal mode detected: {mode}"

    return None, None, "no decisive planning signal detected"


def build_clarification_prompt(request_text: str) -> str:
    if SOURCE_REFERENCE_HINTS.search(request_text):
        return (
            "The request refers to source material like a transcript, screenshot, or "
            "notes, but that source was not included. Paste it or point me to the file."
        )
    if not request_text.strip():
        return "What do you want me to turn into a plan?"
    return (
        "I can route this to a software plan or a universal plan, but the request "
        "is ambiguous. Is this code work or a non-code plan?"
    )


def should_consider_fanout_research(
    request_text: str,
    kind: Optional[str],
    mode: Optional[str],
) -> bool:
    if kind != "software":
        return False

    if SMALL_CHANGE_HINTS.search(request_text) and not FANOUT_RESEARCH_HINTS.search(request_text):
        return False

    if FANOUT_RESEARCH_HINTS.search(request_text):
        return True

    if mode == "investigation" and SOFTWARE_HINTS.search(request_text):
        return True

    return bool(SOFTWARE_COMPARISON_HINTS.search(request_text) and SOFTWARE_HINTS.search(request_text))


def slugify(request_text: str, fallback: str) -> str:
    words = re.findall(r"[a-z0-9]+", request_text.lower())
    filtered = [word for word in words if word not in STOPWORDS]
    base = filtered[:6] or [fallback]
    slug = "-".join(base).strip("-")
    return slug or fallback


def path_slug(path_text: str, fallback: str) -> str:
    words = re.findall(r"[a-z0-9]+", path_text.lower())
    slug = "-".join(words).strip("-")
    return slug or fallback


def next_target_path(plans_dir: Path, slug: str) -> Path:
    today = date.today().isoformat()
    base = plans_dir / f"{today}-{slug}-plan.md"
    if not base.exists():
        return base

    for index in range(2, 100):
        candidate = plans_dir / f"{today}-{slug}-plan-{index:02d}.md"
        if not candidate.exists():
            return candidate

    return plans_dir / f"{today}-{slug}-plan-overflow.md"


def normalize_recommended_plans_path(raw_path: str) -> Optional[Path]:
    cleaned = raw_path.strip().strip("'\"").rstrip("/")
    if not cleaned or "://" in cleaned or cleaned.startswith(("~", "$")):
        return None

    path = Path(cleaned)
    if path.is_absolute() or ".." in path.parts:
        return None
    if "plans" not in cleaned.lower():
        return None
    return path


def recommended_plans_dir(repo_root: Path) -> Optional[Path]:
    for filename in GUIDANCE_FILES:
        guidance_file = repo_root / filename
        if not guidance_file.is_file():
            continue

        for line in read_text(guidance_file).splitlines():
            lowered = line.lower()
            if "plan" not in lowered:
                continue

            candidates = [match.group(1) for match in BACKTICK_PLAN_PATH_RE.finditer(line)]
            if any(word in lowered for word in ("directory", "dir", "path")):
                candidates.extend(match.group(1) for match in PLAIN_PLAN_PATH_RE.finditer(line))
            for candidate in candidates:
                relative_path = normalize_recommended_plans_path(candidate)
                if relative_path:
                    return repo_root / relative_path

    return None


def xdg_state_home() -> Path:
    state_home = os.environ.get("XDG_STATE_HOME")
    if state_home:
        return Path(state_home).expanduser()
    return Path.home() / ".local" / "state"


def repo_state_slug(repo_root: Path) -> str:
    resolved = str(repo_root.resolve())
    name = path_slug(repo_root.name, "repo")
    digest = hashlib.sha256(resolved.encode("utf-8")).hexdigest()[:8]
    return f"{name}-{digest}"


def default_plans_dir(repo_root: Path) -> Tuple[Path, str]:
    local_plans_dir = repo_root / ".agents" / "plans"
    if local_plans_dir.is_dir():
        return local_plans_dir, "existing-local"

    recommended_dir = recommended_plans_dir(repo_root)
    if recommended_dir:
        return recommended_dir, "repo-guidance"

    return xdg_state_home() / "agent-skills" / "plan" / repo_state_slug(repo_root) / "plans", "xdg-state"


def resolve_plans_dir(plans_dir_arg: Optional[str], repo_root: Path) -> Tuple[Path, str]:
    if plans_dir_arg:
        return resolve_path(plans_dir_arg, repo_root), "explicit"
    return default_plans_dir(repo_root)


def template_path_for(kind: Optional[str], skill_root: Path) -> Optional[str]:
    if kind == "software":
        return str(skill_root / "references" / "plan-template-software.md")
    if kind == "universal":
        return str(skill_root / "references" / "plan-template-universal.md")
    return None


def classify_request(
    request_text: str,
    request_display: str,
    explicit_kind: str,
    repo_root: Path,
    plans_dir: Path,
    plans_dir_source: str,
    skill_root: Path,
    request_file: Optional[Path] = None,
) -> Dict[str, Any]:
    existing_plan = find_existing_plan(request_text, repo_root)
    if existing_plan:
        kind = existing_plan.kind or "software"
        mode = existing_plan.mode or detect_mode(request_text, kind)
        return {
            "request": request_text,
            "request_display": request_display,
            "request_file": str(request_file) if request_file else None,
            "action": "refine",
            "kind": kind,
            "mode": mode,
            "needs_clarification": False,
            "clarification_prompt": None,
            "existing_plan_path": str(existing_plan.path),
            "target_path": str(existing_plan.path),
            "slug": existing_plan.path.stem,
            "plans_dir": str(plans_dir),
            "plans_dir_source": plans_dir_source,
            "contract_path": str(skill_root / "references" / "plan-contract.md"),
            "routing_path": str(skill_root / "references" / "routing.md"),
            "template_path": template_path_for(kind, skill_root),
            "should_consider_external_research": bool(EXTERNAL_RESEARCH_HINTS.search(request_text)),
            "should_consider_fanout_research": should_consider_fanout_research(request_text, kind, mode),
            "explanation": "existing plan path detected",
        }

    kind, mode, explanation = classify_kind(request_text, explicit_kind)
    needs_clarification = kind is None or bool(SOURCE_REFERENCE_HINTS.search(request_text))
    slug = slugify(request_text, "new-plan")
    target_path = next_target_path(plans_dir, slug)

    return {
        "request": request_text,
        "request_display": request_display,
        "request_file": str(request_file) if request_file else None,
        "action": "create",
        "kind": kind,
        "mode": mode,
        "needs_clarification": needs_clarification,
        "clarification_prompt": build_clarification_prompt(request_text) if needs_clarification else None,
        "existing_plan_path": None,
        "target_path": str(target_path),
        "slug": slug,
        "plans_dir": str(plans_dir),
        "plans_dir_source": plans_dir_source,
        "contract_path": str(skill_root / "references" / "plan-contract.md"),
        "routing_path": str(skill_root / "references" / "routing.md"),
        "template_path": template_path_for(kind, skill_root),
        "should_consider_external_research": bool(EXTERNAL_RESEARCH_HINTS.search(request_text)),
        "should_consider_fanout_research": should_consider_fanout_research(request_text, kind, mode),
        "explanation": explanation,
    }


def request_from_args(args: argparse.Namespace, parser: argparse.ArgumentParser) -> Tuple[str, str, Optional[Path]]:
    request_text = args.request or ""
    request_file: Optional[Path] = None

    if args.request_file:
        request_file = resolve_path(args.request_file, Path.cwd())
        if request_text or args.request_parts:
            parser.error("--request-file cannot be combined with --request or positional request text")
        request_text = read_text(request_file).strip()
        return request_text, f"@{request_file}", request_file

    if args.request_parts:
        if request_text:
            parser.error("--request cannot be combined with positional request text")
        request_text = " ".join(args.request_parts).strip()
        return request_text, shlex.join(args.request_parts), None

    return request_text.strip(), request_text.strip(), None


def command_classify(args: argparse.Namespace, parser: argparse.ArgumentParser) -> int:
    repo_root = resolve_path(args.repo_root, Path.cwd())
    plans_dir, plans_dir_source = resolve_plans_dir(args.plans_dir, repo_root)
    skill_root = resolve_path(args.skill_root, Path.cwd())
    request_text, request_display, request_file = request_from_args(args, parser)
    payload = classify_request(
        request_text=request_text,
        request_display=request_display,
        explicit_kind=args.kind,
        repo_root=repo_root,
        plans_dir=plans_dir,
        plans_dir_source=plans_dir_source,
        skill_root=skill_root,
        request_file=request_file,
    )
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0


def render_instructions(classification: Dict[str, Any], skill_root: Path) -> str:
    kind = classification.get("kind")
    mode = classification.get("mode")
    action = classification.get("action")
    needs_clarification = classification.get("needs_clarification")
    contract_path = Path(str(classification.get("contract_path") or skill_root / "references" / "plan-contract.md"))
    routing_path = Path(str(classification.get("routing_path") or skill_root / "references" / "routing.md"))
    template_value = classification.get("template_path")
    template_path = Path(str(template_value)) if template_value else None

    parts = [
        "# Shared Planning Instructions",
        "",
        f"- Route: action={action}, kind={kind}, mode={mode}",
        f"- Target path: {classification.get('target_path')}",
        f"- Plans directory source: {classification.get('plans_dir_source')}",
        f"- Existing plan: {classification.get('existing_plan_path') or 'none'}",
        f"- Consider external research: {str(classification.get('should_consider_external_research')).lower()}",
        f"- Consider context fan-out: {str(classification.get('should_consider_fanout_research')).lower()}",
        "",
    ]

    if needs_clarification:
        parts.extend(
            [
                "The request needs clarification before a plan is drafted.",
                f"Ask exactly this question and stop: {classification.get('clarification_prompt')}",
                "",
            ]
        )
        return "\n".join(parts).rstrip() + "\n"

    parts.extend(
        [
            "Produce a durable plan note, not pseudocode and not an execution log.",
            "Keep repo paths repo-relative. Preserve completed work when refining an existing plan.",
            "",
            "## Plan Contract",
            "",
            read_text(contract_path),
            "",
            "## Routing Rules",
            "",
            read_text(routing_path),
        ]
    )

    if template_path:
        parts.extend(["", "## Selected Template", "", read_text(template_path)])

    return "\n".join(parts).rstrip() + "\n"


def command_render_instructions(args: argparse.Namespace) -> int:
    skill_root = resolve_path(args.skill_root, Path.cwd())
    classification = read_json(args.classification)
    sys.stdout.write(render_instructions(classification, skill_root))
    return 0


def extract_sections(body: str) -> Dict[str, str]:
    sections: Dict[str, List[str]] = {}
    current: Optional[str] = None
    heading_re = re.compile(r"^##\s+(.+?)\s*$")

    for line in body.splitlines():
        match = heading_re.match(line)
        if match:
            current = match.group(1).strip()
            sections.setdefault(current, [])
            continue
        if current is not None:
            sections[current].append(line)

    return {name: "\n".join(lines).strip() for name, lines in sections.items()}


def expected_kind_mode(
    args: argparse.Namespace,
    classification: Optional[Dict[str, Any]],
) -> Tuple[Optional[str], Optional[str]]:
    expected_kind = args.kind
    expected_mode = args.mode
    if classification:
        expected_kind = expected_kind or classification.get("kind")
        expected_mode = expected_mode or classification.get("mode")
    return expected_kind, expected_mode


def validate_checkbox_section(section_name: str, content: str, errors: List[str], warnings: List[str]) -> None:
    checkbox_count = 0
    for raw_line in content.splitlines():
        line = raw_line.rstrip()
        if not line.strip():
            continue
        if line.startswith(("  ", "\t")):
            continue
        if line.startswith("- "):
            if re.match(r"^- \[[ xX]\]\s+\S", line):
                checkbox_count += 1
                continue
            errors.append(f"section '{section_name}' has a non-checkbox task item: {line}")
            continue
        errors.append(f"section '{section_name}' contains non-list task content: {line}")

    if checkbox_count == 0:
        errors.append(f"section '{section_name}' must contain at least one checkbox item")


def validate_plan_text(
    text: str,
    expected_kind: Optional[str] = None,
    expected_mode: Optional[str] = None,
) -> Dict[str, Any]:
    errors: List[str] = []
    warnings: List[str] = []
    frontmatter = parse_frontmatter(text)
    errors.extend(frontmatter.errors)
    values = frontmatter.values

    required_fields = ["title", "kind", "status", "mode", "created", "updated", "repo", "source_inputs"]
    for field in required_fields:
        if field not in values:
            errors.append(f"frontmatter missing required field: {field}")

    kind = values.get("kind")
    mode = values.get("mode")
    status = values.get("status")

    if kind not in VALID_KINDS:
        errors.append(f"frontmatter kind must be one of {sorted(VALID_KINDS)}")
    if expected_kind and kind and kind != expected_kind:
        errors.append(f"frontmatter kind '{kind}' does not match expected kind '{expected_kind}'")

    if mode not in VALID_MODES:
        errors.append(f"frontmatter mode must be one of {sorted(VALID_MODES)}")
    if expected_mode and mode and mode != expected_mode:
        warnings.append(f"frontmatter mode '{mode}' does not match expected mode '{expected_mode}'")

    if status not in VALID_STATUSES:
        errors.append(f"frontmatter status must be one of {sorted(VALID_STATUSES)}")

    for field in ["created", "updated"]:
        value = values.get(field)
        if isinstance(value, str) and not re.match(r"^\d{4}-\d{2}-\d{2}$", value):
            errors.append(f"frontmatter {field} must use YYYY-MM-DD")

    source_inputs = values.get("source_inputs")
    if not isinstance(source_inputs, list) or not source_inputs:
        errors.append("frontmatter source_inputs must be a non-empty list")

    sections = extract_sections(frontmatter.body)
    required_sections = list(SHARED_REQUIRED_SECTIONS)
    if kind == "software":
        required_sections.extend(SOFTWARE_REQUIRED_SECTIONS)
    elif kind == "universal":
        required_sections.extend(UNIVERSAL_MODE_SECTIONS.get(str(mode), []))

    for section in required_sections:
        if section not in sections:
            errors.append(f"missing required section: ## {section}")
        elif not sections[section].strip():
            warnings.append(f"section '## {section}' is present but empty")

    if kind == "software":
        for section in ["Tasks", "Acceptance Criteria"]:
            if section in sections:
                validate_checkbox_section(section, sections[section], errors, warnings)
        for section in SOFTWARE_OPTIONAL_SECTIONS:
            if section not in sections:
                warnings.append(f"optional software section missing: ## {section}")
        if mode == "investigation":
            for section in SOFTWARE_INVESTIGATION_OPTIONAL_SECTIONS:
                if section not in sections:
                    warnings.append(f"optional investigation section missing: ## {section}")

    if kind == "universal":
        for section in ["Acceptance Criteria", "Validation", "Implementation Units"]:
            if section in sections:
                warnings.append(f"universal plan includes software-only section: ## {section}")

    return {
        "ok": not errors,
        "errors": errors,
        "warnings": warnings,
        "kind": kind,
        "mode": mode,
        "section_count": len(sections),
    }


def command_validate(args: argparse.Namespace) -> int:
    plan_file = resolve_path(args.plan_file, Path.cwd())
    classification = read_json(args.classification) if args.classification else None
    expected_kind, expected_mode = expected_kind_mode(args, classification)
    result = validate_plan_text(read_text(plan_file), expected_kind, expected_mode)
    result["plan_file"] = str(plan_file)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["ok"] else 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Portable core for durable plan classification, instructions, and validation.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    classify_parser = subparsers.add_parser("classify", help="Classify a plan request.")
    classify_parser.add_argument("--request", help="Plan request text.")
    classify_parser.add_argument("--request-file", help="File containing the plan request.")
    classify_parser.add_argument(
        "--kind",
        choices=["auto", "software", "universal"],
        default="auto",
        help="Optional explicit kind override.",
    )
    classify_parser.add_argument("--repo-root", default=".", help="Repo root used for path resolution.")
    classify_parser.add_argument(
        "--plans-dir",
        help=(
            "Explicit plan output directory. Defaults to existing local .agents/plans, "
            "then repo guidance, then XDG state."
        ),
    )
    classify_parser.add_argument(
        "--skill-root",
        default=str(skill_root_from_script()),
        help="Root directory containing SKILL.md and references/.",
    )
    classify_parser.add_argument("request_parts", nargs="*", help="Plan request text.")

    render_parser = subparsers.add_parser(
        "render-instructions",
        help="Render reusable planning instructions for an adapter prompt.",
    )
    render_parser.add_argument("--classification", default="-", help="Classification JSON path or '-'.")
    render_parser.add_argument(
        "--skill-root",
        default=str(skill_root_from_script()),
        help="Root directory containing SKILL.md and references/.",
    )

    validate_parser = subparsers.add_parser("validate", help="Validate a durable plan note.")
    validate_parser.add_argument("--plan-file", required=True, help="Plan note to validate.")
    validate_parser.add_argument("--classification", help="Optional classification JSON path.")
    validate_parser.add_argument("--kind", choices=sorted(VALID_KINDS), help="Expected plan kind.")
    validate_parser.add_argument("--mode", choices=sorted(VALID_MODES), help="Expected plan mode.")

    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(list(sys.argv[1:] if argv is None else argv))
    if args.command == "classify":
        return command_classify(args, parser)
    if args.command == "render-instructions":
        return command_render_instructions(args)
    if args.command == "validate":
        return command_validate(args)
    parser.error(f"unknown command: {args.command}")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
