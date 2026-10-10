defmodule Jump.CredoChecks.DoctestIExExamplesTest do
  use Credo.Test.Case, async: true

  alias Jump.CredoChecks.DoctestIExExamples

  test "alerts on module with `iex>` but no corresponding doctest call" do
    """
    defmodule MyApp.NeedsDoctest do
      @moduledoc \"\"\"
      This module needs a `doctest`.

      ## Examples

          iex> 1 + 1
          2
      \"\"\"
    end
    """
    |> to_source_file()
    |> run_check(DoctestIExExamples)
    |> assert_issue()
  end

  test "does not alert on module with `iex>` that has a corresponding doctest call" do
    """
    defmodule MyApp.HasDoctest do
      @moduledoc \"\"\"
      This module needs a `doctest`.

      ## Examples

          iex> 1 + 1
          2
      \"\"\"
    end
    """
    |> to_source_file()
    |> run_check(DoctestIExExamples, derive_test_path: fn _ -> "test/fixtures/has_doctest_test.exs" end)
    |> refute_issues()
  end

  test "alerts on module with `iex>` whose doctest is in a weird place" do
    """
    defmodule MyApp.HasDoctest do
      @moduledoc \"\"\"
      This module needs a `doctest`.

      ## Examples

          iex> 1 + 1
          2
      \"\"\"
    end
    """
    |> to_source_file()
    |> run_check(DoctestIExExamples)
    |> assert_issue()
  end

  @tag :tmp_dir
  test "does not alert when the test file doctests an alias of the module", %{tmp_dir: tmp_dir} do
    """
    defmodule MyApp.HasDoctest do
      @moduledoc \"\"\"
          iex> 1 + 1
          2
      \"\"\"
    end
    """
    |> run_check_with_test_file(tmp_dir, """
    defmodule MyApp.HasDoctestTest do
      use ExUnit.Case, async: true
      alias MyApp.HasDoctest
      doctest HasDoctest
    end
    """)
    |> refute_issues()
  end

  describe "nested modules" do
    @tag :tmp_dir
    test "alerts when only the outer module is doctested but a nested module has examples", %{tmp_dir: tmp_dir} do
      """
      defmodule MyApp.Outer do
        defmodule Inner do
          @doc \"\"\"
              iex> MyApp.Outer.Inner.limit()
              280
          \"\"\"
          def limit, do: 280
        end
      end
      """
      |> run_check_with_test_file(tmp_dir, """
      defmodule MyApp.OuterTest do
        use ExUnit.Case, async: true

        doctest MyApp.Outer
      end
      """)
      |> assert_issue(fn issue ->
        assert issue.message =~ "`MyApp.Outer.Inner`"
        assert issue.line_no == 3
      end)
    end

    @tag :tmp_dir
    test "does not alert when the nested module with `iex>` examples is doctested", %{tmp_dir: tmp_dir} do
      """
      defmodule MyApp.Outer do
        defmodule Inner do
          @doc \"\"\"
              iex> MyApp.Outer.Inner.limit()
              280
          \"\"\"
          def limit, do: 280
        end
      end
      """
      |> run_check_with_test_file(tmp_dir, """
      defmodule MyApp.AdapterTest do
        use ExUnit.Case, async: true

        doctest MyApp.Outer.Inner
      end
      """)
      |> refute_issues()
    end

    @tag :tmp_dir
    test "alerts once for each module with `iex>` examples that is missing a doctest", %{tmp_dir: tmp_dir} do
      """
      defmodule MyApp.Outer do
        @moduledoc \"\"\"
            iex> 1 + 1
            2
        \"\"\"

        defmodule Inner do
          @doc \"\"\"
              iex> MyApp.Outer.Inner.limit()
              280
          \"\"\"
          def limit, do: 280
        end
      end
      """
      |> run_check_with_test_file(tmp_dir, """
      defmodule MyApp.AdapterTest do
        use ExUnit.Case, async: true
      end
      """)
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(&{&1.line_no, &1.message}) |> Enum.sort() == [
                 {2, "Module `MyApp.Outer` has iex> examples but its test file is missing `doctest MyApp.Outer`."},
                 {8,
                  "Module `MyApp.Outer.Inner` has iex> examples but its test file is missing `doctest MyApp.Outer.Inner`."}
               ]
      end)
    end

    @tag :tmp_dir
    test "does not alert when both the outer and nested modules are doctested", %{tmp_dir: tmp_dir} do
      """
      defmodule MyApp.Outer do
        @moduledoc \"\"\"
            iex> 1 + 1
            2
        \"\"\"

        defmodule Inner do
          @doc \"\"\"
              iex> MyApp.Outer.Inner.limit()
              280
          \"\"\"
          def limit, do: 280
        end
      end
      """
      |> run_check_with_test_file(tmp_dir, """
      defmodule MyApp.AdapterTest do
        use ExUnit.Case, async: true

        doctest MyApp.Outer
        doctest MyApp.Outer.Inner
      end
      """)
      |> refute_issues()
    end

    @tag :tmp_dir
    test "attributes docs after a nested module back to the outer module", %{tmp_dir: tmp_dir} do
      """
      defmodule MyApp.Outer do
        defmodule Inner do
          def limit, do: 280
        end

        @doc \"\"\"
            iex> MyApp.Outer.limit()
            280
        \"\"\"
        def limit, do: Inner.limit()
      end
      """
      |> run_check_with_test_file(tmp_dir, """
      defmodule MyApp.AdapterTest do
        use ExUnit.Case, async: true

        doctest MyApp.Outer
      end
      """)
      |> refute_issues()
    end

    @tag :tmp_dir
    test "resolves nested modules named with `__MODULE__`", %{tmp_dir: tmp_dir} do
      """
      defmodule MyApp.Outer do
        defmodule __MODULE__.Inner do
          @doc \"\"\"
              iex> MyApp.Outer.Inner.limit()
              280
          \"\"\"
          def limit, do: 280
        end
      end
      """
      |> run_check_with_test_file(tmp_dir, """
      defmodule MyApp.AdapterTest do
        use ExUnit.Case, async: true

        doctest MyApp.Outer
      end
      """)
      |> assert_issue(fn issue -> assert issue.message =~ "`MyApp.Outer.Inner`" end)
    end

    @tag :tmp_dir
    test "attributes `iex>` examples to the right one of several top-level modules", %{tmp_dir: tmp_dir} do
      """
      defmodule MyApp.First do
        def hello, do: :world
      end

      defmodule MyApp.Second do
        @doc \"\"\"
            iex> MyApp.Second.hello()
            :world
        \"\"\"
        def hello, do: :world
      end
      """
      |> run_check_with_test_file(tmp_dir, """
      defmodule MyApp.FirstTest do
        use ExUnit.Case, async: true

        doctest MyApp.First
      end
      """)
      |> assert_issue(fn issue -> assert issue.message =~ "`MyApp.Second`" end)
    end
  end

  describe "matching the doctest call" do
    @config_source """
    defmodule MyApp.Scrapers.Config do
      @doc \"\"\"
          iex> MyApp.Scrapers.Config.timeout()
          5_000
      \"\"\"
      def timeout, do: 5_000
    end
    """

    @tag :tmp_dir
    test "does not accept a doctest for a module whose name merely starts with the module's name", %{
      tmp_dir: tmp_dir
    } do
      run_check_with_test_file(@config_source, tmp_dir, """
      defmodule MyApp.Scrapers.ConfigTest do
        use ExUnit.Case, async: true

        alias MyApp.Scrapers.ConfigLoader

        doctest ConfigLoader
      end
      """)
      |> assert_issue()
    end

    @tag :tmp_dir
    test "does not accept a doctest of an alias that points at a different module", %{tmp_dir: tmp_dir} do
      run_check_with_test_file(@config_source, tmp_dir, """
      defmodule MyApp.Scrapers.ConfigTest do
        use ExUnit.Case, async: true

        alias MyApp.Other.Config

        doctest Config
      end
      """)
      |> assert_issue()
    end

    @tag :tmp_dir
    test "does not accept an unaliased partial module name", %{tmp_dir: tmp_dir} do
      run_check_with_test_file(@config_source, tmp_dir, """
      defmodule MyApp.Scrapers.ConfigTest do
        use ExUnit.Case, async: true

        doctest Scrapers.Config
      end
      """)
      |> assert_issue()
    end

    @tag :tmp_dir
    test "does not accept a commented-out doctest", %{tmp_dir: tmp_dir} do
      run_check_with_test_file(@config_source, tmp_dir, """
      defmodule MyApp.Scrapers.ConfigTest do
        use ExUnit.Case, async: true

        # doctest MyApp.Scrapers.Config
      end
      """)
      |> assert_issue()
    end

    @tag :tmp_dir
    test "does not accept a doctest that only appears in a string", %{tmp_dir: tmp_dir} do
      run_check_with_test_file(@config_source, tmp_dir, ~S'''
      defmodule MyApp.Scrapers.ConfigTest do
        use ExUnit.Case, async: true

        @moduledoc """
        Remember to add doctest MyApp.Scrapers.Config
        """
      end
      ''')
      |> assert_issue()
    end

    @tag :tmp_dir
    test "accepts a doctest with options", %{tmp_dir: tmp_dir} do
      run_check_with_test_file(@config_source, tmp_dir, """
      defmodule MyApp.Scrapers.ConfigTest do
        use ExUnit.Case, async: true

        doctest MyApp.Scrapers.Config, import: true
      end
      """)
      |> refute_issues()
    end

    @tag :tmp_dir
    test "accepts a doctest of an `as:` alias", %{tmp_dir: tmp_dir} do
      run_check_with_test_file(@config_source, tmp_dir, """
      defmodule MyApp.Scrapers.ConfigTest do
        use ExUnit.Case, async: true

        alias MyApp.Scrapers.Config, as: ScraperConfig

        doctest ScraperConfig
      end
      """)
      |> refute_issues()
    end

    @tag :tmp_dir
    test "accepts a doctest of a multi-alias", %{tmp_dir: tmp_dir} do
      run_check_with_test_file(@config_source, tmp_dir, """
      defmodule MyApp.Scrapers.ConfigTest do
        use ExUnit.Case, async: true

        alias MyApp.Scrapers.{Config, Loader}

        doctest Config
      end
      """)
      |> refute_issues()
    end

    @tag :tmp_dir
    test "accepts a doctest of a module nested under an alias", %{tmp_dir: tmp_dir} do
      run_check_with_test_file(@config_source, tmp_dir, """
      defmodule MyApp.Scrapers.ConfigTest do
        use ExUnit.Case, async: true

        alias MyApp.Scrapers

        doctest Scrapers.Config
      end
      """)
      |> refute_issues()
    end

    @tag :tmp_dir
    test "does not accept an alias declared after the doctest line", %{tmp_dir: tmp_dir} do
      run_check_with_test_file(@config_source, tmp_dir, """
      defmodule MyApp.Scrapers.ConfigTest do
        use ExUnit.Case, async: true

        doctest Scrapers.Config
        alias MyApp.Scrapers
      end
      """)
      |> assert_issue()
    end

    @tag :tmp_dir
    test "accepts a doctest of an alias built on another alias", %{tmp_dir: tmp_dir} do
      run_check_with_test_file(@config_source, tmp_dir, """
      defmodule MyApp.Scrapers.ConfigTest do
        use ExUnit.Case, async: true

        alias MyApp.Scrapers
        alias Scrapers.Config

        doctest Config
      end
      """)
      |> refute_issues()
    end

    @tag :tmp_dir
    test "does not accept a mismatched doctest in a sibling test file", %{tmp_dir: tmp_dir} do
      tmp_dir
      |> Path.join("config_loader_test.exs")
      |> File.write!("""
      defmodule MyApp.Scrapers.ConfigLoaderTest do
        use ExUnit.Case, async: true

        doctest MyApp.Scrapers.ConfigLoader
      end
      """)

      @config_source
      |> to_source_file(Path.join(tmp_dir, "config.ex"))
      |> run_check(DoctestIExExamples, derive_test_path: fn _ -> Path.join(tmp_dir, "config_test.exs") end)
      |> assert_issue(fn issue -> assert issue.message =~ "no test file at `config_test.exs`" end)
    end
  end

  defp run_check_with_test_file(source, tmp_dir, test_file_source) do
    test_file = Path.join(tmp_dir, "source_test.exs")
    File.write!(test_file, test_file_source)

    source
    |> to_source_file(Path.join(tmp_dir, "source.ex"))
    |> run_check(DoctestIExExamples, derive_test_path: fn _ -> test_file end)
  end
end
