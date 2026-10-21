"""Deterministic claims domain logic shared by the chat-time tools and the workflow tools.

The file name starts with an underscore, so tool discovery skips it. Everything that
a hosted skill can call lives in a sibling file and imports from here.
"""

from __future__ import annotations

import json
from datetime import date, datetime
from pathlib import Path
from typing import Any

_DATA_DIR = Path(__file__).resolve().parent.parent / "data"


def _load(name: str) -> dict[str, Any]:
    with (_DATA_DIR / name).open(encoding="utf-8") as handle:
        return json.load(handle)


def _parse_date(value: Any) -> date | None:
    if not isinstance(value, str):
        return None
    try:
        return datetime.fromisoformat(value).date()
    except ValueError:
        return None


def get_policy(policy_number: str) -> dict[str, Any]:
    """Return the policy or an error object. Never raises for an unknown policy."""
    policies = _load("policies.json")
    policy = policies.get(policy_number.strip().upper())
    if policy is None:
        return {"error": "policy_not_found", "policy_number": policy_number}
    return policy


def get_claim_history(policy_number: str) -> dict[str, Any]:
    """Return earlier claims on the policy, newest first."""
    history = _load("claim_history.json")
    claims = history.get(policy_number.strip().upper())
    if claims is None:
        return {"error": "policy_not_found", "policy_number": policy_number, "claims": []}
    ordered = sorted(claims, key=lambda item: item.get("date", ""), reverse=True)
    return {"policy_number": policy_number, "claims": ordered, "count": len(ordered)}


def get_fraud_signals(claim: dict[str, Any]) -> dict[str, Any]:
    """Apply a small, explainable signal list to one claim.

    The point of this tool is not to be a fraud model. It is deterministic so that the
    tool-loop and workflow variants of the triage skill see the same facts.
    """
    signals: list[dict[str, Any]] = []
    policy_number = str(claim.get("policy_number", ""))
    policy = get_policy(policy_number) if policy_number else {"error": "missing"}
    amount = claim.get("amount")
    incident_date = _parse_date(claim.get("incident_date"))
    reported_date = _parse_date(claim.get("reported_date"))
    start_date = _parse_date(policy.get("start_date")) if "error" not in policy else None

    if "error" in policy:
        signals.append({"code": "unknown_policy", "weight": 3, "detail": "Policy not found"})
    else:
        if policy.get("status") != "active":
            signals.append({"code": "policy_not_active", "weight": 3, "detail": f"Policy status is {policy.get('status')}"})
        if start_date and incident_date and (incident_date - start_date).days < 30:
            signals.append({"code": "new_policy", "weight": 2, "detail": "Incident within 30 days of policy start"})
        coverage = claim.get("coverage")
        if coverage and coverage not in policy.get("coverages", {}):
            signals.append({"code": "coverage_not_on_policy", "weight": 2, "detail": f"No '{coverage}' coverage on policy"})
        limit = policy.get("coverages", {}).get(coverage, {}).get("limit") if coverage else None
        if isinstance(amount, (int, float)) and isinstance(limit, (int, float)) and limit > 0 and amount > limit:
            signals.append({"code": "amount_over_limit", "weight": 1, "detail": f"Amount {amount} exceeds limit {limit}"})

    if incident_date and reported_date and (reported_date - incident_date).days > 30:
        signals.append({"code": "late_report", "weight": 1, "detail": "Reported more than 30 days after the incident"})
    if isinstance(amount, (int, float)) and amount >= 10000:
        signals.append({"code": "high_amount", "weight": 1, "detail": "Amount of 10,000 or more"})

    history = get_claim_history(policy_number) if policy_number else {"claims": []}
    recent = [c for c in history.get("claims", []) if (_parse_date(c.get("date")) or date.min) >= date(2025, 1, 1)]
    if len(recent) >= 2:
        signals.append({"code": "frequent_claimant", "weight": 1, "detail": f"{len(recent)} claims since 2025"})
    if any(c.get("outcome") == "rejected" for c in history.get("claims", [])):
        signals.append({"code": "prior_rejection", "weight": 1, "detail": "An earlier claim on this policy was rejected"})

    score = sum(int(s["weight"]) for s in signals)
    return {"claim_id": claim.get("claim_id"), "signals": signals, "score": score}


def score_claim(claim: dict[str, Any], policy: dict[str, Any], history: dict[str, Any], signals: dict[str, Any]) -> dict[str, Any]:
    """Deterministic version of the severity rubric in skills/claims-triage/severity-rubric.md.

    The tool-loop skill applies this rubric with the model. The workflow skill applies it
    here, so that the only difference between the two runs is how the tools are called.
    """
    score = int(signals.get("score", 0))
    amount = claim.get("amount") if isinstance(claim.get("amount"), (int, float)) else 0
    codes = {s.get("code") for s in signals.get("signals", [])}

    if "error" in policy or "unknown_policy" in codes or "policy_not_active" in codes:
        severity, route = "high", "investigator"
    elif score >= 4:
        severity, route = "high", "investigator"
    elif score >= 2 or amount >= 5000:
        severity, route = "medium", "adjuster"
    else:
        severity, route = "low", "auto_approve"

    reasons = [s["detail"] for s in signals.get("signals", [])][:3]
    rationale = (
        f"Signal score {score} with amount {amount} on a {policy.get('product', 'unknown')} policy. "
        + ("Signals: " + "; ".join(reasons) + "." if reasons else "No fraud signals raised.")
    )
    return {
        "claim_id": claim.get("claim_id"),
        "policy_number": claim.get("policy_number"),
        "severity": severity,
        "route": route,
        "rationale": rationale,
        "signal_score": score,
        "history_count": int(history.get("count", 0)),
    }
