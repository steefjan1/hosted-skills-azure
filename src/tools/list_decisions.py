"""Chat-time tool: list recorded decisions from the last N hours."""

from datetime import datetime, timedelta, timezone

from pydantic import BaseModel, Field

from azure_functions_agents import tool

from _storage import decisions_table


class ListDecisionsParams(BaseModel):
    hours: int = Field(default=24, ge=1, le=720, description="Look-back window in hours.")


@tool(schema=ListDecisionsParams, description="List triage decisions recorded in the last N hours, newest first.")
async def list_decisions(params: ListDecisionsParams) -> dict:
    since = datetime.now(timezone.utc) - timedelta(hours=params.hours)
    days = sorted({(since + timedelta(days=i)).strftime("%Y-%m-%d") for i in range((params.hours // 24) + 2)})
    rows = []
    table = decisions_table()
    for day in days:
        for entity in table.query_entities(f"PartitionKey eq '{day}'"):
            recorded = entity.get("RecordedAt", "")
            if recorded >= since.isoformat():
                rows.append({
                    "claim_id": entity.get("ClaimId"),
                    "policy_number": entity.get("PolicyNumber"),
                    "severity": entity.get("Severity"),
                    "route": entity.get("Route"),
                    "mode": entity.get("Mode"),
                    "rationale": entity.get("Rationale"),
                    "recorded_at": recorded,
                })
    rows.sort(key=lambda r: r["recorded_at"], reverse=True)
    # One row per claim and mode: the newest run wins. Re-sent claims and Durable retries
    # write extra rows that the digest should not count twice.
    latest = {}
    for r in rows:
        latest.setdefault((r["claim_id"], r["mode"]), r)
    rows = list(latest.values())
    return {"since": since.isoformat(), "count": len(rows), "decisions": rows}
