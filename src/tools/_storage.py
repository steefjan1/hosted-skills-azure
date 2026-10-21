"""Storage clients for the tools, using the same AzureWebJobsStorage settings as the host.

Locally the host uses `AzureWebJobsStorage=UseDevelopmentStorage=true`. In Azure the
Bicep sets identity-based settings (`AzureWebJobsStorage__tableServiceUri` and friends)
and the user-assigned identity in `AZURE_CLIENT_ID`, so there is no connection string.
"""

from __future__ import annotations

import os

from azure.core.exceptions import ResourceExistsError
from azure.data.tables import TableClient
from azure.storage.blob import ContainerClient

DECISIONS_TABLE = os.environ.get("CLAIMS_TABLE_NAME", "claimdecisions")
DIGEST_CONTAINER = os.environ.get("CLAIMS_DIGEST_CONTAINER", "claim-digests")


def _connection_string() -> str | None:
    value = os.environ.get("AzureWebJobsStorage")
    return value if value else None


def _credential():
    from azure.identity import DefaultAzureCredential

    client_id = os.environ.get("AZURE_CLIENT_ID")
    if client_id:
        return DefaultAzureCredential(managed_identity_client_id=client_id)
    return DefaultAzureCredential()


def decisions_table() -> TableClient:
    conn = _connection_string()
    if conn:
        client = TableClient.from_connection_string(conn, table_name=DECISIONS_TABLE)
    else:
        endpoint = os.environ["AzureWebJobsStorage__tableServiceUri"].rstrip("/")
        client = TableClient(endpoint=endpoint, table_name=DECISIONS_TABLE, credential=_credential())
    try:
        client.create_table()
    except ResourceExistsError:
        pass
    return client


def digest_container() -> ContainerClient:
    conn = _connection_string()
    if conn:
        client = ContainerClient.from_connection_string(conn, container_name=DIGEST_CONTAINER)
    else:
        endpoint = os.environ["AzureWebJobsStorage__blobServiceUri"].rstrip("/")
        client = ContainerClient(account_url=endpoint, container_name=DIGEST_CONTAINER, credential=_credential())
    try:
        client.create_container()
    except ResourceExistsError:
        pass
    return client
