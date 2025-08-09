defmodule RubberDuck.Messages.CodeFile do
  @moduledoc """
  Typed messages for code file operations.
  """

  defmodule FileCreated do
    @moduledoc "Message indicating a code file was created"
    defstruct [:file_id, :file_path, :project_id, :language, :content, :timestamp]
  end

  defmodule FileModified do
    @moduledoc "Message indicating a code file was modified"
    defstruct [:file_id, :file_path, :changes, :previous_content, :new_content, :timestamp]
  end

  defmodule FileDeleted do
    @moduledoc "Message indicating a code file was deleted"
    defstruct [:file_id, :file_path, :project_id, :timestamp]
  end

  defmodule FileInitialized do
    @moduledoc "Message indicating a file has been initialized for tracking"
    defstruct [:file_id, :quality_score, :complexity_score, :timestamp]
  end

  defmodule DependenciesAffected do
    @moduledoc "Message indicating dependencies have been affected by changes"
    defstruct [:file_id, :affected_files, :impact_level, :timestamp]
  end

  defmodule AnalysisComplete do
    @moduledoc "Message indicating file analysis is complete"
    defstruct [:file_id, :results, :issues, :suggestions, :timestamp]
  end

  defmodule AnalyzeFile do
    @moduledoc "Message to trigger file analysis"
    defstruct [:file_id, :file_path, :analysis_types, :deep_scan, metadata: %{}]
  end

  defmodule QualityAssessed do
    @moduledoc "Message indicating quality assessment is complete"
    defstruct [:file_id, :quality_score, :metrics, :timestamp]
  end

  defmodule OptimizationsDetected do
    @moduledoc "Message indicating optimization opportunities were found"
    defstruct [:file_id, :optimizations, :priority, :timestamp]
  end

  defmodule DocumentationUpdated do
    @moduledoc "Message indicating documentation was updated"
    defstruct [:file_id, :coverage, :quality, :timestamp]
  end

  defmodule SecurityIssueFound do
    @moduledoc "Message indicating a security issue was found"
    defstruct [:file_id, :vulnerability, :severity, :timestamp]
  end

  defmodule RefactoringRequired do
    @moduledoc "Message indicating refactoring is needed"
    defstruct [:file_id, :candidates, :complexity, :timestamp]
  end
end