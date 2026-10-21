"""Workflow-safe handlers for the dynamic-workflow variant of claim triage.

A file may hold many @workflow_tool handlers. Each takes one dict and returns JSON.
They run later, inside Durable activities, so they must tolerate re-execution. The only
one with a side effect (wf_record_decision) writes one row per run so the measurement
scripts can see every run; a Durable retry would add a second row, which the digest dedupes.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from azure_functions_agents import WorkflowRetryBackoff, WorkflowRetryPolicy, workflow_tool

from _claims_data import get_claim_history, get_fraud_signals, get_policy, score_claim
from _storage import decisions_table


def _require_str(args: dict[str, Any], name: str) -> str:
    value = args.get(name)
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{name} must be a non-empty string")
    return value.strip()


def _require_dict(args: dict[str, Any], name: str) -> dict[str, Any]:
    value = args.get(name)
    if not isinstance(value, dict):
        raise ValueError(f"{name} must be an object")
    return value


@workflow_tool(description="Look up a policy. Args: {policy_number: str}. Returns the policy with coverages and limits.")
def wf_policy_lookup(args: dict[str, Any]) -> dict[str, Any]:
    return get_policy(_require_str(args, "policy_number"))


@workflow_tool(description="List earlier claims on a policy. Args: {policy_number: str}. Returns {claims: [...], count}.")
def wf_claim_history(args: dict[str, Any]) -> dict[str, Any]:
    return get_claim_history(_require_str(args, "policy_number"))


@workflow_tool(description="Run the deterministic fraud signal checks. Args: {claim: <whole claim object>}. Returns {signals: [...], score}.")
def wf_fraud_signals(args: dict[str, Any]) -> dict[str, Any]:
    return get_fraud_signals(_require_dict(args, "claim"))


@workflow_tool(
    description=(
        "Apply the severity rubric. Args: {claim: <claim>, policy: <wf_policy_lookup result>, "
        "history: <wf_claim_history result>, signals: <wf_fraud_signals result>}. "
        "Returns {claim_id, policy_number, severity, route, rationale}."
    )
)
def wf_score_claim(args: dict[str, Any]) -> dict[str, Any]:
    return score_claim(
        _require_dict(args, "claim"),
        _require_dict(args, "policy"),
        _require_dict(args, "history"),
        _require_dict(args, "signals"),
    )


@workflow_tool(
    description=(
        "Record the decision as the terminal step. Args: {decision: <wf_score_claim result>, mode: 'workflow'}. "
        "Every run writes its own row (the measurement scripts need per-run rows)."
    ),
    retry=WorkflowRetryPolicy(
        max_attempts=3,
        backoff=WorkflowRetryBackoff(initial="PT1S", multiplier=2.0, max="PT4S"),
    ),
    timeout="PT30S",
)
def wf_record_decision(args: dict[str, Any]) -> dict[str, Any]:
    decision = _require_dict(args, "decision")
    mode = str(args.get("mode") or "workflow")
    now = datetime.now(timezone.utc)
    entity = {
        "PartitionKey": now.strftime("%Y-%m-%d"),
        "RowKey": f"{decision.get('claim_id')}|{mode}|{now.strftime('%H%M%S%f')}",
        "ClaimId": str(decision.get("claim_id")),
        "PolicyNumber": str(decision.get("policy_number")),
        "Severity": str(decision.get("severity")),
        "Route": str(decision.get("route")),
        "Rationale": str(decision.get("rationale")),
        "Mode": mode,
        "RecordedAt": now.isoformat(),
    }
    decisions_table().upsert_entity(entity)
    return {"recorded": True, "claim_id": entity["ClaimId"], "mode": mode, "route": entity["Route"]}
