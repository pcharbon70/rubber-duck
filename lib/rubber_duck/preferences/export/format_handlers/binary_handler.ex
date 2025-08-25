defmodule RubberDuck.Preferences.Export.FormatHandlers.BinaryHandler do
  @moduledoc """
  Binary format handler for preference exports.

  Handles encoding and decoding of preference data in efficient binary format
  using Erlang's External Term Format (ETF) with compression and integrity checking.
  """

  # "RDPB" - RubberDuck Preference Binary
  @magic_header <<0x52, 0x44, 0x50, 0x42>>
  @format_version 1

  @doc """
  Format preference data as binary.
  """
  @spec format(data :: map()) :: {:ok, binary()} | {:error, term()}
  def format(data) do
    try do
      # Serialize data using Erlang Term Format
      serialized = :erlang.term_to_binary(data, [:compressed])

      # Add header and version information
      binary_data = build_binary_format(serialized)

      {:ok, binary_data}
    rescue
      error -> {:error, "Binary encoding failed: #{inspect(error)}"}
    end
  end

  @doc """
  Parse binary preference data.
  """
  @spec parse(binary_data :: binary()) :: {:ok, map()} | {:error, term()}
  def parse(binary_data) when is_binary(binary_data) do
    try do
      case validate_binary_header(binary_data) do
        {:ok, payload} ->
          data = :erlang.binary_to_term(payload, [:safe])
          {:ok, data}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      error -> {:error, "Binary parsing failed: #{inspect(error)}"}
    end
  end

  def parse(_), do: {:error, "Input must be binary data"}

  @doc """
  Validate binary structure for preference import.
  """
  @spec validate_structure(data :: map()) :: {:ok, map()} | {:error, [String.t()]}
  def validate_structure(data) do
    # Use same validation as JSON handler since the data structure is the same
    RubberDuck.Preferences.Export.FormatHandlers.JsonHandler.validate_structure(data)
  end

  @doc """
  Get information about a binary export without fully parsing it.
  """
  @spec get_binary_info(binary_data :: binary()) :: {:ok, map()} | {:error, term()}
  def get_binary_info(binary_data) when is_binary(binary_data) do
    try do
      case validate_binary_header(binary_data) do
        {:ok, _payload} ->
          header_info = parse_binary_header(binary_data)
          {:ok, header_info}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      error -> {:error, "Binary info extraction failed: #{inspect(error)}"}
    end
  end

  def get_binary_info(_), do: {:error, "Input must be binary data"}

  ## Private Functions

  defp build_binary_format(serialized_data) do
    # Build binary format with header
    # Header: Magic(4) + Version(1) + Checksum(4) + Size(4) + Data
    checksum = :erlang.crc32(serialized_data)
    size = byte_size(serialized_data)

    @magic_header <>
      <<@format_version::8>> <>
      <<checksum::32>> <>
      <<size::32>> <>
      serialized_data
  end

  defp validate_binary_header(binary_data) do
    case binary_data do
      <<@magic_header, @format_version::8, checksum::32, size::32, payload::binary>> ->
        validate_payload_integrity(payload, size, checksum)

      <<@magic_header, version::8, _rest::binary>> ->
        {:error, "Unsupported binary format version: #{version}"}

      _ ->
        {:error, "Invalid binary format (missing or corrupted header)"}
    end
  end

  defp parse_binary_header(binary_data) do
    case binary_data do
      <<@magic_header, version::8, checksum::32, size::32, _payload::binary>> ->
        %{
          magic_header: @magic_header,
          format_version: version,
          checksum: checksum,
          payload_size: size,
          total_size: byte_size(binary_data)
        }

      _ ->
        %{error: "Invalid binary header"}
    end
  end

  defp validate_payload_integrity(payload, expected_size, expected_checksum) do
    case byte_size(payload) do
      ^expected_size -> validate_checksum(payload, expected_checksum)
      _ -> {:error, "Binary data corruption detected (size mismatch)"}
    end
  end

  defp validate_checksum(payload, expected_checksum) do
    calculated_checksum = :erlang.crc32(payload)
    
    if calculated_checksum == expected_checksum do
      {:ok, payload}
    else
      {:error, "Binary data corruption detected (checksum mismatch)"}
    end
  end
end
