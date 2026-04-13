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
end
