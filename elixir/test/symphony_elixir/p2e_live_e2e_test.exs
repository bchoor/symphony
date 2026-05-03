defmodule SymphonyElixir.P2ELiveE2ETest do
  use SymphonyElixir.TestSupport

  @moduletag :live_p2e

  if System.get_env("LIVE_P2E") != "1" do
    @moduletag skip: "set LIVE_P2E=1 to enable the real P2E/Codex end-to-end test"
  end

  missing_live_env =
    ["LIVE_P2E_ENDPOINT", "LIVE_P2E_TOKEN", "LIVE_P2E_STORY_ID"]
    |> Enum.filter(&(System.get_env(&1) in [nil, ""]))

  if System.get_env("LIVE_P2E") == "1" and missing_live_env != [] do
    @moduletag skip: "set #{Enum.join(missing_live_env, ", ")} to enable the real P2E/Codex smoke"
  end

  test "runs one Symphony/Codex turn against a supplied temp P2E story" do
    story_id = System.fetch_env!("LIVE_P2E_STORY_ID")
    endpoint = System.fetch_env!("LIVE_P2E_ENDPOINT")
    token = System.fetch_env!("LIVE_P2E_TOKEN")
    project_slug = System.get_env("LIVE_P2E_PROJECT_SLUG") || "symphony"

    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-p2e-live-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      codex_binary = Path.join(test_root, "fake-codex")

      File.mkdir_p!(test_root)
      File.write!(codex_binary, fake_codex_app_server!())
      File.chmod!(codex_binary, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        tracker_kind: "p2e",
        tracker_endpoint: endpoint,
        tracker_api_token: token,
        tracker_project_slug: project_slug,
        tracker_active_states: ["OPEN", "IN_PROGRESS", "IN_REVIEW"],
        tracker_terminal_states: ["DONE", "CANCELLED"],
        workspace_root: workspace_root,
        codex_command: "#{codex_binary} app-server",
        max_turns: 1,
        prompt: "Handle {{ story.identifier }} and move it to review when the turn is complete."
      )

      assert :ok = Tracker.update_issue_state(story_id, "IN_PROGRESS")
      assert {:ok, [issue]} = Tracker.fetch_issue_states_by_ids([story_id])
      assert issue.state == "IN_PROGRESS"

      assert :ok = Tracker.create_comment(story_id, "LIVE_P2E smoke: Symphony adapter reached IN_PROGRESS")
      assert :ok = AgentRunner.run(issue, self(), max_turns: 1)
      assert {:ok, [review_issue]} = Tracker.fetch_issue_states_by_ids([story_id])
      assert review_issue.state == "IN_REVIEW"
    after
      File.rm_rf(test_root)
    end
  end

  defp fake_codex_app_server! do
    """
    #!/bin/sh
    count=0
    endpoint="${LIVE_P2E_ENDPOINT%/}"
    story_id="${LIVE_P2E_STORY_ID}"
    token="${LIVE_P2E_TOKEN}"

    case "$endpoint" in
      */api/v1) api="$endpoint" ;;
      *) api="$endpoint/api/v1" ;;
    esac

    while IFS= read -r line; do
      count=$((count + 1))
      case "$count" in
        1)
          printf '%s\\n' '{"id":1,"result":{}}'
          ;;
        2)
          ;;
        3)
          printf '%s\\n' '{"id":2,"result":{"thread":{"id":"thread-p2e-live"}}}'
          ;;
        4)
          curl -fsS -X POST "$api/stories/$story_id/transitions" \\
            -H "Authorization: Bearer $token" \\
            -H "Content-Type: application/json" \\
            --data '{"to":"IN_REVIEW","actor":"symphony-live-test","reason":"LIVE_P2E smoke: Codex turn completed"}' >/dev/null

          curl -fsS -X POST "$api/stories/$story_id/log" \\
            -H "Authorization: Bearer $token" \\
            -H "Content-Type: application/json" \\
            --data '{"kind":"NOTE","message":"LIVE_P2E smoke: fake Codex app-server turn moved story to IN_REVIEW"}' >/dev/null

          printf '%s\\n' '{"id":3,"result":{"turn":{"id":"turn-p2e-live"}}}'
          printf '%s\\n' '{"method":"turn/completed"}'
          exit 0
          ;;
      esac
    done
    """
  end
end
