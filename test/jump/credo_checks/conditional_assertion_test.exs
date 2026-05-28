defmodule Jump.CredoChecks.ConditionalAssertionTest do
  use Credo.Test.Case, async: true

  alias Jump.CredoChecks.ConditionalAssertion

  describe "flags non-deterministic assertions" do
    for assertion <- [
          "assert foo == :bar or baz == :bop",
          "assert foo == :bar || baz == :bop",
          "assert foo in [:bar, :baz] or bop in [:whiz, :bang]",
          "assert foo in [:bar, :baz] || bop in [:whiz, :bang]",
          "assert (foo =~ \"bar\") or (baz * 10 + 4 < 0)",
          "assert a or b or c",
          "assert a || b || c",
          "assert a or b, \"custom message\"",
          "assert a || b, \"custom message\""
        ] do
      @tag assertion: assertion
      test "flags `#{assertion}`", %{assertion: assertion} do
        """
        defmodule MyTest do
          use ExUnit.Case, async: true

          test "non-deterministic" do
            #{assertion}
          end
        end
        """
        |> to_source_file()
        |> run_check(ConditionalAssertion)
        |> assert_issue(fn issue ->
          expected_operator =
            if assertion =~ "or" do
              "or"
            else
              "||"
            end

          assert issue.message =~
                   "Asserting on a conditional (`#{expected_operator}`) indicates a lack of clarity about the expected behavior."

          assert issue.message =~ "Assert the specific value you expect."
        end)
      end
    end
  end

  describe "does not flag deterministic assertions" do
    for assertion <- [
          "assert foo == :bar",
          "assert foo == :bar and baz == :bop",
          "assert foo == :bar && baz == :bop",
          "assert foo in [:bar, :baz]",
          "assert Enum.any?(list, fn x -> x == 1 or x == 2 end)",
          "assert match?({:ok, _}, result)",
          "assert true"
        ] do
      @tag assertion: assertion
      test "does not flag `#{assertion}`", %{assertion: assertion} do
        """
        defmodule MyTest do
          use ExUnit.Case, async: true

          test "deterministic" do
            #{assertion}
          end
        end
        """
        |> to_source_file()
        |> run_check(ConditionalAssertion)
        |> refute_issues()
      end
    end
  end
end
