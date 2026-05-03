defmodule SymphonyElixir.P2E.Adapter do
  @moduledoc """
  P2E-backed tracker adapter.
  """

  @behaviour SymphonyElixir.Tracker

  alias SymphonyElixir.{Config, Linear.Issue}
  alias SymphonyElixir.P2E.Client

  @state_update_reason "symphony tracker state update"

  @spec fetch_candidate_issues() :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_candidate_issues do
    fetch_issues_by_states(Config.settings!().tracker.active_states)
  end

  @spec fetch_issues_by_states([String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issues_by_states(states) when is_list(states) do
    normalized_states =
      states
      |> Enum.map(&normalize_string/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if normalized_states == [] do
      {:ok, []}
    else
      with {:ok, project_slug} <- project_slug(),
           {:ok, stories} <- client_module().list_stories(project_slug, statuses: normalized_states) do
        hydrate_story_summaries(stories)
      end
    end
  end

  @spec fetch_issue_states_by_ids([String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids) when is_list(issue_ids) do
    issue_ids
    |> Enum.map(&normalize_string/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> hydrate_story_ids()
  end

  @spec create_comment(String.t(), String.t()) :: :ok | {:error, term()}
  def create_comment(issue_id, body) when is_binary(issue_id) and is_binary(body) do
    case client_module().append_log(issue_id, "NOTE", body) do
      {:ok, _entry} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec update_issue_state(String.t(), String.t()) :: :ok | {:error, term()}
  def update_issue_state(issue_id, state_name)
      when is_binary(issue_id) and is_binary(state_name) do
    case client_module().transition(issue_id, state_name, @state_update_reason) do
      {:ok, _story} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp hydrate_story_summaries(stories) do
    stories
    |> Enum.map(&story_id/1)
    |> Enum.reject(&is_nil/1)
    |> hydrate_story_ids()
  end

  defp hydrate_story_ids(story_ids) when is_list(story_ids) do
    Enum.reduce_while(story_ids, {:ok, []}, fn story_id, {:ok, acc} ->
      case client_module().get_story(story_id) do
        {:ok, story} -> {:cont, {:ok, [normalize_story(story) | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, issues} -> {:ok, Enum.reverse(issues)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_story(story) when is_map(story) do
    story_id = story_id(story)

    %Issue{
      id: story_id,
      identifier: story_id,
      title: map_get(story, "title"),
      description: map_get(story, "background"),
      priority: parse_priority(map_get(story, "priority")),
      state: map_get(story, "status"),
      branch_name: nil,
      url: map_get(story, "githubIssueUrl"),
      labels: normalize_labels(map_get(story, "tags")),
      story_as: map_get(story, "storyAs"),
      story_want: map_get(story, "storyWant"),
      story_so_that: map_get(story, "storySoThat"),
      background: map_get(story, "background"),
      spec_file: map_get(story, "specFile"),
      files_hint: normalize_string_list(map_get(story, "filesHint")),
      constraints: normalize_string_list(map_get(story, "constraints")),
      context_docs: normalize_string_list(map_get(story, "contextDocs")),
      non_goals: normalize_string_list(map_get(story, "nonGoals")),
      effort_hint: map_get(story, "effortHint"),
      verification_cmd: map_get(story, "verificationCmd"),
      github_issue_number: map_get(story, "githubIssueNumber"),
      acceptance_criteria: normalize_acceptance_criteria(map_get(story, "acceptanceCriteria")),
      capabilities: normalize_capabilities(map_get(story, "capabilities")),
      release: map_get(story, "release"),
      sizing: map_get(story, "sizing"),
      created_at: parse_datetime(map_get(story, "createdAt")),
      updated_at: parse_datetime(map_get(story, "updatedAt"))
    }
  end

  defp story_id(story) when is_map(story) do
    normalize_string(map_get(story, "storyId"))
  end

  defp story_id(_story), do: nil

  defp normalize_acceptance_criteria(criteria) when is_list(criteria) do
    Enum.map(criteria, fn criterion ->
      %{
        id: map_get(criterion, "id"),
        text: map_get(criterion, "text"),
        checked: map_get(criterion, "checked") == true,
        order: map_get(criterion, "order") || 0
      }
    end)
  end

  defp normalize_acceptance_criteria(_criteria), do: []

  defp normalize_capabilities(capabilities) when is_list(capabilities) do
    Enum.map(capabilities, fn capability ->
      %{
        id: map_get(capability, "id"),
        name: map_get(capability, "name"),
        action: map_get(capability, "action"),
        description: map_get(capability, "description"),
        is_breaking: map_get(capability, "isBreaking") == true
      }
    end)
  end

  defp normalize_capabilities(_capabilities), do: []

  defp normalize_labels(labels) when is_list(labels) do
    labels
    |> Enum.map(&normalize_string/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&String.downcase/1)
  end

  defp normalize_labels(_labels), do: []

  defp normalize_string_list(values) when is_list(values) do
    values
    |> Enum.map(&normalize_string/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_string_list(_values), do: []

  defp normalize_string(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_string(value) when is_atom(value), do: value |> Atom.to_string() |> normalize_string()
  defp normalize_string(value) when is_integer(value), do: value |> Integer.to_string() |> normalize_string()
  defp normalize_string(_value), do: nil

  defp parse_priority("P0"), do: 1
  defp parse_priority("P1"), do: 2
  defp parse_priority("P2"), do: 3
  defp parse_priority("P3"), do: 4
  defp parse_priority(priority) when is_integer(priority), do: priority
  defp parse_priority(_priority), do: nil

  defp parse_datetime(nil), do: nil

  defp parse_datetime(raw) when is_binary(raw) do
    case DateTime.from_iso8601(raw) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp parse_datetime(_raw), do: nil

  defp map_get(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, String.to_atom(key))
  end

  defp project_slug do
    case Config.settings!().tracker.project_slug do
      slug when is_binary(slug) and slug != "" -> {:ok, slug}
      _ -> {:error, :missing_p2e_project_slug}
    end
  end

  defp client_module do
    Application.get_env(:symphony_elixir, :p2e_client_module, Client)
  end
end
