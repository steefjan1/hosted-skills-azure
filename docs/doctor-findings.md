# azure-functions-doctor findings for hosted-skills-azure

Run on 2026-10-21 by following the `azure-functions-doctor` skill from
[Azure/azure-functions-skills](https://github.com/Azure/azure-functions-skills) as a coding
agent would: `references/routing.md` first, then `source-only-checks.md`,
`ai-semantic-checks.md`, the Python section of `language-checks.md`,
`supply-chain-checks.md` and `iac-azure-resource-checks.md`. Project files only, no project
code executed, no Azure CLI runtime metadata (so `RT-003` uses the skill's fallback table).

Project: Python 3.13, v2 programming model, hosted skills runtime 0.1.0b16. Triggers: 2 queue,
1 HTTP, 1 timer, built-in HTTP and MCP endpoints, Durable orchestrator and activities
(registered by the runtime). IaC: Bicep via azd.

Summary: 0 fail, 9 warn, 3 info. Most important: at-least-once delivery with no retry
strategy and no poison-queue plan on the two queue skills (`DP-008`, `EH-003`, `EH-005`).

| ID | Severity | Status | Title | Location | Evidence | Fix |
|---|---|---|---|---|---|---|
| DP-008 | medium | warn | Queue triggers have no explicit retry strategy | `src/claim_triage.agent.md:5`, `src/claim_triage_workflow.agent.md:5` | Both `queue_trigger` skills rely on the host default of 5 dequeues with immediate retry; a throttled model (429) burns all five in seconds, which the 2026-10-20 batch showed | Add `extensions.queues.maxDequeueCount` and `visibilityTimeout` in `host.json`, or a fixed-delay retry policy, so a model throttle does not poison the message |
| EH-003 | medium | warn | No poison-queue handling | `src/host.json` | Messages land in `claims-in-poison` and `claims-in-workflow-poison` and nothing reads them | Add a hosted skill or function on the poison queues that records a `needs_human` decision, or an alert on poison queue depth |
| EH-005 | medium | warn | Side effect before completion, not idempotent | `src/tools/record_decision.py:35`, `src/tools/wf_claim_tools.py` (`wf_record_decision`) | Every run writes a new row keyed by timestamp. A host retry after a transient failure records the claim twice | Deliberate for the measurement scripts; for production key the row on `claim_id|mode` again and upsert, as the first version did |
| CQ-001 / PY-004 | low | warn | Storage client created per invocation | `src/tools/_storage.py:35-44, 48-58` | `decisions_table()` and `digest_container()` build a new client and call `create_table()` / `create_container()` on every tool call | Cache the clients at module level and create the table and container once |
| PY-002 / CQ-006 | low | warn | Blocking SDK calls inside async tools | `src/tools/record_decision.py:35`, `src/tools/list_decisions.py:23`, `src/tools/write_digest.py:22` | `async def` tools call the synchronous `azure.data.tables` and `azure.storage.blob` clients | Use the `aio` clients, or make the tools plain `def` (the runtime runs them in a thread) |
| RT-004 | low | warn | Extension bundle is the preview bundle | `src/host.json:24` | `Microsoft.Azure.Functions.ExtensionBundle.Preview` `[4.42.0, 5.0.0)`; the checklist says to recommend the standard bundle `[4.*, 5.0.0)` | Keep it. The checklist is wrong for this project: dynamic workflows need the preview bundle, because the standard one carries Durable extension 3.8.0 and the Python Durable SDK 2.0 needs the gRPC listener. The plugin's own `azure-functions-hosted-skills` reference prescribes the preview bundle. The two skills disagree |
| SC-004 | low | warn | `httpsOnly` not declared | `infra/app/api.bicep:73` | The AVM `web/site` module is used without `httpsOnly`; the module's default is true, but the template does not say so | Declare `httpsOnly: true` |
| SC-008 | low | warn | `minTlsVersion` not declared on the function app | `infra/app/api.bicep:73` | Storage sets `TLS1_2`; the site does not declare it | Add `minTlsVersion: '1.2'` to `siteConfig` |
| SC-006 | low | warn | FTP state not declared | `infra/app/api.bicep:73` | No `ftpsState` on the site | Add `ftpsState: 'Disabled'` |
| PY-010 | info | info | Compiled dependencies | `src/requirements.txt` (transitive) | `pydantic_core`, `cryptography`, `grpcio` arrive through the runtime | Flex Consumption builds remotely (`ENABLE_MULTIPLATFORM_BUILD` is set), so wheels match the Linux worker. Local venvs on Windows on ARM need x64 Python for the same reason |
| AS-006 | info | info | Local observability setting empty | `src/local.settings.json.sample:14` | `APPLICATIONINSIGHTS_CONNECTION_STRING` is blank for local runs | Intended; the Bicep sets it in Azure. The runtime logs a warning locally and continues |
| SC-009 | info | info | Queue payload validated in prose, not schema | `src/claim_triage.agent.md:30` | The skill tells the model to stop on a missing `claim_id` or `policy_number`; nothing enforces it before the model runs | Acceptable for a demo; `input_schema` exists for HTTP skills only. A validating tool, or a schema on the queue message, would be the production answer |

Checks that passed, by id: CF-001, CF-002, CF-003, AS-001, AS-002 (identity-based
`AzureWebJobsStorage__*` with grouped keys), AS-003, AS-007, AS-008 (task hub named),
DP-002, DP-003, DP-004, DP-005, DP-006, PY-001, PY-003, PY-007, PY-009, SC-001 (no secrets;
the sample settings file holds placeholders), SC-002 (HTTP skill and chat endpoints use
function keys), SC-005 (`local.settings.json` in `.gitignore` and `.funcignore`), PF-006,
PF-008, ST-008 (Flex deployment storage with user-assigned identity), PF-005, SC-003 (no CORS
wildcard). `tracked-secret-files`: the Azurite development key appears nowhere in the repo.

Supply chain, Python: `azurefunctions-agents-runtime[monitor]==0.1.0b16` is pinned;
`azure-data-tables>=12.5,<13` is bounded. The checklist's threat model names the `durabletask`
PyPI compromise as its worked example, and `durabletask` is a transitive dependency here, so
the exact pin on the runtime matters more than usual. For comparison, the official
`ai-hosted-skills-python` template at v1.0.2 ships `azurefunctions-agents-runtime[monitor]`
with no version at all.

## What doctor would say about the template the plugin scaffolds from

The same checklists against `Azure-Samples/functions-daily-blog-hosted-skills-azd` v1.0.2:

| ID | Status | Finding |
|---|---|---|
| RT-004 | pass | Standard bundle `[4.*, 5.0.0)`, which the checklist recommends and which breaks dynamic workflows |
| unpinned-prod-deps (Python analogue) | warn | `azurefunctions-agents-runtime[monitor]` unpinned; every scaffold gets whatever beta is current |
| DP-008 | warn | Timer skill inherits `timeout: 900`; the hosted-skills skill's own default for background agents is 1800 |
| EH-003 | n/a | No queue triggers |

The plugin's `azure-functions-hosted-skills` reference (`project-files.md`) tells the agent to
use the preview bundle `[4.42.0, 5.0.0)` because the Connector Extension lives there. Nothing
in the plugin says dynamic workflows need it too. Whether a scaffolded app ends up on the right
bundle depends on whether the agent reads that reference after copying the template.
