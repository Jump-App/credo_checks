defmodule Jump.CredoChecks.SafeBinaryToTermTest do
  use Credo.Test.Case, async: true

  alias Jump.CredoChecks.SafeBinaryToTerm

  describe "flags missing :safe" do
    test "fully-qualified call with empty options" do
      """
      defmodule MyApp.Decoder do
        def decode(binary) do
          Plug.Crypto.non_executable_binary_to_term(binary, [])
        end
      end
      """
      |> to_source_file()
      |> run_check(SafeBinaryToTerm)
      |> assert_issue(fn issue ->
        assert issue.message =~ ":safe"
        assert issue.trigger == "non_executable_binary_to_term"
      end)
    end

    test "arity-1 call with no options" do
      """
      defmodule MyApp.Decoder do
        def decode(binary) do
          Plug.Crypto.non_executable_binary_to_term(binary)
        end
      end
      """
      |> to_source_file()
      |> run_check(SafeBinaryToTerm)
      |> assert_issue()
    end

    test "aliased module call without :safe" do
      """
      defmodule MyApp.Decoder do
        alias Plug.Crypto

        def decode(value) do
          Crypto.non_executable_binary_to_term(value, [])
        end
      end
      """
      |> to_source_file()
      |> run_check(SafeBinaryToTerm)
      |> assert_issue()
    end

    test "unqualified imported call without :safe" do
      """
      defmodule MyApp.Decoder do
        import Plug.Crypto

        def decode(binary) do
          non_executable_binary_to_term(binary)
        end
      end
      """
      |> to_source_file()
      |> run_check(SafeBinaryToTerm)
      |> assert_issue()
    end

    test "piped arity-1 call" do
      """
      defmodule MyApp.Decoder do
        def decode(string) do
          string
          |> Base.decode64!()
          |> Plug.Crypto.non_executable_binary_to_term()
        end
      end
      """
      |> to_source_file()
      |> run_check(SafeBinaryToTerm)
      |> assert_issue()
    end

    test "options list with other atoms but not :safe" do
      """
      defmodule MyApp.Decoder do
        def decode(binary) do
          Plug.Crypto.non_executable_binary_to_term(binary, [:used])
        end
      end
      """
      |> to_source_file()
      |> run_check(SafeBinaryToTerm)
      |> assert_issue()
    end

    test "options passed as a variable rather than a literal" do
      """
      defmodule MyApp.Decoder do
        def decode(binary, opts) do
          Plug.Crypto.non_executable_binary_to_term(binary, opts)
        end
      end
      """
      |> to_source_file()
      |> run_check(SafeBinaryToTerm)
      |> assert_issue()
    end
  end

  describe "allows :safe" do
    test "fully-qualified call with :safe" do
      """
      defmodule MyApp.Decoder do
        def decode(binary) do
          Plug.Crypto.non_executable_binary_to_term(binary, [:safe])
        end
      end
      """
      |> to_source_file()
      |> run_check(SafeBinaryToTerm)
      |> refute_issues()
    end

    test "aliased call with :safe" do
      """
      defmodule MyApp.Decoder do
        alias Plug.Crypto

        def decode(value) do
          Crypto.non_executable_binary_to_term(value, [:safe])
        end
      end
      """
      |> to_source_file()
      |> run_check(SafeBinaryToTerm)
      |> refute_issues()
    end

    test "unqualified imported call with :safe" do
      """
      defmodule MyApp.Decoder do
        import Plug.Crypto

        def decode(binary) do
          non_executable_binary_to_term(binary, [:safe])
        end
      end
      """
      |> to_source_file()
      |> run_check(SafeBinaryToTerm)
      |> refute_issues()
    end

    test "piped call with :safe" do
      """
      defmodule MyApp.Decoder do
        def decode(string) do
          string
          |> Base.decode64!()
          |> Plug.Crypto.non_executable_binary_to_term([:safe])
        end
      end
      """
      |> to_source_file()
      |> run_check(SafeBinaryToTerm)
      |> refute_issues()
    end

    test ":safe alongside other options" do
      """
      defmodule MyApp.Decoder do
        def decode(binary) do
          Plug.Crypto.non_executable_binary_to_term(binary, [:safe, :used])
        end
      end
      """
      |> to_source_file()
      |> run_check(SafeBinaryToTerm)
      |> refute_issues()
    end
  end

  describe "ignores unrelated code" do
    test "other functions are not flagged" do
      """
      defmodule MyApp.Decoder do
        def decode(binary) do
          :erlang.binary_to_term(binary, [:safe])
          Jason.decode!(binary)
        end
      end
      """
      |> to_source_file()
      |> run_check(SafeBinaryToTerm)
      |> refute_issues()
    end
  end
end
