defmodule SymphonyElixir.Linear.Issue do
  @moduledoc """
  Normalized Linear issue representation used by the orchestrator.
  """

  defstruct [
    :id,
    :identifier,
    :title,
    :description,
    :priority,
    :state,
    :branch_name,
    :url,
    :assignee_id,
    :story_as,
    :story_want,
    :story_so_that,
    :background,
    :spec_file,
    :effort_hint,
    :verification_cmd,
    :github_issue_number,
    blocked_by: [],
    labels: [],
    files_hint: [],
    constraints: [],
    context_docs: [],
    non_goals: [],
    acceptance_criteria: [],
    capabilities: [],
    release: nil,
    sizing: nil,
    assigned_to_worker: true,
    created_at: nil,
    updated_at: nil
  ]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          identifier: String.t() | nil,
          title: String.t() | nil,
          description: String.t() | nil,
          priority: integer() | nil,
          state: String.t() | nil,
          branch_name: String.t() | nil,
          url: String.t() | nil,
          assignee_id: String.t() | nil,
          story_as: String.t() | nil,
          story_want: String.t() | nil,
          story_so_that: String.t() | nil,
          background: String.t() | nil,
          spec_file: String.t() | nil,
          effort_hint: String.t() | nil,
          verification_cmd: String.t() | nil,
          github_issue_number: integer() | nil,
          labels: [String.t()],
          files_hint: [String.t()],
          constraints: [String.t()],
          context_docs: [String.t()],
          non_goals: [String.t()],
          acceptance_criteria: [map()],
          capabilities: [map()],
          release: String.t() | nil,
          sizing: String.t() | nil,
          assigned_to_worker: boolean(),
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @spec label_names(t()) :: [String.t()]
  def label_names(%__MODULE__{labels: labels}) do
    labels
  end
end
