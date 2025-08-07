defmodule RubberDuck.Analyzers.Code.SecurityTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Analyzers.Code.Security
  alias RubberDuck.Messages.Code.{Analyze, SecurityScan}

  describe "analyze/2 with Analyze message" do
    test "detects code injection vulnerabilities" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :security
      }
      
      context = %{
        content: "def dangerous_function(user_input), do: Code.eval_string(user_input)"
      }

      assert {:ok, result} = Security.analyze(message, context)
      assert length(result.vulnerabilities) > 0
      assert Enum.any?(result.vulnerabilities, &(&1.type == :code_injection))
      assert Enum.any?(result.vulnerabilities, &(&1.severity == :critical))
    end

    test "detects hardcoded secrets" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :security
      }
      
      context = %{
        content: ~s(def get_api_key, do: "secret_key_12345")
      }

      assert {:ok, result} = Security.analyze(message, context)
      assert length(result.vulnerabilities) > 0
      assert Enum.any?(result.vulnerabilities, &(&1.type == :hardcoded_secret))
    end

    test "detects unsafe operations" do
      message = %Analyze{
        file_path: "test.ex", 
        analysis_type: :security
      }
      
      context = %{
        content: "def run_command(cmd), do: System.cmd(cmd, [])"
      }

      assert {:ok, result} = Security.analyze(message, context)
      assert length(result.unsafe_operations) > 0
      assert Enum.any?(result.unsafe_operations, &(&1.operation == "System.cmd"))
    end

    test "detects authentication issues" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :security
      }
      
      context = %{
        content: "skip_before_action :authenticate_user"
      }

      assert {:ok, result} = Security.analyze(message, context)
      assert length(result.authentication_issues) > 0
      assert Enum.any?(result.authentication_issues, &(&1.type == :skipped_auth))
    end

    test "calculates security risk level" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :security
      }
      
      # High risk content
      context = %{
        content: """
        def bad_function(input) do
          Code.eval_string(input)
          System.cmd("rm -rf " <> input, [])
          password = "hardcoded_password_123"
        end
        """
      }

      assert {:ok, result} = Security.analyze(message, context)
      assert result.risk_level == :critical
    end

    test "handles comprehensive analysis type" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :comprehensive
      }
      
      context = %{content: "def safe_function, do: :ok"}

      assert {:ok, result} = Security.analyze(message, context)
      assert Map.has_key?(result, :vulnerabilities)
      assert Map.has_key?(result, :risk_level)
    end

    test "returns error for unsupported message types" do
      unsupported_message = %{__struct__: :unsupported}
      
      assert {:error, {:unsupported_message_type, :unsupported}} = 
        Security.analyze(unsupported_message, %{})
    end
  end

  describe "analyze/2 with SecurityScan message" do
    test "performs comprehensive security scan" do
      message = %SecurityScan{
        content: "def vulnerable(input), do: Code.eval_string(input)",
        file_type: :elixir
      }

      assert {:ok, result} = Security.analyze(message, %{})
      assert Map.has_key?(result, :vulnerabilities)
      assert Map.has_key?(result, :cwe_mappings)
      assert length(result.cwe_mappings) > 0
    end

    test "maps vulnerabilities to CWE categories" do
      message = %SecurityScan{
        content: "System.cmd(user_input, [])",
        file_type: :elixir
      }

      assert {:ok, result} = Security.analyze(message, %{})
      assert "CWE-78: OS Command Injection" in result.cwe_mappings
    end
  end

  describe "input validation checking" do
    test "detects good validation practices" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :security
      }
      
      context = %{
        content: """
        def create_user(params) do
          %User{}
          |> User.changeset(params)
          |> Repo.insert()
        end
        """
      }

      assert {:ok, result} = Security.analyze(message, context)
      assert result.input_validation.validated_inputs > 0
      assert result.input_validation.validation_score > 0.0
    end

    test "detects risky direct parameter usage" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :security
      }
      
      context = %{
        content: """
        def unsafe_query(params) do
          from(u in User, where: u.id == ^params["id"])
          |> Repo.all()
        end
        """
      }

      assert {:ok, result} = Security.analyze(message, context)
      assert :direct_param_usage in result.input_validation.unvalidated_risks
    end
  end

  describe "file type specific vulnerabilities" do
    test "detects Elixir-specific vulnerabilities" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :security
      }
      
      context = %{
        content: """
        def dangerous(params) do
          atom = String.to_atom(params["key"])
          GenServer.call(atom, :get_data)
        end
        """
      }

      assert {:ok, result} = Security.analyze(message, context)
      assert Enum.any?(result.vulnerabilities, &(&1.type == :atom_injection))
      assert Enum.any?(result.unsafe_operations, &(&1.operation == "Dynamic GenServer calls"))
    end
  end

  describe "behavior implementation" do
    test "implements required callbacks" do
      assert function_exported?(Security, :analyze, 2)
      assert function_exported?(Security, :supported_types, 0)
    end

    test "returns correct supported types" do
      types = Security.supported_types()
      assert Analyze in types
      assert SecurityScan in types
    end

    test "returns correct priority" do
      assert Security.priority() == :high
    end

    test "returns appropriate timeout" do
      assert Security.timeout() == 15_000
    end

    test "returns metadata" do
      metadata = Security.metadata()
      assert is_map(metadata)
      assert Map.has_key?(metadata, :name)
      assert Map.has_key?(metadata, :description)
      assert :security in metadata.categories
    end
  end

  describe "edge cases" do
    test "handles empty content" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :security
      }

      assert {:ok, result} = Security.analyze(message, %{content: ""})
      assert result.vulnerabilities == []
      assert result.risk_level == :none
    end

    test "handles nil content" do
      message = %Analyze{
        file_path: "nonexistent.ex",
        analysis_type: :security
      }

      # Should handle gracefully when file doesn't exist
      assert {:ok, result} = Security.analyze(message, %{})
      assert is_list(result.vulnerabilities)
    end

    test "handles non-string content gracefully" do
      message = %SecurityScan{
        content: nil,
        file_type: :elixir
      }

      assert {:ok, result} = Security.analyze(message, %{})
      assert result.vulnerabilities == []
      assert result.unsafe_operations == []
    end
  end
end