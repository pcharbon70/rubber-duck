defmodule RubberDuck.Test.EntityFactory do
  @moduledoc """
  Factory module for creating test entities using proper Ash Resource structs.
  
  This module replaces the old map-based entity patterns in tests with
  proper struct-based factories that align with the actual Ash Resource
  definitions.
  """

  alias RubberDuck.Accounts.User
  alias RubberDuck.Projects.{Project, CodeFile}
  alias RubberDuck.AI.AnalysisResult

  @doc """
  Creates a test user entity with proper struct.
  """
  def build_user(attrs \\ %{}) do
    defaults = %{
      id: generate_id(),
      username: "testuser#{:rand.uniform(10000)}",
      hashed_password: "$2b$12$test.hash"
    }

    struct(User, Map.merge(defaults, attrs))
  end

  @doc """
  Creates a test project entity with proper struct.
  """
  def build_project(attrs \\ %{}) do
    defaults = %{
      id: generate_id(),
      name: "Test Project #{:rand.uniform(100)}",
      description: "A test project",
      language: "elixir",
      status: :active,
      owner_id: generate_id(),
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }

    struct(Project, Map.merge(defaults, attrs))
  end

  @doc """
  Creates a test code file entity with proper struct.
  """
  def build_code_file(attrs \\ %{}) do
    defaults = %{
      id: generate_id(),
      file_path: "/test/file.ex",
      content: "defmodule Test do\nend",
      language: "elixir",
      status: :active,
      project_id: generate_id(),
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }

    struct(CodeFile, Map.merge(defaults, attrs))
  end

  @doc """
  Creates a test analysis result entity with proper struct.
  """
  def build_analysis_result(attrs \\ %{}) do
    defaults = %{
      id: generate_id(),
      analysis_type: :general,
      summary: "Test analysis",
      details: %{},
      score: Decimal.new("75.0"),
      suggestions: ["Improve test coverage"],
      status: :completed,
      project_id: generate_id(),
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }

    struct(AnalysisResult, Map.merge(defaults, attrs))
  end

  @doc """
  Creates a legacy-style entity map for backward compatibility.
  This function is deprecated and should be replaced with proper struct factories.
  """
  @deprecated "Use build_user/1, build_project/1, build_code_file/1, or build_analysis_result/1 instead"
  def build_entity(type, attrs \\ %{})

  def build_entity(:user, attrs) do
    user = build_user(attrs)
    # Convert to map for legacy compatibility
    Map.from_struct(user)
    |> Map.put(:type, :user)
  end

  def build_entity(:project, attrs) do
    project = build_project(attrs)
    Map.from_struct(project)
    |> Map.put(:type, :project)
  end

  def build_entity(:code_file, attrs) do
    code_file = build_code_file(attrs)
    Map.from_struct(code_file)
    |> Map.put(:type, :code_file)
  end

  def build_entity(:analysis_result, attrs) do
    analysis_result = build_analysis_result(attrs)
    Map.from_struct(analysis_result)
    |> Map.put(:type, :analysis_result)
  end

  # Helper functions

  defp generate_id do
    Ecto.UUID.generate()
  end
end