defmodule RubberDuck.Messages.Project do
  @moduledoc """
  Typed messages for project management operations.
  """

  defmodule AnalyzeStructure do
    @moduledoc "Message to analyze project structure"
    defstruct [:project_id, :deep_scan, :include_dependencies, metadata: %{}]
  end

  defmodule MonitorHealth do
    @moduledoc "Message to monitor project health"
    defstruct [:project_id, :metrics, :thresholds, metadata: %{}]
  end

  defmodule OptimizeResources do
    @moduledoc "Message to optimize project resources"
    defstruct [:project_id, :optimization_type, :targets, metadata: %{}]
  end

  defmodule UpdateStatus do
    @moduledoc "Message to update project status"
    defstruct [:project_id, :status, :details, :timestamp]
  end

  defmodule ProjectCreated do
    @moduledoc "Message indicating a project was created"
    defstruct [:project_id, :name, :path, :timestamp]
  end

  defmodule ProjectUpdated do
    @moduledoc "Message indicating a project was updated"
    defstruct [:project_id, :changes, :timestamp]
  end

  defmodule ProjectDeleted do
    @moduledoc "Message indicating a project was deleted"
    defstruct [:project_id, :timestamp]
  end

  defmodule QualityDegraded do
    @moduledoc "Message indicating project quality has degraded"
    defstruct [:project_id, :metrics, :violations, :severity, :timestamp]
  end

  defmodule DependencyOutdated do
    @moduledoc "Message indicating dependencies are outdated"
    defstruct [:project_id, :dependencies, :vulnerabilities, :timestamp]
  end

  defmodule RefactoringSuggested do
    @moduledoc "Message indicating refactoring suggestions are available"
    defstruct [:project_id, :suggestions, :priority, :impact, :timestamp]
  end

  defmodule OptimizationCompleted do
    @moduledoc "Message indicating optimization has been completed"
    defstruct [:project_id, :optimization_type, :results, :improvements, :timestamp]
  end

  defmodule DependencyUpdate do
    @moduledoc "Message to trigger dependency updates"
    defstruct [:project_id, :dependencies, :update_strategy, metadata: %{}]
  end

  defmodule ImpactAnalysis do
    @moduledoc "Message to request impact analysis"
    defstruct [:project_id, :change_type, :targets, metadata: %{}]
  end

  defmodule StructureOptimization do
    @moduledoc "Message for structure optimization operations"
    defstruct [:project_id, :optimization_type, :suggestions, metadata: %{}]
  end
end