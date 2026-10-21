"""Chat-time tool: persist one triage decision to the claimdecisions table."""

from datetime import datetime, timezone

from pydantic import BaseModel, Field

from azure_functions_agents import tool

from _storage import decisions_table


class RecordDecisionParams(BaseModel):
    claim_id: str = Field(description="Claim id, for example CLM-2026-0501.")
    policy_number: str = Field(description="Policy number the claim is on.")
    severity: str = Field(description="low, medium or high.")
    route: str = Field(description="auto_approve, adjuster or investigator.")
    rationale: str = Field(description="Two sentences explaining the decision.")
    mode: str = Field(default="tool_loop", description="Which skill produced it: tool_loop or workflow.")


@tool(schema=RecordDecisionParams, description="Record the triage decision for a claim. Every run writes its own row.")
async def record_decision(params: RecordDecisionParams) -> dict:
    now = datetime.now(timezone.utc)
    entity = {
        "PartitionKey": now.strftime("%Y-%m-%d"),
        "RowKey": f"{params.claim_id}|{params.mode}|{now.strftime('%H%M%S%f')}",
        "ClaimId": params.claim_id,
        "PolicyNumber": params.policy_number,
        "Severity": params.severity,
        "Route": params.route,
        "Rationale": params.rationale,
        "Mode": params.mode,
        "RecordedAt": now.isoformat(),
    }
    decisions_table().upsert_entity(entity)
    return {"recorded": True, "claim_id": params.claim_id, "mode": params.mode, "route": params.route}
