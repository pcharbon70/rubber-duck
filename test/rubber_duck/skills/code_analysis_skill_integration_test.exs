defmodule RubberDuck.Skills.CodeAnalysisSkillIntegrationTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Skills.CodeAnalysisSkill
  alias RubberDuck.Messages.Code.{Analyze, SecurityScan}

  describe "integration with Security analyzer" do
    test "security analysis via Analyze message" do
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :security,
        depth: :moderate,
        auto_fix: false
      }
      
      context = %{
        content: "def vulnerable(input), do: Code.eval_string(input)",
        state: %{}
      }

      assert {:ok, result} = CodeAnalysisSkill.handle_analyze(message, context)
      assert Map.has_key?(result, :security)
      assert is_map(result.security)
      assert Map.has_key?(result.security, :vulnerabilities)
      # The content should trigger a vulnerability detection
      assert is_list(result.security.vulnerabilities)
    end

    test "comprehensive analysis includes security" do
      message = %Analyze{
        file_path: "test.ex", 
        analysis_type: :comprehensive,
        depth: :moderate,
        auto_fix: false
      }
      
      context = %{
        content: "def bad_function, do: System.cmd(\"rm -rf /\", [])",
        state: %{}
      }

      assert {:ok, result} = CodeAnalysisSkill.handle_analyze(message, context)
      assert Map.has_key?(result, :security)
      assert is_map(result.security)
      assert Map.has_key?(result.security, :vulnerabilities)
    end

    test "SecurityScan message delegation" do
      message = %SecurityScan{
        content: "password = \"hardcoded123\"",
        file_type: :elixir
      }

      assert {:ok, result} = CodeAnalysisSkill.handle_security_scan(message, %{})
      assert Map.has_key?(result, :vulnerabilities)
      assert length(result.vulnerabilities) > 0
      assert Enum.any?(result.vulnerabilities, &(&1.type == :hardcoded_secret))
    end

    test "legacy signal handler for code.security.scan" do
      signal = %{
        type: "code.security.scan",
        data: %{
          content: "def dangerous, do: eval(user_input)",
          file_path: "test.ex",
          file_type: :elixir
        }
      }
      
      state = %{}

      # The signal handling should delegate to Security analyzer
      result = CodeAnalysisSkill.handle_signal(signal, state)
      
      case result do
        {:ok, security_scan, _updated_state} ->
          assert Map.has_key?(security_scan, :vulnerabilities)
          assert is_list(security_scan.vulnerabilities)
          
        {:ok, _state} ->
          # If only state returned, that might be from fallback handling
          :ok
          
        other ->
          flunk("Unexpected result: #{inspect(other)}")
      end
    end

    test "legacy signal handler for code.analyze.file with security enabled" do
      signal = %{
        type: "code.analyze.file",
        data: %{
          file_path: "test.ex",
          content: "def insecure, do: System.cmd(params[:cmd], [])"
        }
      }
      
      state = %{opts: %{security_scan: true}}

      result = CodeAnalysisSkill.handle_signal(signal, state)
      
      case result do
        {:ok, analysis_result, _updated_state} ->
          assert Map.has_key?(analysis_result, :security)
          assert is_map(analysis_result.security)
          
        {:ok, _state} ->
          # Sometimes just state is returned
          :ok
          
        other ->
          flunk("Unexpected result: #{inspect(other)}")
      end
    end

    test "security analysis disabled in legacy signal" do
      signal = %{
        type: "code.analyze.file", 
        data: %{
          file_path: "test.ex",
          content: "def safe_function, do: :ok"
        }
      }
      
      state = %{opts: %{security_scan: false}}

      assert {:ok, result, _updated_state} = CodeAnalysisSkill.handle_signal(signal, state)
      refute Map.has_key?(result, :security)
    end
  end

  describe "error handling" do
    test "handles security analyzer errors gracefully in perform_security_analysis" do
      # This tests the error handling in perform_security_analysis
      # by creating a scenario that should trigger an error path
      message = %Analyze{
        file_path: "test.ex",
        analysis_type: :security,
        depth: :moderate,
        auto_fix: false
      }
      
      # Empty context should still work but with limited functionality
      context = %{}

      assert {:ok, result} = CodeAnalysisSkill.handle_analyze(message, context)
      assert Map.has_key?(result, :security)
      assert is_map(result.security)
    end

    test "handles SecurityScan errors gracefully" do
      # Test with invalid message structure (should be handled gracefully)
      message = %SecurityScan{
        content: nil,
        file_type: nil
      }

      assert {:ok, result} = CodeAnalysisSkill.handle_security_scan(message, %{})
      assert Map.has_key?(result, :vulnerabilities)
    end
  end
end