"""Chat-time tool: look up one policy. One @tool per file, by design of the discovery rules."""

from pydantic import BaseModel, Field

from azure_functions_agents import tool

from _claims_data import get_policy


class PolicyLookupParams(BaseModel):
    policy_number: str = Field(description="Policy number, for example POL-1001.")


@tool(schema=PolicyLookupParams, description="Look up a policy: holder, product, status, deductible, coverages and limits.")
async def policy_lookup(params: PolicyLookupParams) -> dict:
    return get_policy(params.policy_number)
