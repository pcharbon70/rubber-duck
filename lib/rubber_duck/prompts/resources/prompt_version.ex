defmodule RubberDuck.Prompts.Resources.PromptVersion do
  @moduledoc """
  Version tracking resource for comprehensive prompt history management.
  
  Stores complete version history with content snapshots, metadata,
  and diff generation capabilities for audit trails and rollback support.
  """

  use Ash.Resource,
    domain: RubberDuck.Prompts.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "prompt_versions"
    repo RubberDuck.Repo
  end

  attributes do
    uuid_primary_key :id
    
    attribute :version_number, :integer, allow_nil?: false
    attribute :content_snapshot, :string, allow_nil?: false
    attribute :change_summary, :string
    attribute :diff_data, :map, default: %{}
    attribute :created_by_id, :uuid, allow_nil?: false
    attribute :metadata, :map, default: %{}
    attribute :content_hash, :string
    attribute :size_bytes, :integer
    attribute :change_type, :atom, constraints: [one_of: [:create, :update, :approve, :archive, :restore]]
    
    timestamps()
  end

  relationships do
    belongs_to :prompt, RubberDuck.Prompts.Resources.Prompt, allow_nil?: false
  end

  actions do
    defaults [:create, :read]

    read :list_for_prompt do
      argument :prompt_id, :uuid, allow_nil?: false
      filter expr(prompt_id == ^arg(:prompt_id))
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :system) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type(:create) do
      authorize_if actor_attribute_equals(:role, :system)
    end
  end

  validations do
    validate present([:prompt_id, :version_number, :content_snapshot, :created_by_id])
    validate compare(:version_number, greater_than: 0)
  end

  identities do
    identity :unique_version_per_prompt, [:prompt_id, :version_number]
  end
end