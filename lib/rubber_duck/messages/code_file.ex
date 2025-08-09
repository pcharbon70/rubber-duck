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

  # Protocol implementations for CodeFile messages
  alias RubberDuck.Protocol.Message

  defimpl Message, for: FileCreated do
    def validate(msg), do: {:ok, msg}
    def route(msg, _context), do: {:ok, msg}
    def to_jido_signal(msg), do: %{type: "code_file.created", data: Map.from_struct(msg), metadata: %{}}
    def priority(_), do: :normal
    def timeout(_), do: 5_000
    def encode(msg), do: Jason.encode!(Map.from_struct(msg))
  end

  defimpl Message, for: FileModified do
    def validate(msg), do: {:ok, msg}
    def route(msg, _context), do: {:ok, msg}
    def to_jido_signal(msg), do: %{type: "code_file.modified", data: Map.from_struct(msg), metadata: %{}}
    def priority(_), do: :normal
    def timeout(_), do: 5_000
    def encode(msg), do: Jason.encode!(Map.from_struct(msg))
  end

  defimpl Message, for: FileDeleted do
    def validate(msg), do: {:ok, msg}
    def route(msg, _context), do: {:ok, msg}
    def to_jido_signal(msg), do: %{type: "code_file.deleted", data: Map.from_struct(msg), metadata: %{}}
    def priority(_), do: :high
    def timeout(_), do: 5_000
    def encode(msg), do: Jason.encode!(Map.from_struct(msg))
  end

  defimpl Message, for: AnalyzeFile do
    def validate(msg), do: {:ok, msg}
    def route(msg, _context), do: {:ok, msg}
    def to_jido_signal(msg), do: %{type: "code_file.analyze", data: Map.from_struct(msg), metadata: %{}}
    def priority(_), do: :normal
    def timeout(_), do: 10_000
    def encode(msg), do: Jason.encode!(Map.from_struct(msg))
  end

  defimpl Message, for: AnalysisComplete do
    def validate(msg), do: {:ok, msg}
    def route(msg, _context), do: {:ok, msg}
    def to_jido_signal(msg), do: %{type: "code_file.analysis_complete", data: Map.from_struct(msg), metadata: %{}}
    def priority(_), do: :low
    def timeout(_), do: 5_000
    def encode(msg), do: Jason.encode!(Map.from_struct(msg))
  end

  defimpl Message, for: DependenciesAffected do
    def validate(msg), do: {:ok, msg}
    def route(msg, _context), do: {:ok, msg}
    def to_jido_signal(msg), do: %{type: "code_file.dependencies_affected", data: Map.from_struct(msg), metadata: %{}}
    def priority(_), do: :high
    def timeout(_), do: 5_000
    def encode(msg), do: Jason.encode!(Map.from_struct(msg))
  end

  defimpl Message, for: QualityAssessed do
    def validate(msg), do: {:ok, msg}
    def route(msg, _context), do: {:ok, msg}
    def to_jido_signal(msg), do: %{type: "code_file.quality_assessed", data: Map.from_struct(msg), metadata: %{}}
    def priority(_), do: :low
    def timeout(_), do: 5_000
    def encode(msg), do: Jason.encode!(Map.from_struct(msg))
  end

  defimpl Message, for: OptimizationsDetected do
    def validate(msg), do: {:ok, msg}
    def route(msg, _context), do: {:ok, msg}
    def to_jido_signal(msg), do: %{type: "code_file.optimizations_detected", data: Map.from_struct(msg), metadata: %{}}
    def priority(_), do: :normal
    def timeout(_), do: 5_000
    def encode(msg), do: Jason.encode!(Map.from_struct(msg))
  end

  defimpl Message, for: SecurityIssueFound do
    def validate(msg), do: {:ok, msg}
    def route(msg, _context), do: {:ok, msg}
    def to_jido_signal(msg), do: %{type: "code_file.security_issue_found", data: Map.from_struct(msg), metadata: %{}}
    def priority(_), do: :critical
    def timeout(_), do: 5_000
    def encode(msg), do: Jason.encode!(Map.from_struct(msg))
  end

  defimpl Message, for: RefactoringRequired do
    def validate(msg), do: {:ok, msg}
    def route(msg, _context), do: {:ok, msg}
    def to_jido_signal(msg), do: %{type: "code_file.refactoring_required", data: Map.from_struct(msg), metadata: %{}}
    def priority(_), do: :low
    def timeout(_), do: 5_000
    def encode(msg), do: Jason.encode!(Map.from_struct(msg))
  end

  defimpl Message, for: DocumentationUpdated do
    def validate(msg), do: {:ok, msg}
    def route(msg, _context), do: {:ok, msg}
    def to_jido_signal(msg), do: %{type: "code_file.documentation_updated", data: Map.from_struct(msg), metadata: %{}}
    def priority(_), do: :low
    def timeout(_), do: 5_000
    def encode(msg), do: Jason.encode!(Map.from_struct(msg))
  end

  defimpl Message, for: FileInitialized do
    def validate(msg), do: {:ok, msg}
    def route(msg, _context), do: {:ok, msg}
    def to_jido_signal(msg), do: %{type: "code_file.initialized", data: Map.from_struct(msg), metadata: %{}}
    def priority(_), do: :normal
    def timeout(_), do: 5_000
    def encode(msg), do: Jason.encode!(Map.from_struct(msg))
  end
end