"""Chat-time tool: earlier claims on a policy."""

from pydantic import BaseModel, Field

from azure_functions_agents import tool

from _claims_data import get_claim_history


class ClaimHistoryParams(BaseModel):
    policy_number: str = Field(description="Policy number, for example POL-1001.")


@tool(schema=ClaimHistoryParams, description="List earlier claims on a policy, newest first, with amount and outcome.")
async def claim_history(params: ClaimHistoryParams) -> dict:
    return get_claim_history(params.policy_number)
