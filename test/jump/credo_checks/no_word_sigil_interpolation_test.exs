defmodule Jump.CredoChecks.NoWordSigilInterpolationTest do
  use Credo.Test.Case, async: true

  alias Jump.CredoChecks.NoWordSigilInterpolation

  test "flags interpolation, including the quoted phrase example" do
    ~S|~w("hello #{foo} world")|
    |> to_source_file()
    |> run_check(NoWordSigilInterpolation)
    |> assert_issue(fn issue ->
      assert issue.message =~ "explicit list"
      assert issue.line_no == 1
      assert issue.trigger == "~w"
    end)
  end

  test "flags interpolation with every modifier" do
    for modifier <- ["", "a", "c", "s"] do
      (~S|~w(name #{foo} balance)| <> modifier)
      |> to_source_file()
      |> run_check(NoWordSigilInterpolation)
      |> assert_issue()
    end
  end

  test "flags interpolation with every delimiter" do
    for source <- [
          ~S|~w(foo #{bar})|,
          ~S|~w[foo #{bar}]|,
          ~S|~w{foo #{bar}}|,
          ~S|~w<foo #{bar}>|,
          ~S|~w"foo #{bar}"|,
          ~S|~w'foo #{bar}'|,
          ~S|~w/foo #{bar}/|,
          ~S"~w|foo #{bar}|"
        ] do
      source
      |> to_source_file()
      |> run_check(NoWordSigilInterpolation)
      |> assert_issue()
    end
  end

  test "flags heredocs and reports the sigil's line and column" do
    ~S'''
    def words do
      ~w"""
      hello #{foo}
      """
    end
    '''
    |> to_source_file()
    |> run_check(NoWordSigilInterpolation)
    |> assert_issue(fn issue ->
      assert issue.line_no == 2
      assert issue.column == 3
    end)
  end

  test "reports one issue per offending sigil" do
    ~S|{~w(a #{foo} b), ~w(#{bar}), ~w(plain)}|
    |> to_source_file()
    |> run_check(NoWordSigilInterpolation)
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end

  test "allows plain word sigils with every modifier and punctuation" do
    for modifier <- ["", "a", "c", "s"] do
      (~S|~w(name net_worth balance foo/bar "hello" don't [x] {y})| <> modifier)
      |> to_source_file()
      |> run_check(NoWordSigilInterpolation)
      |> refute_issues()
    end
  end

  test "allows empty and multiline word sigils" do
    ~S'''
    ~w()
    ~w"""
    name
    net_worth
    foo"""bar
    """
    '''
    |> to_source_file()
    |> run_check(NoWordSigilInterpolation)
    |> refute_issues()
  end

  test "ignores escapes, since only interpolation is flagged" do
    ~S'''
    ~w(name net\ worth)
    ~w(hello\nworld)
    ~w(foo\)bar)
    '''
    |> to_source_file()
    |> run_check(NoWordSigilInterpolation)
    |> refute_issues()
  end

  test "ignores uppercase word sigils, other sigils, strings, and comments" do
    ~S'''
    ~W(name #{foo})
    ~s(hello #{foo})
    "~w(name #{foo})"
    # ~w(#{foo})
    '''
    |> to_source_file()
    |> run_check(NoWordSigilInterpolation)
    |> refute_issues()
  end
end
