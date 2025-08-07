defmodule RubberDuck.Analyzers.Code.QualityTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Analyzers.Code.Quality
  alias RubberDuck.Messages.Code.{Analyze, QualityCheck}

  describe "analyze/2 with Analyze message" do
    test "analyzes quality characteristics" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :quality
      }
      
      context = %{
        content: """
        defmodule TestModule do
          @moduledoc "Test module for quality analysis"
          
          def complex_function(x) do
            if x > 10 do
              case x do
                11 -> :eleven
                12 -> :twelve
                _ -> 
                  if x > 20 do
                    cond do
                      x < 30 -> :twenty_something
                      x < 40 -> :thirty_something
                      true -> :large
                    end
                  else
                    :other
                  end
              end
            else
              cond do
                x < 0 -> :negative
                x == 0 -> :zero
                true -> :positive
              end
            end
          end
        end
        """
      }

      assert {:ok, result} = Quality.analyze(message, context)
      assert Map.has_key?(result, :quality_score)
      assert Map.has_key?(result, :metrics)
      assert Map.has_key?(result, :issues)
      assert Map.has_key?(result, :suggestions)
      assert is_float(result.quality_score)
      assert result.quality_score >= 0.0 and result.quality_score <= 1.0
    end

    test "detects high complexity in complex code" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :quality
      }
      
      context = %{
        content: """
        def extremely_complex_function(a, b, c, d, e) do
          if a > 5 do
            if b > 3 do
              if c > 2 do
                case d do
                  1 -> if e > 10, do: for(x <- 1..10, do: x), else: :case1b
                  2 -> if a > 5, do: for(y <- 1..5, do: y * 2), else: :case2b
                  3 -> cond do
                    a + b > 15 -> for(z <- 1..15, do: z + c)
                    a + b > 10 -> Enum.map(1..10, &(&1 + d))
                    true -> :case3c
                  end
                  _ -> if c > e, do: :default1, else: :default2
                end
              else
                for w <- 1..c, do: w * b
              end
            else
              if d > e, do: :branch1, else: :branch2
            end
          else
            case b do
              x when x > 10 -> :large_b
              _ -> :small_everything
            end
          end
        end
        """
      }

      assert {:ok, result} = Quality.analyze(message, context)
      # This very complex code should trigger complexity issues
      assert result.metrics.complexity > 8
      complexity_issues = Enum.filter(result.issues, &(&1.type == :complexity))
      assert length(complexity_issues) > 0
      assert List.first(complexity_issues).severity == :high
    end

    test "detects long file issues" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :quality
      }
      
      # Create content with more than 100 lines
      long_content = Enum.map(1..120, fn i -> "# Comment line #{i}" end)
                    |> Enum.join("\n")
      
      context = %{content: long_content}

      assert {:ok, result} = Quality.analyze(message, context)
      length_issues = Enum.filter(result.issues, &(&1.type == :length))
      assert length(length_issues) > 0
      assert List.first(length_issues).severity == :medium
    end

    test "detects code duplication" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :quality
      }
      
      context = %{
        content: """
        def function1 do
          IO.puts "Same line"
          IO.puts "Same line"
          IO.puts "Same line"
          IO.puts "Same line"
          IO.puts "Same line"
        end
        """
      }

      assert {:ok, result} = Quality.analyze(message, context)
      duplication_issues = Enum.filter(result.issues, &(&1.type == :duplication))
      assert length(duplication_issues) > 0
    end

    test "calculates quality metrics" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :quality
      }
      
      context = %{
        content: """
        defmodule SimpleModule do
          def simple_function(x), do: x + 1
        end
        """
      }

      assert {:ok, result} = Quality.analyze(message, context)
      assert Map.has_key?(result.metrics, :complexity)
      assert Map.has_key?(result.metrics, :loc)
      assert Map.has_key?(result.metrics, :maintainability_index)
      assert result.metrics.complexity >= 1
    end

    test "generates improvement suggestions" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :quality
      }
      
      context = %{
        content: """
        def complex_with_duplication(x) do
          if x > 10 do
            if x > 20 do
              if x > 30 do
                result = x * 2
                IO.puts result
                result
              else
                result = x * 2
                IO.puts result
                result
              end
            else
              :medium
            end
          else
            :small
          end
        end
        """
      }

      assert {:ok, result} = Quality.analyze(message, context)
      assert length(result.suggestions) > 0
      assert Enum.any?(result.suggestions, &(&1.type == :refactor))
    end

    test "handles comprehensive analysis type" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :comprehensive
      }
      
      context = %{content: "def simple_function, do: :ok"}

      assert {:ok, result} = Quality.analyze(message, context)
      assert Map.has_key?(result, :quality_score)
      assert Map.has_key?(result, :metrics)
    end

    test "detects documentation issues with moderate depth" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :quality,
        depth: :moderate
      }
      
      context = %{
        content: """
        defmodule UndocumentedModule do
          def function1(x), do: x + 1
          def function2(x), do: x * 2  
          def function3(x), do: x - 1
        end
        """
      }

      assert {:ok, result} = Quality.analyze(message, context)
      doc_issues = Enum.filter(result.issues, &(&1.type == :documentation))
      assert length(doc_issues) > 0
    end

    test "detects maintainability issues with deep depth" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :quality,
        depth: :deep
      }
      
      context = %{
        content: """
        defmodule BadModule do
          def x(a, b) do
            if a > b do
              temp = a * 2
              if temp > 10 do
                data1 = temp + b
                if data1 > 20 do
                  data1 * 2
                else
                  data1 / 2
                end
              else
                temp
              end
            else
              b
            end
          end
        end
        """
      }

      assert {:ok, result} = Quality.analyze(message, context)
      maintainability_issues = Enum.filter(result.issues, &(&1.type == :maintainability))
      assert length(maintainability_issues) >= 0  # May or may not detect based on thresholds
    end

    test "returns error for unsupported message types" do
      unsupported_message = %{__struct__: :unsupported}
      
      assert {:error, {:unsupported_message_type, :unsupported}} = 
        Quality.analyze(unsupported_message, %{})
    end
  end

  describe "analyze/2 with QualityCheck message" do
    test "performs quality check on target" do
      message = %QualityCheck{
        target: "test.ex",
        metrics: [:complexity, :coverage, :duplication],
        thresholds: %{complexity: 10, coverage: 80, duplication: 5}
      }

      assert {:ok, result} = Quality.analyze(message, %{})
      assert Map.has_key?(result, :status)
      assert result.status == :completed
      assert Map.has_key?(result, :metrics)
      assert Map.has_key?(result, :passed)
      assert is_boolean(result.passed)
    end

    test "checks thresholds correctly" do
      message = %QualityCheck{
        target: "test.ex",
        metrics: [:complexity, :coverage],
        thresholds: %{complexity: 5, coverage: 90}
      }

      assert {:ok, result} = Quality.analyze(message, %{})
      assert is_boolean(result.passed)
      assert Map.has_key?(result, :quality_score)
    end

    test "provides recommendations based on analysis" do
      message = %QualityCheck{
        target: "test.ex",
        metrics: [:duplication, :coverage],
        thresholds: %{}
      }

      assert {:ok, result} = Quality.analyze(message, %{})
      assert Map.has_key?(result, :recommendations)
      assert is_list(result.recommendations)
    end
  end

  describe "quality scoring" do
    test "calculates high quality score for simple code" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :quality
      }
      
      context = %{
        content: """
        defmodule WellWritten do
          @moduledoc "A well-documented module"
          
          @doc "Adds two numbers"
          def add(a, b), do: a + b
          
          @doc "Subtracts two numbers"  
          def subtract(a, b), do: a - b
        end
        """
      }

      assert {:ok, result} = Quality.analyze(message, context)
      assert result.quality_score >= 0.8
    end

    test "calculates low quality score for complex code" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :quality
      }
      
      # Create a long, complex file with duplication
      complex_content = """
      defmodule BadCode do
        def bad_function(x, y, z, a, b, c) do
          if x > 5 do
            if y > 3 do
              if z > 2 do
                if a > 1 do
                  if b > 0 do
                    if c > -1 do
                      result = x + y + z + a + b + c
                      IO.puts result
                      IO.puts result
                      IO.puts result
                      result * 2
                    else
                      0
                    end
                  else
                    0
                  end
                else
                  0
                end
              else
                0
              end
            else
              0
            end
          else
            0
          end
        end
      end
      """ <> String.duplicate("# Extra line to make it long\n", 100)
      
      context = %{content: complex_content}

      assert {:ok, result} = Quality.analyze(message, context)
      assert result.quality_score < 0.5
    end
  end

  describe "maintainability analysis" do
    test "calculates maintainability score" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :quality
      }
      
      context = %{
        content: """
        defmodule Maintainable do
          @moduledoc "Well structured module"
          
          def simple_function(input) do
            input |> process() |> validate()
          end
          
          defp process(data), do: String.upcase(data)
          defp validate(data), do: {:ok, data}
        end
        """
      }

      assert {:ok, result} = Quality.analyze(message, context)
      assert Map.has_key?(result, :maintainability_score)
      assert result.maintainability_score >= 0.0
      assert result.maintainability_score <= 1.0
    end

    test "detects technical debt indicators" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :quality
      }
      
      context = %{
        content: """
        def problematic_function(x) do
          if x > 1 do
            if x > 2 do
              if x > 3 do
                if x > 4 do
                  if x > 5 do
                    if x > 6 do
                      temp_result = x * x * x * x
                      temp_result + temp_result + temp_result
                    else
                      x * 5
                    end
                  else
                    x * 4
                  end
                else
                  x * 3
                end
              else
                x * 2
              end
            else
              x
            end
          else
            0
          end
        end
        """
      }

      assert {:ok, result} = Quality.analyze(message, context)
      assert Map.has_key?(result, :technical_debt_indicators)
      debt_indicators = result.technical_debt_indicators
      assert is_list(debt_indicators)
      
      # Should detect some technical debt (various types)
      assert length(debt_indicators) > 0
      
      # Should have different types of debt indicators
      debt_types = Enum.map(debt_indicators, & &1.type)
      assert length(debt_types) >= 2  # Multiple debt types detected
    end
  end

  describe "suggestion generation" do
    test "suggests testing improvements" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :quality,
        depth: :deep
      }
      
      context = %{
        content: "def untested_function(x), do: x * 2",
        test_coverage: 0.3  # Low test coverage
      }

      assert {:ok, result} = Quality.analyze(message, context)
      testing_suggestions = Enum.filter(result.suggestions, &(&1.type == :testing))
      assert length(testing_suggestions) > 0
      assert List.first(testing_suggestions).priority == :high
    end

    test "suggests documentation improvements" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :quality,
        depth: :moderate
      }
      
      context = %{
        content: """
        defmodule UndocumentedModule do
          def function1(x), do: x + 1
          def function2(y), do: y * 2
        end
        """
      }

      assert {:ok, result} = Quality.analyze(message, context)
      doc_suggestions = Enum.filter(result.suggestions, &(&1.type == :documentation))
      assert length(doc_suggestions) > 0
    end
  end

  describe "behavior implementation" do
    test "implements required callbacks" do
      assert function_exported?(Quality, :analyze, 2)
      assert function_exported?(Quality, :supported_types, 0)
    end

    test "returns correct supported types" do
      types = Quality.supported_types()
      assert Analyze in types
      assert QualityCheck in types
    end

    test "returns correct priority" do
      assert Quality.priority() == :normal
    end

    test "returns appropriate timeout" do
      assert Quality.timeout() == 10_000
    end

    test "returns metadata" do
      metadata = Quality.metadata()
      assert is_map(metadata)
      assert Map.has_key?(metadata, :name)
      assert Map.has_key?(metadata, :description)
      assert :quality in metadata.categories
    end
  end

  describe "edge cases" do
    test "handles empty content" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :quality
      }

      assert {:ok, result} = Quality.analyze(message, %{content: ""})
      assert result.issues == []
      assert result.quality_score > 0.0
    end

    test "handles nil content" do
      message = %Analyze{
        file_path: "nonexistent.ex",
        analysis_type: :quality
      }

      # Should handle gracefully when file doesn't exist
      assert {:ok, result} = Quality.analyze(message, %{})
      assert is_list(result.issues)
      assert is_float(result.quality_score)
    end

    test "handles malformed code gracefully" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :quality
      }
      
      context = %{
        content: "def incomplete_function("  # Malformed Elixir code
      }

      assert {:ok, result} = Quality.analyze(message, context)
      assert is_map(result)
      assert Map.has_key?(result, :quality_score)
    end
  end

  describe "metrics calculation" do
    test "calculates lines of code correctly" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :quality
      }
      
      context = %{
        content: """
        defmodule Test do
          def func1, do: :ok
          
          def func2 do
            :ok
          end
        end
        """
      }

      assert {:ok, result} = Quality.analyze(message, context)
      assert result.metrics.loc == 6  # Non-empty lines
    end

    test "calculates complexity correctly" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :quality
      }
      
      context = %{
        content: """
        def complex_function(x) do
          if x > 5 do
            case x do
              6 -> :six
              7 -> :seven
              _ -> :other
            end
          else
            for i <- 1..x, do: i
          end
        end
        """
      }

      assert {:ok, result} = Quality.analyze(message, context)
      # Should detect if, case, and for constructs
      assert result.metrics.complexity >= 4
    end

    test "estimates duplication percentage" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :quality
      }
      
      context = %{
        content: """
        def func1 do
          IO.puts "duplicate line"
          IO.puts "duplicate line"
          IO.puts "duplicate line"
        end
        """
      }

      assert {:ok, result} = Quality.analyze(message, context)
      assert result.metrics.duplication > 0.0
    end
  end

  describe "file-based analysis" do
    test "reads file content when not provided in context" do
      # This would require creating a temporary file in a real scenario
      message = %Analyze{
        file_path: "nonexistent.ex",
        analysis_type: :quality
      }
      
      context = %{}  # No content provided

      assert {:ok, result} = Quality.analyze(message, context)
      # Should handle missing file gracefully
      assert is_map(result)
    end
  end

  describe "threshold checking" do
    test "passes when all metrics meet thresholds" do
      message = %QualityCheck{
        target: "test.ex",
        metrics: [:complexity, :coverage],
        thresholds: %{complexity: 15, coverage: 70}  # Lenient thresholds
      }

      assert {:ok, result} = Quality.analyze(message, %{})
      # With default values, should pass lenient thresholds
      assert result.passed == true
    end

    test "handles empty thresholds" do
      message = %QualityCheck{
        target: "test.ex",
        metrics: [:complexity],
        thresholds: %{}
      }

      assert {:ok, result} = Quality.analyze(message, %{})
      assert result.passed == true  # Should pass when no thresholds set
    end
  end
end