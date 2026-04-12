defmodule Jump.CredoChecks.TopLevelAliasImportRequireTest do
  use Credo.Test.Case, async: true

  alias Jump.CredoChecks.TopLevelAliasImportRequire

  describe "import" do
    test "allows import at module level" do
      """
      defmodule Foo do
        import Ecto.Query

        def bar(baz) do
          from(u in User)
        end
      end
      """
      |> to_source_file()
      |> run_check(TopLevelAliasImportRequire)
      |> refute_issues()
    end

    test "alerts on import inside function" do
      """
      defmodule Foo do
        def bar(baz) do
          import Ecto.Query
          from(u in User)
        end
      end
      """
      |> to_source_file()
      |> run_check(TopLevelAliasImportRequire)
      |> assert_issue()
    end

    test "alerts on import inside private function" do
      """
      defmodule Foo do
        defp bar(baz) do
          import Ecto.Query
          from(u in User)
        end
      end
      """
      |> to_source_file()
      |> run_check(TopLevelAliasImportRequire)
      |> assert_issue()
    end

    test "alerts on import inside describe block" do
      """
      defmodule FooTest do
        use ExUnit.Case

        describe "bar" do
          import Hammox

          test "does something" do
            assert true
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(TopLevelAliasImportRequire)
      |> assert_issue()
    end

    test "alerts on import inside test block" do
      """
      defmodule FooTest do
        use ExUnit.Case

        test "does something" do
          import Hammox
          assert true
        end
      end
      """
      |> to_source_file()
      |> run_check(TopLevelAliasImportRequire)
      |> assert_issue()
    end

    test "alerts on import inside setup block" do
      """
      defmodule FooTest do
        use ExUnit.Case

        setup do
          import Hammox
          :ok
        end
      end
      """
      |> to_source_file()
      |> run_check(TopLevelAliasImportRequire)
      |> assert_issue()
    end
  end

  describe "alias" do
    test "allows alias at module level" do
      """
      defmodule Foo do
        alias Jump.Users.Schema

        def bar(baz) do
          %Schema{}
        end
      end
      """
      |> to_source_file()
      |> run_check(TopLevelAliasImportRequire)
      |> refute_issues()
    end

    test "alerts on alias inside function" do
      """
      defmodule Foo do
        def bar(baz) do
          alias Jump.Users.Schema
          %Schema{}
        end
      end
      """
      |> to_source_file()
      |> run_check(TopLevelAliasImportRequire)
      |> assert_issue()
    end

    test "alerts on alias inside describe block" do
      """
      defmodule FooTest do
        use ExUnit.Case

        describe "bar" do
          alias Jump.Users.Schema

          test "does something" do
            assert %Schema{}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(TopLevelAliasImportRequire)
      |> assert_issue()
    end
  end

  describe "require" do
    test "allows require at module level" do
      """
      defmodule Foo do
        require Logger

        def bar(baz) do
          Logger.info("hello")
        end
      end
      """
      |> to_source_file()
      |> run_check(TopLevelAliasImportRequire)
      |> refute_issues()
    end

    test "alerts on require inside function" do
      """
      defmodule Foo do
        def bar(baz) do
          require Logger
          Logger.info("hello")
        end
      end
      """
      |> to_source_file()
      |> run_check(TopLevelAliasImportRequire)
      |> assert_issue()
    end
  end

  describe "multiple issues" do
    test "alerts on multiple nested imports" do
      """
      defmodule Foo do
        def bar(baz) do
          import Ecto.Query
          alias Jump.User
          from(u in User)
        end
      end
      """
      |> to_source_file()
      |> run_check(TopLevelAliasImportRequire)
      |> assert_issues(fn issues ->
        assert length(issues) == 2
      end)
    end
  end

  test "allows import, alias, or require inside quote block" do
    """
    defmodule Foo do
      defmacro bar(baz) do
        quote do
          import Ecto.Query
          require Logger
          alias Jump.User
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(TopLevelAliasImportRequire)
    |> refute_issues()
  end

  test "allows variables named import, alias, or require" do
    """
    defmodule Foo do
      def bar(baz) do
        import = %{name: "import"}
        alias = %{name: "alias"}
        require = %{name: "require"}

        assert import.name == "import"
        assert alias.name == "alias"
        assert require.name == "require"
      end
    end
    """
    |> to_source_file()
    |> run_check(TopLevelAliasImportRequire)
    |> refute_issues()
  end

  test "allows import, alias, or require inside nested module" do
    """
    defmodule Foo do
      defmodule Bar do
        import Ecto.Query
        alias Jump.User
        require Logger
      end

      describe "my describe block" do
        defmodule Baz do
          import Ecto.Query
          alias Jump.User
          require Logger
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(TopLevelAliasImportRequire)
    |> refute_issues()
  end
end
