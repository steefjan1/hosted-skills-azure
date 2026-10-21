"""Hosted skills app. The runtime discovers every *.agent.md, agents.config.yaml, mcp.json,
tools/ and skills/ next to this file and registers one Azure Function per hosted skill.

The two wrappers below are workarounds for azure-functions-durable 2.0.0b2 (pulled in by
azurefunctions-agents-runtime 0.1.0b16) when dynamic workflows run on the Azure Storage
Durable backend. Both are no-ops once the SDK fixes them. See README, "Things the docs did
not tell me".
"""

import dataclasses

import durabletask.client as _durable_client
import durabletask.internal.shared as _durable_shared

from azure_functions_agents import create_function_app


# 1. The host's rpcBaseUrl carries a path (http://127.0.0.1:17071/durabletask/). The SDK
#    strips only the scheme, and a gRPC target with a path never connects. Keep host:port.
def _strip_path(host_address):
    if not host_address:
        return host_address
    scheme, sep, rest = host_address.partition("://")
    if sep:
        return scheme + sep + rest.split("/", 1)[0]
    return host_address.split("/", 1)[0]


_original_get_grpc_channel = _durable_shared.get_grpc_channel
_original_get_async_grpc_channel = _durable_shared.get_async_grpc_channel


def _get_grpc_channel(host_address=None, *args, **kwargs):
    return _original_get_grpc_channel(_strip_path(host_address), *args, **kwargs)


def _get_async_grpc_channel(host_address=None, *args, **kwargs):
    return _original_get_async_grpc_channel(_strip_path(host_address), *args, **kwargs)


_durable_shared.get_grpc_channel = _get_grpc_channel
_durable_shared.get_async_grpc_channel = _get_async_grpc_channel


# 2. OrchestrationQuery.max_instance_count defaults to 2^31-1. The Durable extension passes it
#    to Azure Table Storage as the page size, and Table Storage rejects $top above 1000 with
#    400 InvalidInput (Azurite does not). The runtime's start_workflow lists instances through
#    get_status_all(), so every workflow start failed in Azure. Paging continues through the
#    continuation token, so clamping loses nothing.
_AZURE_TABLE_MAX_PAGE = 1000
_original_build_query_instances_req = _durable_client.build_query_instances_req


def _build_query_instances_req(orchestration_query, continuation_token=None, *args, **kwargs):
    count = getattr(orchestration_query, "max_instance_count", None)
    if count is not None and count > _AZURE_TABLE_MAX_PAGE:
        orchestration_query = dataclasses.replace(
            orchestration_query, max_instance_count=_AZURE_TABLE_MAX_PAGE
        )
    return _original_build_query_instances_req(orchestration_query, continuation_token, *args, **kwargs)


_durable_client.build_query_instances_req = _build_query_instances_req

app = create_function_app()
