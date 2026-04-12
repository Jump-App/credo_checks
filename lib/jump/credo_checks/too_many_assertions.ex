defmodule Jump.CredoChecks.TooManyAssertions do
  @moduledoc """
  Flags test blocks that contain too many assertions.

  Tests with too many assertions are testing multiple concerns in a single
  test block. This makes failures harder to diagnose and tests harder to
  maintain.
  """
  use Credo.Check,
    base_priority: :normal,
    category: :warning,
    param_defaults: [max_assertions: 20],
    explanations: [
      check: """
      Tests with too many assertions are testing multiple concerns in a single
      test block. This makes failures harder to diagnose and tests harder to
      maintain.

      Split large tests into focused sub-tests that each verify a single behavior.
      """,
      params: [
        max_assertions: "Maximum number of assertions allowed per test block (default: 20)."
      ]
    ]

  @assertion_functions ~w(
      assert refute assert_raise assert_receive assert_received
      refute_receive refute_received assert_in_delta refute_in_delta
      assert_has refute_has assert_empty refute_empty
      assert_equal_ci assert_ids_match assert_sorted_equal
      assert_issue refute_issues assert_enqueued refute_enqueued
      assert_text assert_reply assert_broadcast assert_push
      flunk await_has await_gone
      json_response text_response html_response response
    )a

  @doc false
  @impl Credo.Check
  def run(%SourceFile{filename: filename} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    if String.ends_with?(filename, "_test.exs") do
      max_assertions = Params.get(params, :max_assertions, __MODULE__)

      Credo.Code.prewalk(
        source_file,
        &traverse(&1, &2, issue_meta, max_assertions)
      )
    else
      []
    end
  end

  # Test block without context: test "name" do ... end
  defp traverse({:test, meta, [name, [do: body]]}, issues, issue_meta, max_assertions) when is_binary(name) do
    check_assertion_count(body, name, meta, issues, issue_meta, max_assertions)
  end

  # Test block with context: test "name", %{} do ... end
  defp traverse({:test, meta, [name, _context, [do: body]]}, issues, issue_meta, max_assertions) when is_binary(name) do
    check_assertion_count(body, name, meta, issues, issue_meta, max_assertions)
  end

  defp traverse(ast, issues, _issue_meta, _max_assertions) do
    {ast, issues}
  end

  defp check_assertion_count(body, name, meta, issues, issue_meta, max_assertions) do
    count = count_assertions(body)

    if count >= max_assertions do
      {:ok,
       [
         format_issue(
           issue_meta,
           message:
             "Test has #{count} assertions (max #{max_assertions}). Consider splitting into focused tests that each verify a single behavior.",
           trigger: name,
           line_no: meta[:line]
         )
         | issues
       ]}
    else
      {:ok, issues}
    end
  end

  defp count_assertions(body) do
    {_, count} =
      Macro.prewalk(body, 0, fn
        {fn_name, _meta, args} = node, acc when is_atom(fn_name) and is_list(args) ->
          if fn_name in @assertion_functions do
            {node, acc + 1}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    count
  end
end
