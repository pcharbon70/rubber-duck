defmodule RubberDuck.Messages.Code.SecurityScan do
  @moduledoc """
  Message for scanning code for security vulnerabilities.

  Replaces the "code.security.scan" signal pattern.
  """

  @enforce_keys [:content, :file_type]
  defstruct [
    :content,
    :file_type,
    :file_path,
    scan_vulnerabilities: true,
    scan_unsafe_operations: true,
    scan_input_validation: true,
    scan_authentication: true,
    opts: %{},
    metadata: %{}
  ]

  @type file_type :: :elixir | :elixir_script | :javascript | :unknown

  @type t :: %__MODULE__{
          content: String.t(),
          file_type: file_type(),
          file_path: String.t() | nil,
          scan_vulnerabilities: boolean(),
          scan_unsafe_operations: boolean(),
          scan_input_validation: boolean(),
          scan_authentication: boolean(),
          opts: map(),
          metadata: map()
        }

  defimpl RubberDuck.Protocol.Message do
    alias RubberDuck.Messages.Code.SecurityScan

    def validate(%SecurityScan{} = msg) do
      with :ok <- validate_content(msg.content),
           :ok <- validate_file_type(msg.file_type) do
        {:ok, msg}
      end
    end

    def route(%SecurityScan{} = msg, context) do
      if Code.ensure_loaded?(RubberDuck.Skills.CodeAnalysisSkill) do
        RubberDuck.Skills.CodeAnalysisSkill.handle_security_scan(msg, context)
      else
        {:error, :handler_not_loaded}
      end
    end

    def to_jido_signal(%SecurityScan{} = msg) do
      data = Map.from_struct(msg)

      %{
        type: "code.security.scan",
        data: data |> Map.delete(:metadata),
        metadata: msg.metadata
      }
    end

    # Security is always high priority
    def priority(_), do: :high
    def timeout(_), do: 30_000
    def encode(msg), do: Jason.encode!(Map.from_struct(msg))

    defp validate_content(content) when is_binary(content) and byte_size(content) > 0, do: :ok
    defp validate_content(_), do: {:error, :invalid_content}

    defp validate_file_type(type) when type in [:elixir, :elixir_script, :javascript, :unknown],
      do: :ok

    defp validate_file_type(_), do: {:error, :invalid_file_type}
  end
end
