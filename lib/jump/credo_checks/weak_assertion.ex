defmodule CredoChecks.WeakAssertion do
  @moduledoc """
  Ensures tests don't use low-value assertions like `refute is_nil(val)`.

  We want to avoid assertions that only verify that a value is of a certain type,
  without asserting anything meaningful about it. A passing `assert is_list(val)` tells
  you nothing about whether the list has the right elements, length, etc. Even worse is
  something that merely tells you what the value is *not*, like `refute is_nil(val)`.
  """
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Assertions like `assert is_list(val)` or `refute is_nil(val)` are almost
      always too weak. They pass for any value of the right type, which means
      the test isn't actually verifying the behavior you care about.

      Instead, assert something specific about the value:

          # ❌ Weak
          assert is_list(result)
          assert is_map(result)
          assert is_binary(result)
          refute is_nil(result)
          refute result == nil
          assert result != nil
          assert not is_nil(result)
          assert result
          assert %{} = result
          assert "" <> _ = result
          assert <<_::binary>> = result
          assert %{key: <<_::binary>>} = result

          # ✅ Strong
          assert [%Product{id: ^id}] = result
          assert %{name: "Tyler"} = result
          assert result == "expected string"
          assert is_nil(error)
          assert %Product{} = result
      """
    ]

  @type_checks ~w(
      is_list is_map is_binary is_nil is_atom is_boolean
      is_tuple is_bitstring
      is_struct is_exception
    )a

  @suggestions %{
    is_list: "Assert something about the list (its length, contents, specific elements, etc.).",
    is_map: "Assert something about the map (specific key-value pairs, structure, etc.).",
    is_binary:
      "Assert something about what's in the string (at the very least, that it's non-empty: byte_size(val) > 0).",
    is_nil: "Assert what the value *is*, rather than what it is not.",
    is_atom: "Assert the specific atom value, e.g. `assert val == :ok`.",
    is_boolean: "Assert the specific boolean value, e.g. `assert val == true`.",
    is_float: "Assert the specific numeric value or a range.",
    is_integer: "Assert the specific numeric value or a range.",
    is_number: "Assert the specific numeric value or a range.",
    is_tuple: "Pattern match on the tuple, e.g. `assert {:ok, _} = val`.",
    is_bitstring: "Assert the specific value or match on a pattern.",
    is_struct: "Assert the specific struct, e.g. `assert %MyStruct{} = val`.",
    is_exception: "Assert the specific exception, e.g. `assert %ArgumentError{} = val`."
  }

  @doc false
  @impl Credo.Check
  def run(%SourceFile{filename: filename} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    if String.ends_with?(filename, "_test.exs") do
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    else
      []
    end
  end

  # Skip property tests — type checks are reasonable for property-based testing
  # where you're verifying behavior across arbitrary generated inputs.
  # Replacing the AST with :ok prevents prewalk from descending into children.
  defp traverse({:property, _meta, _args}, issues, _issue_meta) do
    {:ok, issues}
  end

  # assert is_nil(val) is allowed — it's a specific, positive assertion.
  defp traverse({:assert, _meta, [{:is_nil, _, _args}]} = ast, issues, _issue_meta) do
    {ast, issues}
  end

  # assert is_struct(val, Module) is allowed — it asserts a specific struct type.
  defp traverse({:assert, _meta, [{:is_struct, _, [_, _]}]} = ast, issues, _issue_meta) do
    {ast, issues}
  end

  defp traverse({assert_or_refute, meta, [{type_check, _, _args}]} = ast, issues, issue_meta)
       when assert_or_refute in [:assert, :refute] and type_check in @type_checks do
    {ast, [issue_for(issue_meta, assert_or_refute, type_check, meta[:line]) | issues]}
  end

  # assert not is_nil(val)
  defp traverse({:assert, meta, [{:not, _, [{type_check, _, _args}]}]} = ast, issues, issue_meta)
       when type_check in @type_checks do
    {ast, [issue_for(issue_meta, :assert_not, type_check, meta[:line]) | issues]}
  end

  # assert !is_nil(val)
  defp traverse({:assert, meta, [{:!, _, [{type_check, _, _args}]}]} = ast, issues, issue_meta)
       when type_check in @type_checks do
    {ast, [issue_for(issue_meta, :assert_not, type_check, meta[:line]) | issues]}
  end

  # refute String.length(val) == 0, refute byte_size(val) == 0
  defp traverse({:refute, meta, [{:==, _, [size_call, 0]}]} = ast, issues, issue_meta) do
    case size_check_fn(size_call) do
      nil -> {ast, issues}
      fn_name -> {ast, [non_empty_string_issue(issue_meta, "refute #{fn_name}(...) == 0", meta[:line]) | issues]}
    end
  end

  # assert val != nil, assert nil != val
  defp traverse({:assert, meta, [{:!=, _, args}]} = ast, issues, issue_meta) do
    if nil in args do
      {ast,
       [
         format_issue(
           issue_meta,
           message:
             "assert val != nil is a weak assertion. Assert on what the result actually is, e.g. `assert %DateTime{} = result`, or you may want to combine the assignment with a previous statement, like `assert element = Enum.find(list, fn item -> item == 2 end)`.",
           trigger: "assert val != nil",
           line_no: meta[:line]
         )
         | issues
       ]}
    else
      {ast, issues}
    end
  end

  # refute val == nil, refute nil == val
  defp traverse({:refute, meta, [{:==, _, args}]} = ast, issues, issue_meta) do
    if nil in args do
      {ast,
       [
         format_issue(
           issue_meta,
           message: "refute val == nil is a weak assertion. Assert something specific about the value instead.",
           trigger: "refute val == nil",
           line_no: meta[:line]
         )
         | issues
       ]}
    else
      {ast, issues}
    end
  end

  # assert true, refute false — always-passing assertions
  defp traverse({:assert, meta, [true]} = ast, issues, issue_meta) do
    {ast,
     [
       format_issue(
         issue_meta,
         message: "assert true is a weak assertion that always passes. Assert something meaningful.",
         trigger: "assert true",
         line_no: meta[:line]
       )
       | issues
     ]}
  end

  defp traverse({:refute, meta, [false]} = ast, issues, issue_meta) do
    {ast,
     [
       format_issue(
         issue_meta,
         message: "refute false is a weak assertion that always passes. Assert something meaningful.",
         trigger: "refute false",
         line_no: meta[:line]
       )
       | issues
     ]}
  end

  # assert result (bare variable — only checks truthiness)
  # Skip variables ending in ? — they conventionally hold booleans, so `assert bool?` is fine.
  defp traverse({:assert, meta, [{var, _, context}]} = ast, issues, issue_meta)
       when is_atom(var) and is_atom(context) and var not in [true, false, nil] do
    if String.ends_with?(Atom.to_string(var), "?") do
      {ast, issues}
    else
      {ast,
       [
         format_issue(
           issue_meta,
           message:
             "assert #{var} is a weak assertion that only checks truthiness. Assert something specific about the value instead.",
           trigger: "assert #{var}",
           line_no: meta[:line]
         )
         | issues
       ]}
    end
  end

  # assert "" <> _ = expr — matching with empty string prefix only checks it's a binary
  defp traverse({:assert, meta, [{:=, _, [{:<>, _, ["", {:_, _, _atom}]}, _rhs]}]} = ast, issues, issue_meta) do
    {ast,
     [
       format_issue(
         issue_meta,
         message:
           ~s(assert "" <> _ = val is a weak assertion that only checks the value is a binary. Assert something about the string's content instead.),
         trigger: ~s(assert "" <> _ = val),
         line_no: meta[:line]
       )
       | issues
     ]}
  end

  # assert %{} = expr — matching against an empty map only checks it's a map
  defp traverse({:assert, meta, [{:=, _, [{:%{}, _, []}, _rhs]}]} = ast, issues, issue_meta) do
    {ast,
     [
       format_issue(
         issue_meta,
         message:
           "assert %{} = val is a weak assertion that only checks the value is a map. Assert specific key-value pairs, e.g. `assert %{name: \"Tyler\"} = result`.",
         trigger: "assert %{} = val",
         line_no: meta[:line]
       )
       | issues
     ]}
  end

  # assert <<_::binary>> = expr — matching any possibly-empty binary is weak
  # Also catches nested cases like assert %{key: <<_, _::binary>>} = expr
  defp traverse({:<<>>, meta, [{:"::", _, [{:_, _, _}, {:binary, _, _}]}]} = ast, issues, issue_meta) do
    {ast,
     [
       format_issue(
         issue_meta,
         message:
           ~s(<<_::binary>> is a weak match that only checks the value is a binary. Assert something about the string's content instead.),
         trigger: ~s(<<_::binary>>),
         line_no: meta[:line]
       )
       | issues
     ]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp size_check_fn({{:., _, [{:__aliases__, _, [:String]}, :length]}, _, [_]}), do: "String.length"
  defp size_check_fn({:byte_size, _, [_]}), do: "byte_size"
  defp size_check_fn(_), do: nil

  defp non_empty_string_issue(issue_meta, trigger, line_no) do
    format_issue(
      issue_meta,
      message:
        "#{trigger} is a weak assertion that only checks the string is non-empty. Assert something about the string's content instead.",
      trigger: trigger,
      line_no: line_no
    )
  end

  defp issue_for(issue_meta, assert_form, type_check, line_no) do
    trigger =
      case assert_form do
        :assert -> "assert #{type_check}(...)"
        :refute -> "refute #{type_check}(...)"
        :assert_not -> "assert not #{type_check}(...)"
      end

    suggestion = Map.get(@suggestions, type_check, "Assert something more specific about the value.")

    format_issue(
      issue_meta,
      message: "#{trigger} is a weak assertion that only checks the type. #{suggestion}",
      trigger: trigger,
      line_no: line_no
    )
  end
end
