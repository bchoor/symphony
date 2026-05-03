defmodule SymphonyElixir.P2EAdapterTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.P2E.{Adapter, Client}

  defmodule StubP2EHTTP do
    import Plug.Conn

    def init(opts), do: opts

    def call(conn, opts) do
      owner = Keyword.fetch!(opts, :owner)
      send(owner, {:stub_p2e_request, conn.method, conn.request_path, get_req_header(conn, "authorization")})

      case {conn.method, conn.request_path} do
        {"GET", "/api/v1/products/symphony/stories"} ->
          json(conn, %{
            "data" => [%{"storyId" => "T-01-L1", "title" => "Adapter", "status" => "OPEN"}],
            "page" => %{"nextCursor" => nil}
          })

        {"GET", "/api/v1/stories/T-01-L1"} ->
          json(conn, %{
            "story" => %{
              "storyId" => "T-01-L1",
              "title" => "Ship P2E adapter",
              "status" => "OPEN",
              "priority" => "P1",
              "tags" => ["Plugin"],
              "acceptanceCriteria" => [
                %{"id" => "ac-1", "text" => "Adapter fetches P2E stories", "checked" => false, "order" => 1}
              ],
              "createdAt" => "2026-05-01T00:00:00Z",
              "updatedAt" => "2026-05-01T01:00:00Z"
            }
          })

        {"POST", "/api/v1/stories/T-01-L1/log"} ->
          json(conn, %{"entry" => %{"storyId" => "T-01-L1", "kind" => "NOTE"}})

        {"POST", "/api/v1/stories/T-01-L1/transitions"} ->
          json(conn, %{"story" => %{"storyId" => "T-01-L1", "status" => "IN_REVIEW"}})

        _ ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(404, Jason.encode!(%{"error" => "not_found"}))
      end
    end

    defp json(conn, body) do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(body))
    end
  end

  defmodule FakeP2EClient do
    def list_stories(product_slug, opts) do
      send(self(), {:list_stories_called, product_slug, opts})

      {:ok,
       [
         %{
           "storyId" => "T-01-L1",
           "title" => "Ship P2E adapter",
           "status" => "OPEN",
           "priority" => "P1",
           "tags" => ["Plugin", "Elixir"],
           "createdAt" => "2026-05-01T00:00:00Z",
           "updatedAt" => "2026-05-01T01:00:00Z"
         }
       ]}
    end

    def get_story(story_id) do
      send(self(), {:get_story_called, story_id})

      {:ok,
       %{
         "storyId" => story_id,
         "title" => "Ship P2E adapter",
         "status" => "OPEN",
         "priority" => "P1",
         "tags" => ["Plugin", "Elixir"],
         "storyAs" => "PM",
         "storyWant" => "Symphony to work P2E stories",
         "storySoThat" => "the backlog can move autonomously",
         "background" => "Use the REST tracker surface.",
         "filesHint" => ["elixir/lib/symphony_elixir/p2e/adapter.ex"],
         "constraints" => ["Use req"],
         "contextDocs" => ["docs/design-docs/rest-api-v1.md"],
         "nonGoals" => ["webhooks"],
         "sizing" => "XL",
         "release" => "v0.1",
         "githubIssueUrl" => nil,
         "acceptanceCriteria" => [
           %{"id" => "ac-1", "text" => "Adapter fetches P2E stories", "checked" => false, "order" => 1}
         ],
         "capabilities" => [
           %{
             "id" => "cap-1",
             "name" => "p2e_tracker_adapter",
             "action" => "INTRODUCES",
             "description" => "Adapter",
             "isBreaking" => false
           }
         ],
         "createdAt" => "2026-05-01T00:00:00Z",
         "updatedAt" => "2026-05-01T01:00:00Z"
       }}
    end

    def transition(story_id, state_name, reason) do
      send(self(), {:transition_called, story_id, state_name, reason})
      {:ok, %{"story" => %{"storyId" => story_id, "status" => state_name}}}
    end

    def append_log(story_id, kind, message) do
      send(self(), {:append_log_called, story_id, kind, message})
      {:ok, %{"entry" => %{"storyId" => story_id, "kind" => kind, "message" => message}}}
    end
  end

  setup do
    p2e_client_module = Application.get_env(:symphony_elixir, :p2e_client_module)

    on_exit(fn ->
      if is_nil(p2e_client_module) do
        Application.delete_env(:symphony_elixir, :p2e_client_module)
      else
        Application.put_env(:symphony_elixir, :p2e_client_module, p2e_client_module)
      end
    end)

    write_p2e_workflow!()
    Application.put_env(:symphony_elixir, :p2e_client_module, FakeP2EClient)

    :ok
  end

  test "tracker dispatches tracker.kind p2e to the P2E adapter" do
    assert Config.settings!().tracker.kind == "p2e"
    assert Tracker.adapter() == Adapter
  end

  test "p2e adapter implements the tracker callbacks using thick story details" do
    assert {:ok, [issue]} = Adapter.fetch_candidate_issues()
    assert_receive {:list_stories_called, "symphony", [statuses: ["OPEN", "IN_PROGRESS", "IN_REVIEW"]]}
    assert_receive {:get_story_called, "T-01-L1"}

    assert issue.id == "T-01-L1"
    assert issue.identifier == "T-01-L1"
    assert issue.title == "Ship P2E adapter"
    assert issue.state == "OPEN"
    assert issue.priority == 2
    assert issue.labels == ["plugin", "elixir"]
    assert issue.story_as == "PM"
    assert issue.story_want == "Symphony to work P2E stories"

    assert issue.acceptance_criteria == [
             %{id: "ac-1", text: "Adapter fetches P2E stories", checked: false, order: 1}
           ]

    assert {:ok, [%{identifier: "T-01-L1"}]} = Adapter.fetch_issues_by_states(["IN_REVIEW"])
    assert_receive {:list_stories_called, "symphony", [statuses: ["IN_REVIEW"]]}
    assert_receive {:get_story_called, "T-01-L1"}

    assert {:ok, [%{identifier: "T-01-L1"}]} = Adapter.fetch_issue_states_by_ids(["T-01-L1"])
    assert_receive {:get_story_called, "T-01-L1"}

    assert :ok = Adapter.create_comment("T-01-L1", "agent note")
    assert_receive {:append_log_called, "T-01-L1", "NOTE", "agent note"}

    assert :ok = Adapter.update_issue_state("T-01-L1", "IN_REVIEW")
    assert_receive {:transition_called, "T-01-L1", "IN_REVIEW", "symphony tracker state update"}
  end

  test "p2e adapter callbacks work through a stubbed HTTP server without live network" do
    {endpoint, server_pid} = start_stub_p2e_server!()

    on_exit(fn ->
      if Process.alive?(server_pid), do: Process.exit(server_pid, :normal)
    end)

    write_p2e_workflow!(endpoint: endpoint)
    Application.put_env(:symphony_elixir, :p2e_client_module, Client)

    assert {:ok, [issue]} = Adapter.fetch_candidate_issues()
    assert issue.identifier == "T-01-L1"
    assert issue.title == "Ship P2E adapter"
    assert issue.priority == 2

    assert {:ok, [%{identifier: "T-01-L1"}]} = Adapter.fetch_issues_by_states(["OPEN"])
    assert {:ok, [%{identifier: "T-01-L1"}]} = Adapter.fetch_issue_states_by_ids(["T-01-L1"])
    assert :ok = Adapter.create_comment("T-01-L1", "agent note")
    assert :ok = Adapter.update_issue_state("T-01-L1", "IN_REVIEW")

    assert_receive {:stub_p2e_request, "GET", "/api/v1/products/symphony/stories", ["Bearer test-token"]}
    assert_receive {:stub_p2e_request, "GET", "/api/v1/stories/T-01-L1", ["Bearer test-token"]}
    assert_receive {:stub_p2e_request, "POST", "/api/v1/stories/T-01-L1/log", ["Bearer test-token"]}
    assert_receive {:stub_p2e_request, "POST", "/api/v1/stories/T-01-L1/transitions", ["Bearer test-token"]}
  end

  test "p2e client sends REST requests with bearer auth and decodes story payloads" do
    requests = :ets.new(:p2e_client_requests, [:ordered_set, :public])
    owner = self()

    request_fun = fn method, url, opts ->
      send(owner, {:request, method, url, opts})
      :ets.insert(requests, {System.unique_integer([:positive, :monotonic]), {method, url, opts}})

      cond do
        method == :get and String.ends_with?(url, "/api/v1/products/symphony/stories?statuses%5B%5D=OPEN&limit=100") ->
          {:ok,
           %{
             status: 200,
             body: %{
               "data" => [
                 %{"storyId" => "T-01-L1", "title" => "Adapter", "status" => "OPEN"}
               ],
               "page" => %{"nextCursor" => nil}
             }
           }}

        method == :get and String.ends_with?(url, "/api/v1/stories/T-01-L1") ->
          {:ok, %{status: 200, body: %{"story" => %{"storyId" => "T-01-L1", "title" => "Adapter"}}}}

        method == :post and String.ends_with?(url, "/api/v1/stories/T-01-L1/transitions") ->
          {:ok, %{status: 200, body: %{"story" => %{"storyId" => "T-01-L1", "status" => "IN_PROGRESS"}}}}

        method == :post and String.ends_with?(url, "/api/v1/stories/T-01-L1/log") ->
          {:ok, %{status: 200, body: %{"entry" => %{"storyId" => "T-01-L1", "kind" => "NOTE"}}}}
      end
    end

    assert {:ok, [%{"storyId" => "T-01-L1"}]} =
             Client.list_stories("symphony", statuses: ["OPEN"], request_fun: request_fun)

    assert {:ok, %{"storyId" => "T-01-L1"}} = Client.get_story("T-01-L1", request_fun: request_fun)

    assert {:ok, %{"story" => %{"status" => "IN_PROGRESS"}}} =
             Client.transition("T-01-L1", "IN_PROGRESS", "start", request_fun: request_fun)

    assert {:ok, %{"entry" => %{"kind" => "NOTE"}}} =
             Client.append_log("T-01-L1", "NOTE", "started", request_fun: request_fun)

    assert_receive {:request, :get, _url, opts}
    assert {"Authorization", "Bearer test-token"} in opts[:headers]

    transition_request =
      requests
      |> :ets.tab2list()
      |> Enum.map(fn {_key, request} -> request end)
      |> Enum.find(fn {method, url, _opts} ->
        method == :post and String.ends_with?(url, "/api/v1/stories/T-01-L1/transitions")
      end)

    assert {_, _, transition_opts} = transition_request
    assert transition_opts[:json] == %{to: "IN_PROGRESS", actor: "symphony", reason: "start"}
  end

  test "workflow p2e template renders the thick spec through the story alias" do
    workflow_path = Workflow.workflow_file_path()
    Workflow.set_workflow_file_path(Path.expand("WORKFLOW.p2e.md", File.cwd!()))

    on_exit(fn -> Workflow.set_workflow_file_path(workflow_path) end)

    issue = %Issue{
      id: "T-01-L1",
      identifier: "T-01-L1",
      title: "Symphony x P2E MVP adapter",
      state: "OPEN",
      story_as: "PM",
      story_want: "Symphony to pull OPEN P2E stories",
      story_so_that: "I can hand the backlog to Symphony",
      background: "P2E REST is ready.",
      acceptance_criteria: [
        %{id: "ac-1", text: "Client lists stories", checked: false, order: 1},
        %{id: "ac-2", text: "Docs updated", checked: true, order: 2}
      ],
      capabilities: [
        %{
          id: "cap-1",
          name: "p2e_tracker_adapter",
          action: "INTRODUCES",
          description: "REST adapter",
          is_breaking: false
        }
      ],
      constraints: ["Use req"],
      files_hint: ["elixir/lib/symphony_elixir/p2e/client.ex"],
      context_docs: ["docs/design-docs/rest-api-v1.md"],
      non_goals: ["webhooks"],
      sizing: "XL",
      release: "v0.1",
      labels: ["adapter", "elixir"]
    }

    prompt = PromptBuilder.build_prompt(issue)

    assert prompt =~ "Story T-01-L1"
    assert prompt =~ "PM wants Symphony to pull OPEN P2E stories"
    assert prompt =~ "- [ ] Client lists stories"
    assert prompt =~ "- [x] Docs updated"
    assert prompt =~ "p2e_tracker_adapter (INTRODUCES)"
    assert prompt =~ "elixir/lib/symphony_elixir/p2e/client.ex"
    assert prompt =~ "Sizing: XL"
    assert prompt =~ "Release: v0.1"
    assert prompt =~ "Tags: adapter, elixir"
  end

  defp start_stub_p2e_server! do
    {:ok, pid} =
      Bandit.start_link(
        plug: {StubP2EHTTP, owner: self()},
        port: 0,
        ip: {127, 0, 0, 1},
        startup_log: false
      )

    {:ok, {_address, port}} = ThousandIsland.listener_info(pid)
    {"http://127.0.0.1:#{port}", pid}
  end

  defp write_p2e_workflow!(opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, "https://p2e.example.test")

    File.write!(Workflow.workflow_file_path(), """
    ---
    tracker:
      kind: "p2e"
      endpoint: "#{endpoint}"
      api_key: "test-token"
      project_slug: "symphony"
      active_states: ["OPEN", "IN_PROGRESS", "IN_REVIEW"]
      terminal_states: ["DONE", "CANCELLED"]
    ---
    Story {{ story.identifier }}
    """)

    if Process.whereis(SymphonyElixir.WorkflowStore), do: SymphonyElixir.WorkflowStore.force_reload()
    :ok
  end
end
