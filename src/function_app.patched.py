import durabletask.internal.shared as _durable_shared

from azure_functions_agents import create_function_app


def _strip_path(host_address):
    """Workaround for azure-functions-durable 2.0.0b2 with extension bundle 4.32.

    The host passes rpcBaseUrl as ``http://127.0.0.1:17071/durabletask/``. The SDK strips
    the scheme but not the path, and a gRPC target with a path never connects (Windows:
    getaddrinfo error, Linux: silent timeout), so every start_workflow fails with the
    runtime's generic "failed to start workflow". Keep only scheme, host and port.
    """
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


# The runtime's workflow client is the async one; the sync one is patched for completeness.
_durable_shared.get_grpc_channel = _get_grpc_channel
_durable_shared.get_async_grpc_channel = _get_async_grpc_channel

# The runtime discovers every *.agent.md, agents.config.yaml, mcp.json, tools/ and
# skills/ next to this file and registers one Azure Function per hosted skill.
app = create_function_app()
