# hosted-skills-azure

Companion repo for three Cloud Perspectives posts on **Azure Functions hosted skills**: five
`.agent.md` files that triage insurance claims, answer coverage questions and write a daily
digest, deployed with `azd` to Flex Consumption in swedencentral.

| Post | What the repo shows |
|---|---|
| 1. Three things Microsoft calls a skill | The anatomy: `.agent.md` hosted skills, a `SKILL.md` Agent Skill, `@tool` functions, triggers, built-in endpoints |
| 2. Tool loop or workflow | The same triage done twice: once through the model loop, once as a dynamic workflow on Durable Functions, with tokens, model calls and end-to-end latency measured |
| 3. Let the skill build the skill | Building and checking this app with the `azure-functions-skills` plugin in a coding agent, then reading the `af.*` spans in Application Insights |

Everything is fictional: policies, claims and the fraud signals. The point is the runtime,
not the insurance.

## What is in the app

```text
src/
  function_app.py                  create_function_app() plus two Durable SDK beta workarounds
  agents.config.yaml               app-wide model and timeout
  host.json                        30 minute functionTimeout, Durable task hub, preview bundle 4.42+
  claim_triage.agent.md            queue: claims-in           tool loop baseline
  claim_triage_workflow.agent.md   queue: claims-in-workflow  dynamic workflow (workflows.enabled)
  coverage_question.agent.md       HTTP POST /coverage        input_schema + response_schema
  claims_assistant.agent.md        built-in chat UI, chat API and MCP tool
  daily_claims_digest.agent.md     timer 06:00 UTC            writes a Markdown digest blob
  tools/                           one @tool per file; wf_claim_tools.py holds the @workflow_tool handlers
  skills/claims-triage/            SKILL.md + severity rubric + coverage rules (Markdown only)
  data/                            policies.json, claim_history.json
infra/                             Bicep: Flex Consumption, Foundry project + gpt-5.4, storage, App Insights, RBAC
scripts/                           Windows PowerShell 5.1 scripts for sending claims and measuring runs
samples/claims/                    five claims that land on low, medium and high severity
docs/                              diagrams and the post drafts
```

Each hosted skill becomes one Azure Function. Startup discovery in this app registers
14 functions: the five skills, the four built-in HTTP routes and the MCP trigger of
`claims_assistant`, and the Durable orchestrator and activities that `workflows.enabled`
brings in.

## Prerequisites

- Azure subscription with quota for `gpt-5.4` GlobalStandard in your region
- [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd), Azure CLI with the `application-insights` extension
- Python 3.13 and [Azure Functions Core Tools v4](https://learn.microsoft.com/azure/azure-functions/functions-run-local) for local runs
- Azurite (`npm install -g azurite`) for local runs; no Docker needed

## Deploy

```powershell
azd auth login
azd init -e hosted-skills   # accept the defaults, pick your subscription
azd env set AZURE_LOCATION swedencentral
azd up
```

`azd up` provisions the resource group, a user-assigned identity, a Foundry account and
project with a `gpt-5.4` deployment, a storage account with the two queues, the decisions
table and the digest container, Log Analytics, Application Insights and the Flex
Consumption function app, then deploys `src/`. The person running `azd` gets the same
data-plane roles as the function app, so the scripts and a local `func start` work against
the real resources.

Model, version and capacity are parameters:

```powershell
azd env set FOUNDRY_MODEL gpt-5.4-mini
azd env set FOUNDRY_MODEL_NAME gpt-5.4-mini
azd env set FOUNDRY_MODEL_VERSION 2026-03-17
```

For a model without reasoning support (for example `gpt-4.1`) also clear the two reasoning
settings: `azd env set AZURE_FUNCTIONS_AGENTS_REASONING_EFFORT ""` and the same for
`AZURE_FUNCTIONS_AGENTS_REASONING_SUMMARY`.

## Try it

```powershell
cd scripts

# One claim to both queues. CLM-2026-0502 is a 12-day-old policy claiming a coverage it does not have.
.\Send-Claim.ps1 -ClaimId CLM-2026-0502 -Mode both

# All five claims, three rounds, for the measurement in post 2
.\Send-ClaimBatch.ps1 -Rounds 3

# A few minutes later: model calls, tokens and end-to-end latency per mode
.\Get-RunMetrics.ps1 -Hours 1

# HTTP skill with a validated JSON response
.\Invoke-Coverage.ps1 -PolicyNumber POL-1003 -Question "Is a crown covered and up to what amount?"

# Chat UI (asks for the function key in the browser)
.\Get-FunctionKey.ps1
start "$(azd env get-value AZURE_FUNCTION_URL)/agents/claims_assistant/"

# Fire the timer skill now instead of waiting for 06:00 UTC
.\Invoke-TimerSkill.ps1
```

The MCP endpoint of `claims_assistant` is `/runtime/webhooks/mcp` with the `mcp_extension`
system key (`.\Get-FunctionKey.ps1 -Mcp`).

## Run locally

```powershell
cd src
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
Copy-Item local.settings.json.sample local.settings.json
# Fill FOUNDRY_PROJECT_ENDPOINT from `azd env get-value FOUNDRY_PROJECT_ENDPOINT`, then:
azurite --skipApiVersionCheck      # second terminal
func start
```

The local host uses Azurite for the queues, the table, the digest container, session history
and the Durable task hub. Send claims with `-Local`:

```powershell
..\scripts\Send-Claim.ps1 -ClaimId CLM-2026-0504 -Mode both -Local
..\scripts\Invoke-Coverage.ps1 -PolicyNumber POL-1002 -Question "Is a cracked windscreen covered?" -Local
```

Keep the venv active in the shell that runs `func start`; Core Tools picks the Python on
`PATH` and without the venv it misses `azure-functions-durable` and fails indexing.

## What the measurement compares

`claim_triage` and `claim_triage_workflow` get the same claims. The first calls four tools
one at a time through the model loop and applies the rubric itself. The second asks the model
for one workflow plan (three lookups in parallel, then score, then record) and Durable
Functions runs it; the rubric is applied by the `wf_score_claim` tool. `Get-RunMetrics.ps1`
reports:

- model calls and tokens per run, from the Microsoft Agent Framework `chat` spans joined to
  the runtime's `agent.run` span by operation id in Application Insights;
- end-to-end seconds from enqueue (logged by `Send-Claim.ps1`) to `RecordedAt` in the
  decisions table, so the orchestration time of the workflow variant counts;
- whether both modes reached the same route for each claim.

## Things the docs did not tell me

Found while getting this repo to run on 2026-10-20, runtime 0.1.0b16, Core Tools 4.12.1.

Dynamic workflows:

- **Use the preview extension bundle.** `azure-functions-durable 2.0.0b2` (pulled in by the
  runtime) talks gRPC to the Durable extension. The standard bundle `[4.32.0, 5.0.0)` that the
  runtime samples ship (Durable extension 3.8.0) answers with the legacy HTTP listener, so every
  `start_workflow` fails. `host.json` here uses `Microsoft.Azure.Functions.ExtensionBundle.Preview`
  `[4.42.0, 5.0.0)` (Durable 3.15.2 in Azure), which is what the `azure-functions-skills` plugin
  scaffolds. `function_app.py` carries two small wrappers for the SDK beta on top of that: it
  strips the `/durabletask/` path from the gRPC target the host hands out (on Windows the raw
  value fails name resolution), and it clamps the instance-query page size to 1000, because the
  SDK's default of 2^31-1 is rejected by Azure Table Storage (400 InvalidInput) but not by Azurite.
- **The model never sees why.** All three failures above reached the model as the same tool
  result, `{"error": "failed to start workflow"}`, and reached Application Insights as a
  successful function. The real exception goes to the runtime's system log namespace, which never
  lands in your `traces`. The host-side half of the last one did show up in `traces` as a Durable
  extension exception, which is how it was found.

The app:

- At app level, `system_tools.dynamic_sessions_code_interpreter` must be an object. The
  `false` form in the reference is per-agent front matter only; to have no sandbox app-wide,
  leave the key out.
- Tool discovery picks **one** `@tool` per file (the first descriptor it finds) and auto-wraps
  the first plain public function in a file that has none. Helpers go in `_private.py` modules
  or start with an underscore. A file may hold many `@workflow_tool` handlers.
- Every `tools.exclude` entry logs a "could not verify tool reference" warning at startup in
  0.1.0b16. The filter still applies; the validator just runs before tool discovery.
- `az storage message put` does not base64-encode. The Functions queue trigger decodes base64 by
  default, so a plain JSON body fails with "Message decoding has failed" five times and goes to
  the poison queue without the skill ever running. The runtime's own sample README sends plain
  text; `Send-Claim.ps1` encodes.
- The worker's OpenTelemetry spans (`agent.run`, `chat`, `execute_tool`) carry their own
  operation id and an empty `operation_Name`. Filter `dependencies` by span `name`, not by the
  host's `operation_Name`; `Get-RunMetrics.ps1` joins `agent.run` to `chat` on `operation_Id`.
- The official samples restrict `AZURE_LOCATION` to ten regions in the Americas. That is a
  Bicep `@allowed` list in the samples, not a runtime limit. swedencentral has Flex Consumption
  and `gpt-5.4` GlobalStandard and works.
- A Foundry account rejects concurrent child operations (`RequestConflict`). `foundry.bicep`
  serializes the project, the model deployment and the role assignments with `dependsOn`.

Local development on Windows:

- Core Tools 4.12 has no Python worker for Windows on ARM (`3.13/WINDOWS/Arm64`). Copy the
  `workers\python` tree to a folder you own, duplicate `X64` as `Arm64`, point
  `languageWorkers__python__workerDirectory` at it in `local.settings.json`, and use an x64
  Python 3.13 venv so the worker's grpc binaries load.
- Host logging at `Information` floods the console with blob lease renewals. `host.json` sets
  `default: Warning` with `Function` and `Host.Results` at `Information`.
- `pip` installs the pinned `0.1.0b16` pre-release without flags; `uv pip install` needs
  `--prerelease=allow` because the runtime pins `azure-functions-durable==2.0.0b2`.

## License

MIT. The Bicep in `infra/` started from the `queue-trigger-agent` sample in
[Azure/azure-functions-agents-runtime](https://github.com/Azure/azure-functions-agents-runtime) (MIT).
