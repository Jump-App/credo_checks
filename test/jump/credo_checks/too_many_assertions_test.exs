defmodule Jump.CredoChecks.TooManyAssertionsTest do
  use Credo.Test.Case, async: true

  alias Jump.CredoChecks.TooManyAssertions

  test "flags tests with too many assertions" do
    """
    test "example" do
    assert 1 == 1
    assert 2 == 2
    assert 3 == 3
    end
    """
    |> to_source_file("lib/my_module_test.exs")
    |> run_check(TooManyAssertions, max_assertions: 2)
    |> assert_issue()
  end

  test "does not flag tests with fewer than max_assertions" do
    """
    test "example" do
      assert 1 == 1
    end
    """
    |> to_source_file("lib/my_module_test.exs")
    |> run_check(TooManyAssertions, max_assertions: 2)
    |> refute_issues()
  end
end
