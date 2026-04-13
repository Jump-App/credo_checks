defmodule Jump.CredoChecks.AssertElementSelectorCanNeverFailTest do
  use Credo.Test.Case, async: true

  alias Jump.CredoChecks.AssertElementSelectorCanNeverFail

  test "alerts on assert element() call" do
    for call <- [
          "assert Phoenix.LiveViewTest.element(view, \"[data-testid='button']\")",
          ~s{assert Phoenix.LiveViewTest.element(view, "[data-testid='button']", "Click")},
          "assert LiveViewTest.element(view, \"[data-testid='button']\")",
          ~s{assert LiveViewTest.element(view, "[data-testid='button']", "Click")},
          "assert element(view, \"[data-testid='button']\")",
          ~s{assert element(view, "[data-testid='button']", "Click")}
        ] do
      """
      defmodule MyTest do
        import Phoenix.LiveViewTest
        alias Phoenix.LiveViewTest

        test "should not assert element" do
          #{call}
        end
      end
      """
      |> to_source_file()
      |> run_check(AssertElementSelectorCanNeverFail)
      |> assert_issue()
    end
  end

  test "does not alert on has_element? call" do
    """
    defmodule MyTest do
      test "should use has_element" do
        assert has_element?(view, "[data-testid='button']")
      end
    end
    """
    |> to_source_file()
    |> run_check(AssertElementSelectorCanNeverFail)
    |> refute_issues()
  end

  test "does not alert on other assertions" do
    """
    defmodule MyTest do
      test "other assertions are fine" do
        assert true
        assert 1 == 1
      end
    end
    """
    |> to_source_file()
    |> run_check(AssertElementSelectorCanNeverFail)
    |> refute_issues()
  end
end
