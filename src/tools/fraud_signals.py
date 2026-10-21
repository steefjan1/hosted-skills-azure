"""Chat-time tool: deterministic fraud signals for one claim."""

from typing import Any

from pydantic import BaseModel, Field

from azure_functions_agents import tool

from _claims_data import get_fraud_signals


class FraudSignalsParams(BaseModel):
    claim: dict[str, Any] = Field(
        description="The whole claim object: claim_id, policy_number, coverage, amount, incident_date, reported_date, description."
    )


@tool(schema=FraudSignalsParams, description="Run the deterministic fraud signal checks on a claim and return the signals and their total score.")
async def fraud_signals(params: FraudSignalsParams) -> dict:
    return get_fraud_signals(params.claim)
