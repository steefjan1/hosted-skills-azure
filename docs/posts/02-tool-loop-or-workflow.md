# Tool loop or dynamic workflow: measuring the same claim two ways in Azure Functions hosted skills

*Draft 2 of 3. Focus keyphrase: dynamic workflows Azure Functions. Diagram: `docs/diagrams/02-tool-loop-vs-workflow.png`. Numbers measured 2026-10-21 in swedencentral, gpt-5.4 at medium reasoning effort, runtime 0.1.0b16, 15 runs per mode.*

The Learn page for dynamic workflows makes a claim I wanted to test. Let the model author one plan of tool calls, run that plan as a Durable Functions orchestration, and intermediate results never enter the model's context. Microsoft points at Anthropic's programmatic tool calling and the roughly tenfold token reduction reported there. That number is for a different platform and a different workload. So I measured mine, and the answer is not what the page suggests.

## Two skills, one claim

`claim_triage.agent.md` and `claim_triage_workflow.agent.md` receive identical claims from two queues. Both read the same `claims-triage` Agent Skill and the same deterministic data.

The first is the ordinary loop. The model calls `policy_lookup`, `claim_history` and `fraud_signals`, applies the rubric from the skill, and calls `record_decision`. Every tool result returns through the model.

The second has `workflows.enabled: true`. That flag gives the model five extra tools, `start_workflow` among them, and an addendum to the system prompt. The instructions ask for one plan: three lookups with no dependencies between them, a `wf_score_claim` task that depends on all three, and `wf_record_decision` at the end. The model writes the DAG, calls `start_workflow`, gets a workflow id back and ends its turn. Durable Functions does the rest. The rubric runs inside `wf_score_claim`, in Python, so the only thing that differs between the two runs is how the tools get called.

## What I measured

`Get-RunMetrics.ps1` pulls three things. Model calls and tokens per run come from Application Insights: the runtime exports an `agent.run` span per invocation and the Agent Framework exports a `chat` span per model call with `gen_ai.usage.input_tokens` and `gen_ai.usage.output_tokens`, joined on operation id. End-to-end seconds run from enqueue time, logged by the send script, to the `RecordedAt` timestamp in the decisions table, so the workflow's orchestration time counts. And whether both modes reached the same route per claim.

Five claims, three rounds, both queues, sends paced twenty seconds apart.

| | Tool loop | Dynamic workflow |
|---|---|---|
| Model calls per claim | 5.5 | 3.6 |
| Tool calls per claim | 7 | 3.7 |
| Input tokens per claim | 14,861 | 17,048 |
| Output tokens per claim | 723 | 876 |
| Enqueue to decision | 27.2 s | 24.3 s |
| Same route, all 15 runs | yes | yes |

The workflow made fewer model calls and spent more tokens. Per call, the loop sent about 2,700 input tokens and the workflow about 4,700.

## Why the tokens went up

Two things that the architecture diagram does not show.

The workflow flag is not free. Every call a workflow-enabled skill makes carries the five management tool schemas, the runtime's `data-driven-workflows` skill and the system addendum that explains when to prefer `start_workflow`. That is roughly two thousand tokens of context before the model has read a single claim.

And the skill still has to learn the domain. In both variants the model's first move was `load_skill` for `claims-triage`, usually followed by reading the rubric file. The loop then calls four tools; the workflow calls one. But the tool results the workflow keeps out of the context are a policy object, a short claims history and a signal list, a few hundred tokens each. There was not much to save.

So the trade is three fewer model round trips against a heavier prompt on each remaining one. In this domain the prompt wins. The orchestration itself, five activities with a fan-out of three, ran in about 400 milliseconds. The remaining 24 seconds is the model writing the plan.

## What the workflow buys that tokens do not show

The orchestration survives a worker restart. The loop variant does not; a restart mid-run means the queue message comes back and the whole conversation starts over. The workflow's terminal task carries a retry policy, three attempts with exponential backoff and a 30-second attempt timeout, declared on the decorator, and the docs are explicit that handlers must tolerate re-execution.

Operators can list, inspect, cancel and terminate workflows from outside the chat. With the Azure Storage backend used here that is the five management tools and the Durable instance tables. With Durable Task Scheduler it is a dashboard.

And the fan-out is real. Three activities started within the same millisecond and finished 28 milliseconds later. The loop did the same three lookups in three model round trips.

## What it took to make the workflow start at all

This is the part the Learn page leaves out, and it cost an evening. Three separate things stopped `start_workflow`, and every one of them reached the model as the same five words, `failed to start workflow`, and reached Application Insights as a successful function.

First, the extension bundle. The runtime's samples ship `host.json` with the standard bundle, `[4.32.0, 5.0.0)`, whose Durable extension 3.8.0 still speaks the legacy HTTP protocol. The Python Durable SDK the runtime pins, 2.0.0b2, speaks gRPC. It needs the preview bundle, `Microsoft.Azure.Functions.ExtensionBundle.Preview` `[4.42.0, 5.0.0)`, which is what the `azure-functions-skills` plugin scaffolds. I copied from the sample and lost an hour.

Second, the gRPC address. The host hands the SDK `http://127.0.0.1:17071/durabletask/`; the SDK strips the scheme but not the path, and a gRPC target with a path never connects. On Windows that is a name-resolution error, on Linux a silent timeout.

Third, the page size. The SDK's instance query defaults to a page size of 2^31-1. Azure Table Storage rejects anything above 1000 with 400 InvalidInput. Azurite does not, so local runs passed and Azure runs failed. The runtime lists instances before every start, so every start failed.

The second and third are wrapped in `function_app.py`, which is no longer the two lines post 1 promised. The real exceptions go to the runtime's system log namespace, which never lands in your `traces` table. The third one was found because the host side of it did: a Durable extension exception in `traces` with the Table Storage error inside it.

## Where this is the wrong answer

A workflow is the wrong tool when the tool results are small. The numbers above are the proof. If your tools return a few hundred tokens, the workflow prompt costs more than the results it saves.

It is the wrong tool when each step needs the user. `start_workflow` returns immediately. The result arrives on a later turn, through a `<workflow-notification>` in the chat UI or a `get_workflow_status` call. A queue-triggered skill has nobody to tell. The decision lands in the table and that is the delivery.

And it is the wrong tool when you need a hand-written, reviewable orchestration. Plans are model-authored by design. There is no template format, and v1 caps at 50 nodes and parallelism 10. If the plan must be the same every time, write a Durable Function.

Where it is the right answer: a plan that scans fifty endpoints or reads a day of logs, where each result is kilobytes and the summary is what the model should see. That is the workload Microsoft's page describes. It is not the workload most line-of-business triage looks like.

## One more thing the loop taught me

The loop skill is where you find out whether your Agent Skill is any good. The model applied the Markdown rubric fifteen times and the code applied it fifteen times, and they agreed on every claim, including the lapsed policy with a prompt injection in its description. That agreement count is a free evaluation of the Markdown, and I would keep the loop variant around for that alone.

*Sources: [Dynamic workflows in Azure Functions hosted skills](https://learn.microsoft.com/en-us/azure/azure-functions/functions-hosted-skills-dynamic-workflows), [runtime workflows doc](https://github.com/Azure/azure-functions-agents-runtime/blob/main/docs/workflows.md), [runtime observability doc](https://github.com/Azure/azure-functions-agents-runtime/blob/main/docs/observability.md), [agent-framework-durable-extension issue 61](https://github.com/microsoft/agent-framework-durable-extension/issues/61) on the preview bundle, [Anthropic programmatic tool calling](https://platform.claude.com/docs/en/agents-and-tools/tool-use/programmatic-tool-calling).*
