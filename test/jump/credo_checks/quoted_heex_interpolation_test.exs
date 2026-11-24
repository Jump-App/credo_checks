defmodule Jump.CredoChecks.QuotedHEExInterpolationTest do
  use Credo.Test.Case, async: true

  alias Jump.CredoChecks.QuotedHEExInterpolation

  @template ~S'''
  <%!-- credo:disable-for-next-tag Jump.CredoChecks.QuotedHEExInterpolation --%>
  <.button
    id="skip-#{n}" />
  <Button
    id='warn-#{n}' />
  <div id={"ok-#{n}"} />
  <%!-- <div id="comment-#{n}" /> --%>
  {~s(<div id="string-#{n}" />)}
  '''

  test "checks inline HEEx at the attribute line" do
    source = "~H\"\"\"\n" <> @template <> "\"\"\""
    assert [%{line_no: 6}] = source |> to_source_file() |> run_check(QuotedHEExInterpolation)
  end

  test "intervening content cancels the skip and inline sigils keep their source line" do
    source =
      ~S|~H"<%!-- credo:disable-for-next-tag Jump.CredoChecks.QuotedHEExInterpolation --%> text <div id='literal-#{n}' />"|

    assert [%{line_no: 1}] = source |> to_source_file() |> run_check(QuotedHEExInterpolation)
  end
end
