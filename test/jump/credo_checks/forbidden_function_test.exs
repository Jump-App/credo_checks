defmodule Jump.CredoChecks.ForbiddenFunctionTest do
  use Credo.Test.Case, async: true

  alias Jump.CredoChecks.ForbiddenFunction

  @erlang_binary_to_term_config [
    functions: [
      {:erlang, :binary_to_term, "Use Plug.Crypto.non_executable_binary_to_term/2 instead."}
    ]
  ]

  describe ":erlang.binary_to_term detection" do
    test "alerts on :erlang.binary_to_term/1" do
      """
      defmodule MyModule do
        def decode(data) do
          :erlang.binary_to_term(data)
        end
      end
      """
      |> to_source_file()
      |> run_check(ForbiddenFunction, @erlang_binary_to_term_config)
      |> assert_issue(fn issue ->
        assert issue.message =~ ":erlang.binary_to_term"
        assert issue.message =~ "Plug.Crypto.non_executable_binary_to_term/2"
      end)
    end

    test "alerts on :erlang.binary_to_term/2" do
      """
      defmodule MyModule do
        def decode(data) do
          :erlang.binary_to_term(data, [:safe])
        end
      end
      """
      |> to_source_file()
      |> run_check(ForbiddenFunction, @erlang_binary_to_term_config)
      |> assert_issue()
    end

    test "allows Plug.Crypto.non_executable_binary_to_term" do
      """
      defmodule MyModule do
        def decode(data) do
          Plug.Crypto.non_executable_binary_to_term(data, [:safe])
        end
      end
      """
      |> to_source_file()
      |> run_check(ForbiddenFunction, @erlang_binary_to_term_config)
      |> refute_issues()
    end

    test "allows other :erlang functions" do
      """
      defmodule MyModule do
        def my_function do
          :erlang.term_to_binary(%{foo: "bar"})
        end
      end
      """
      |> to_source_file()
      |> run_check(ForbiddenFunction, @erlang_binary_to_term_config)
      |> refute_issues()
    end
  end

  describe "Elixir module function detection" do
    test "alerts on forbidden Elixir module function" do
      """
      defmodule MyModule do
        def dangerous do
          SomeModule.dangerous_function(:arg)
        end
      end
      """
      |> to_source_file()
      |> run_check(ForbiddenFunction,
        functions: [
          {SomeModule, :dangerous_function, "This function is dangerous."}
        ]
      )
      |> assert_issue(fn issue ->
        assert issue.message =~ "SomeModule.dangerous_function"
        assert issue.message =~ "This function is dangerous."
      end)
    end

    test "allows non-forbidden functions from the same module" do
      """
      defmodule MyModule do
        def safe do
          SomeModule.safe_function(:arg)
        end
      end
      """
      |> to_source_file()
      |> run_check(ForbiddenFunction,
        functions: [
          {SomeModule, :dangerous_function, "This function is dangerous."}
        ]
      )
      |> refute_issues()
    end
  end

  describe "multiple forbidden functions" do
    test "detects multiple violations" do
      """
      defmodule MyModule do
        def decode(data) do
          :erlang.binary_to_term(data)
        end

        def other do
          SomeModule.dangerous_function(:arg)
        end
      end
      """
      |> to_source_file()
      |> run_check(ForbiddenFunction,
        functions: [
          {:erlang, :binary_to_term, "Use safe alternative."},
          {SomeModule, :dangerous_function, "This is dangerous."}
        ]
      )
      |> assert_issues(fn issues ->
        assert length(issues) == 2

        messages = Enum.map(issues, & &1.message)
        assert Enum.any?(messages, &(&1 =~ ":erlang.binary_to_term"))
        assert Enum.any?(messages, &(&1 =~ "SomeModule.dangerous_function"))
      end)
    end
  end

  describe "unqualified (bare) function call detection" do
    @bare_function_exported_config [
      functions: [
        {:function_exported?, 3, "Use Utils.Module.function_exported?/3 instead."}
      ]
    ]

    test "alerts on bare function_exported?/3 calls" do
      """
      defmodule MyModule do
        def check(mod) do
          function_exported?(mod, :foo, 1)
        end
      end
      """
      |> to_source_file()
      |> run_check(ForbiddenFunction, @bare_function_exported_config)
      |> assert_issue(fn issue ->
        assert issue.message =~ "function_exported?/3"
        assert issue.message =~ "Utils.Module.function_exported?/3"
      end)
    end

    test "does not alert on different arity" do
      """
      defmodule MyModule do
        def check(mod) do
          function_exported?(mod, :foo)
        end
      end
      """
      |> to_source_file()
      |> run_check(ForbiddenFunction, @bare_function_exported_config)
      |> refute_issues()
    end

    test "does not alert on different function name" do
      """
      defmodule MyModule do
        def check(mod) do
          other_function(mod, :foo, 1)
        end
      end
      """
      |> to_source_file()
      |> run_check(ForbiddenFunction, @bare_function_exported_config)
      |> refute_issues()
    end

    test "works alongside qualified function configs" do
      """
      defmodule MyModule do
        def check(mod) do
          function_exported?(mod, :foo, 1)
          :erlang.binary_to_term(<<>>)
        end
      end
      """
      |> to_source_file()
      |> run_check(ForbiddenFunction,
        functions: [
          {:erlang, :binary_to_term, "Use safe alternative."},
          {:function_exported?, 3, "Use Utils.Module.function_exported?/3 instead."}
        ]
      )
      |> assert_issues(fn issues ->
        assert length(issues) == 2
      end)
    end
  end

  describe "edge cases" do
    test "no issues when no functions configured" do
      """
      defmodule MyModule do
        def decode(data) do
          :erlang.binary_to_term(data)
        end
      end
      """
      |> to_source_file()
      |> run_check(ForbiddenFunction, functions: [])
      |> refute_issues()
    end

    test "handles piped calls" do
      """
      defmodule MyModule do
        def decode(data) do
          data
          |> Base.decode64!()
          |> :erlang.binary_to_term()
        end
      end
      """
      |> to_source_file()
      |> run_check(ForbiddenFunction, @erlang_binary_to_term_config)
      |> assert_issue()
    end

    test "handles nested module calls" do
      """
      defmodule MyModule do
        def call do
          Some.Nested.Module.forbidden_func()
        end
      end
      """
      |> to_source_file()
      |> run_check(ForbiddenFunction,
        functions: [
          {Some.Nested.Module, :forbidden_func, "Don't use this."}
        ]
      )
      |> assert_issue(fn issue ->
        assert issue.message =~ "Some.Nested.Module.forbidden_func"
      end)
    end
  end
end
