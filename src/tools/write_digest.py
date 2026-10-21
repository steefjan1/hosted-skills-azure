"""Chat-time tool: write the daily digest as a Markdown blob."""

from datetime import datetime, timezone

from azure.storage.blob import ContentSettings
from pydantic import BaseModel, Field

from azure_functions_agents import tool

from _storage import digest_container


class WriteDigestParams(BaseModel):
    content: str = Field(description="The Markdown digest.")
    blob_name: str | None = Field(default=None, description="Optional blob name. Defaults to digests/<date>.md.")


@tool(schema=WriteDigestParams, description="Write the Markdown digest to the claim-digests container and return the blob name.")
async def write_digest(params: WriteDigestParams) -> dict:
    name = params.blob_name or f"digests/{datetime.now(timezone.utc).strftime('%Y-%m-%d')}.md"
    blob = digest_container().get_blob_client(name)
    blob.upload_blob(
        params.content.encode("utf-8"),
        overwrite=True,
        content_settings=ContentSettings(content_type="text/markdown; charset=utf-8"),
    )
    return {"blob_name": name, "bytes": len(params.content.encode("utf-8"))}
