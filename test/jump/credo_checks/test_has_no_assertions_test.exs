defmodule Jump.CredoChecks.TestHasNoAssertionsTest do
  use Credo.Test.Case, async: true

  alias Jump.CredoChecks.TestHasNoAssertions

  test "alerts on test with no assertions" do
    """
    defmodule MyTest do
      use Jump.DataCase, async: true

      test "checks assigns", %{user: user} do
        %User{} = MyModule.do_stuff(user)
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(TestHasNoAssertions)
    |> assert_issue(fn issue ->
      assert issue.message =~ "has no assertions"
    end)
  end

  test "does not alert on test with assertions" do
    """
    defmodule MyTest do
      use Jump.DataCase, async: true

      test "checks assigns", %{user: user} do
        assert %User{} = MyModule.do_stuff(user)
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(TestHasNoAssertions)
    |> refute_issues()
  end

  test "does not alert on test with heretofore unknown function that seems like an assertion" do
    for assertion_line <- ["assert_blah_blah_blah(user)", "MyModule.refute_blah_blah_blah(user)"] do
      """
      defmodule MyTest do
        use Jump.DataCase, async: true

        test "checks assigns", %{user: user} do
          #{assertion_line}
        end
      end
      """
      |> to_source_file("test/my_test.exs")
      |> run_check(TestHasNoAssertions, custom_assertion_functions: [:my_assertion])
      |> refute_issues()
    end
  end

  test "does not alert on test with custom assertions" do
    for assertion_line <- ["my_assertion(user)", "MyModule.my_assertion(user)"] do
      """
      defmodule MyTest do
        use Jump.DataCase, async: true

        test "checks assigns", %{user: user} do
          #{assertion_line}
        end
      end
      """
      |> to_source_file("test/my_test.exs")
      |> run_check(TestHasNoAssertions, custom_assertion_functions: [:my_assertion])
      |> refute_issues()
    end
  end

  test "does not alert on test calling local helpers that assert" do
    """
    defmodule MyTest do
      use ExUnit.Case, async: true

      test "direct helper" do
        then_it_works(1)
      end

      test "piped helper" do
        %{}
        |> given_something()
        |> then_it_really_works()
      end

      defp given_something(context), do: context

      defp then_it_works(value) when is_integer(value) do
        assert value == 1
      end

      defp then_it_really_works(context) do
        assert_has(context, "dd")
      end
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(TestHasNoAssertions)
    |> refute_issues()
  end

  test "alerts on test calling only local helpers that don't assert" do
    """
    defmodule MyTest do
      use ExUnit.Case, async: true

      test "no assertions" do
        given_something(%{})
      end

      defp given_something(context), do: context
    end
    """
    |> to_source_file("test/my_test.exs")
    |> run_check(TestHasNoAssertions)
    |> assert_issue()
  end
end
