---
tracker:
  kind: p2e
  endpoint: "$P2E_ENDPOINT"
  api_key: "$P2E_API_TOKEN"
  client_id: "$P2E_OAUTH_SYMPHONY_CLIENT_ID"
  client_secret: "$P2E_OAUTH_SYMPHONY_CLIENT_SECRET"
  project_slug: "symphony"
  active_states:
    - OPEN
    - IN_PROGRESS
    - IN_REVIEW
  terminal_states:
    - DONE
    - CANCELLED
polling:
  interval_ms: 5000
workspace:
  root: ~/code/symphony-p2e-workspaces
hooks:
  after_create: |
    git clone --depth 1 https://github.com/openai/symphony .
    if command -v mise >/dev/null 2>&1; then
      cd elixir && mise trust && mise exec -- mix deps.get
    fi
  before_remove: |
    cd elixir && mise exec -- mix workspace.before_remove
agent:
  max_concurrent_agents: 10
  max_turns: 20
codex:
  command: codex --config shell_environment_policy.inherit=all --config 'model="gpt-5.5"' --config model_reasoning_effort=xhigh app-server
  approval_policy: never
  thread_sandbox: workspace-write
  turn_sandbox_policy:
    type: workspaceWrite
---

# Story {{ story.identifier }} - {{ story.title }}

## Intent
{{ story.story_as }} wants {{ story.story_want }} so that {{ story.story_so_that }}.
{{ story.background }}

## Metadata
Sizing: {{ story.sizing }}
Release: {{ story.release }}
Tags: {{ story.labels | join: ", " }}
Current status: {{ story.state }}

## Acceptance Criteria
{% for criterion in story.acceptance_criteria %}
- {% if criterion.checked %}[x]{% else %}[ ]{% endif %} {{ criterion.text }}
{% endfor %}

## Capabilities
{% for capability in story.capabilities %}
- {{ capability.name }} ({{ capability.action }}{% if capability.is_breaking %}, breaking{% endif %}): {{ capability.description }}
{% endfor %}

## Constraints
{% for constraint in story.constraints %}
- {{ constraint }}
{% endfor %}

## Files Hint
{% for path in story.files_hint %}
- {{ path }}
{% endfor %}

## Context Docs
{% for path in story.context_docs %}
- {{ path }}
{% endfor %}

## Non-goals
{% for non_goal in story.non_goals %}
- {{ non_goal }}
{% endfor %}

## Verification
Run: `{{ story.verification_cmd }}`

## Operating Rules
1. Work autonomously in the provided repository copy.
2. Use the P2E story log as the feedback channel; do not assume a Comment model.
3. If the story remains `IN_PROGRESS` or `IN_REVIEW` after a turn, Symphony may re-run the agent.
4. Move only through P2E REST transitions; do not implement a server-side state machine in Symphony.
