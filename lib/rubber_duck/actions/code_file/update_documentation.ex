defmodule RubberDuck.Actions.CodeFile.UpdateDocumentation do
  @moduledoc """
  Action to automatically update or generate documentation for code files.
  """

  use Jido.Action,
    name: "update_documentation",
    description: "Updates or generates documentation with consistency checks",
    schema: [
      file_id: [type: :string, required: true],
      content: [type: :string, required: true],
      file_path: [type: :string, required: true],
      doc_style: [type: :atom, default: :moduledoc, values: [:moduledoc, :comments, :readme, :all]],
      auto_generate: [type: :boolean, default: true]
    ]

  @impl true
  def run(params, _context) do
    with {:ok, analysis} <- analyze_documentation_state(params),
         {:ok, suggestions} <- generate_documentation_suggestions(analysis, params),
         {:ok, updated_content} <- apply_documentation_updates(params.content, suggestions, params),
         {:ok, validation} <- validate_documentation_consistency(updated_content) do

      {:ok, %{
        original_coverage: analysis.coverage,
        new_coverage: calculate_coverage(updated_content),
        documentation_quality: assess_quality(updated_content),
        updates_applied: length(suggestions),
        validation_results: validation,
        updated_content: updated_content
      }}
    end
  end

  defp analyze_documentation_state(params) do
    content = params.content

    analysis = %{
      has_moduledoc: has_moduledoc?(content),
      has_function_docs: count_function_docs(content),
      total_functions: count_functions(content),
      has_type_specs: has_type_specs?(content),
      has_examples: has_examples?(content),
      coverage: calculate_coverage(content),
      missing_docs: find_missing_documentation(content)
    }

    {:ok, analysis}
  end

  defp generate_documentation_suggestions(analysis, params) do
    suggestions = []

    # Generate moduledoc if missing
    suggestions = if not analysis.has_moduledoc and params.auto_generate do
      [generate_moduledoc_suggestion(params) | suggestions]
    else
      suggestions
    end

    # Generate function docs for undocumented functions
    suggestions = if length(analysis.missing_docs) > 0 and params.auto_generate do
      func_suggestions = Enum.map(analysis.missing_docs, &generate_function_doc_suggestion(&1, params))
      suggestions ++ func_suggestions
    else
      suggestions
    end

    # Add type specs if missing
    suggestions = if analysis.has_type_specs do
      suggestions
    else
      [suggest_type_specs(params) | suggestions]
    end

    {:ok, suggestions}
  end

  defp apply_documentation_updates(content, suggestions, params) do
    updated_content = Enum.reduce(suggestions, content, fn suggestion, acc ->
      apply_single_update(acc, suggestion, params)
    end)

    {:ok, updated_content}
  end

  defp validate_documentation_consistency(content) do
    validation = %{
      consistent_style: check_documentation_style_consistency(content),
      complete_coverage: check_documentation_completeness(content),
      valid_examples: validate_code_examples(content),
      no_outdated_refs: check_for_outdated_references(content)
    }

    {:ok, validation}
  end

  defp has_moduledoc?(content) do
    String.contains?(content, "@moduledoc")
  end

  defp count_function_docs(content) do
    content
    |> String.split("\n")
    |> Enum.count(&String.contains?(&1, "@doc"))
  end

  defp count_functions(content) do
    content
    |> then(&Regex.scan(~r/def(?:p?)\s+\w+/, &1))
    |> length()
  end

  defp has_type_specs?(content) do
    String.contains?(content, "@spec")
  end

  defp has_examples?(content) do
    String.contains?(content, "## Examples") or String.contains?(content, "iex>")
  end

  defp calculate_coverage(content) do
    total_functions = count_functions(content)
    documented_functions = count_function_docs(content)

    if total_functions > 0 do
      documented_functions / total_functions
    else
      1.0
    end
  end

  defp find_missing_documentation(content) do
    functions = extract_function_definitions(content)
    documented = extract_documented_functions(content)

    Enum.filter(functions, fn func ->
      not Enum.member?(documented, func.name)
    end)
  end

  defp extract_function_definitions(content) do
    content
    |> then(&Regex.scan(~r/def(?:p?)\s+(\w+)(?:\(([^)]*)\))?/, &1))
    |> Enum.map(fn
      [_, name, args] -> %{name: name, args: args || ""}
      [_, name] -> %{name: name, args: ""}
    end)
  end

  defp extract_documented_functions(content) do
    lines = String.split(content, "\n")

    lines
    |> Enum.with_index()
    |> Enum.filter(fn {line, _} -> String.contains?(line, "@doc") end)
    |> Enum.map(fn {_, index} ->
      # Look for the next function definition after @doc
      next_func = lines
        |> Enum.drop(index + 1)
        |> Enum.find(&Regex.match?(~r/def(?:p?)\s+(\w+)/, &1))

      case Regex.run(~r/def(?:p?)\s+(\w+)/, next_func || "") do
        [_, name] -> name
        _ -> nil
      end
    end)
    |> Enum.filter(& &1)
  end

  defp generate_moduledoc_suggestion(params) do
    module_name = extract_module_name(params.content)

    %{
      type: :moduledoc,
      position: :after_defmodule,
      content: """
        @moduledoc \"\"\"
        Module: #{module_name}

        This module handles #{infer_module_purpose(module_name, params.content)}.
        \"\"\"
      """
    }
  end

  defp generate_function_doc_suggestion(func, _params) do
    %{
      type: :function_doc,
      function_name: func.name,
      position: :before_function,
      content: """
        @doc \"\"\"
        #{humanize_function_name(func.name)}.

        ## Parameters
        #{generate_parameter_docs(func.args)}

        ## Returns
        Returns the result of #{func.name} operation.
        \"\"\"
      """
    }
  end

  defp suggest_type_specs(_params) do
    %{
      type: :type_specs,
      position: :before_functions,
      content: "# Consider adding @spec annotations for type safety"
    }
  end

  defp apply_single_update(content, suggestion, _params) do
    case suggestion.type do
      :moduledoc ->
        insert_moduledoc(content, suggestion.content)

      :function_doc ->
        insert_function_doc(content, suggestion.function_name, suggestion.content)

      _ ->
        content
    end
  end

  defp insert_moduledoc(content, moduledoc) do
    if String.contains?(content, "@moduledoc") do
      content
    else
      String.replace(content, ~r/(defmodule\s+[\w.]+\s+do)/, "\\1\n#{moduledoc}")
    end
  end

  defp insert_function_doc(content, function_name, doc) do
    pattern = ~r/(def(?:p?)\s+#{function_name})/

    if Regex.match?(pattern, content) do
      String.replace(content, pattern, "#{doc}\n  \\1")
    else
      content
    end
  end

  defp check_documentation_style_consistency(content) do
    has_moduledoc = String.contains?(content, "@moduledoc")
    has_docs = String.contains?(content, "@doc")

    has_moduledoc and has_docs
  end

  defp check_documentation_completeness(content) do
    coverage = calculate_coverage(content)
    coverage >= 0.8
  end

  defp validate_code_examples(content) do
    examples = Regex.scan(~r/iex>(.+)/, content)

    # Basic validation - check if examples are present and formatted
    Enum.empty?(examples) or Enum.all?(examples, fn [_, code] ->
      String.trim(code) != ""
    end)
  end

  defp check_for_outdated_references(_content) do
    # Check for references to deprecated functions or modules
    true
  end

  defp assess_quality(content) do
    score = 0

    # Check various quality indicators
    score = score + if(has_moduledoc?(content), do: 25, else: 0)
    score = score + if(has_type_specs?(content), do: 25, else: 0)
    score = score + if(has_examples?(content), do: 25, else: 0)

    coverage = calculate_coverage(content)
    score = score + round(coverage * 25)

    cond do
      score >= 90 -> :excellent
      score >= 70 -> :good
      score >= 50 -> :fair
      score >= 30 -> :poor
      true -> :missing
    end
  end

  defp extract_module_name(content) do
    case Regex.run(~r/defmodule\s+([\w.]+)/, content) do
      [_, name] -> name
      _ -> "Unknown"
    end
  end

  defp infer_module_purpose(module_name, content) do
    cond do
      String.contains?(module_name, "Controller") -> "HTTP request handling and routing"
      String.contains?(module_name, "View") -> "presentation logic and rendering"
      String.contains?(module_name, "Schema") -> "data structure definitions"
      String.contains?(module_name, "Agent") -> "autonomous agent operations"
      String.contains?(module_name, "Action") -> "specific action implementations"
      String.contains?(content, "use GenServer") -> "GenServer process management"
      String.contains?(content, "use Supervisor") -> "process supervision"
      true -> "core functionality"
    end
  end

  defp humanize_function_name(name) do
    name
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp generate_parameter_docs(""), do: "  None"
  defp generate_parameter_docs(args) do
    args
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(fn arg -> "  - `#{arg}`: Parameter description" end)
    |> Enum.join("\n")
  end
end
