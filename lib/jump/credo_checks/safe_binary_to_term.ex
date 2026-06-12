defmodule Jump.CredoChecks.SafeBinaryToTerm do
  @moduledoc """
  Requires `Plug.Crypto.non_executable_binary_to_term/2` to be called with the
  `:safe` option.

  Without `:safe`, decoding interns any atoms embedded in the binary into the
  BEAM's fixed, never-garbage-collected atom table. When the binary is
  attacker-controlled (a pagination cursor, a request param, a webhook body), a
  payload packed with distinct atoms can exhaust the table and crash the node —
  a denial of service.

  Both `non_executable_binary_to_term/1` (no options) and a `/2` call whose
  options list omits `:safe` are flagged. Qualified, aliased, imported, and
  piped calls are all matched.

      # ❌ Bad — interns arbitrary atoms from untrusted input
      Plug.Crypto.non_executable_binary_to_term(binary, [])
      Plug.Crypto.non_executable_binary_to_term(binary)

      # ✅ Good — :safe makes decoding of an unknown atom raise instead
      Plug.Crypto.non_executable_binary_to_term(binary, [:safe])

  For the rare case where the input is genuinely trusted and `:safe` causes
  problems (e.g. atoms not yet loaded mid-deploy), exclude the file via Credo's
  built-in `files: %{excluded: [...]}` option with a comment explaining why the
  input cannot be attacker-controlled.
  """
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      `Plug.Crypto.non_executable_binary_to_term/2` must be called with the
      `:safe` option when the input could be attacker-controlled.

      Without `:safe`, the decoder interns every atom in the payload into the
      BEAM's fixed (~1M, never-GC'd) atom table. A crafted binary full of
      distinct atoms exhausts the table and crashes the node. `:safe` makes
      decoding an unknown atom raise instead of creating it.

      # Bad
      Plug.Crypto.non_executable_binary_to_term(binary, [])
      Plug.Crypto.non_executable_binary_to_term(binary)

      # Good
      Plug.Crypto.non_executable_binary_to_term(binary, [:safe])
      """
    ]

  alias Credo.IssueMeta

  def run(source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  # Matches any module-qualified call ending in `non_executable_binary_to_term`,
  # so it catches `Plug.Crypto.non_executable_binary_to_term`, an aliased
  # `Crypto.non_executable_binary_to_term`, etc. In a pipe the receiver argument
  # is absent from `args`, but `:safe` always appears as an element of a list
  # literal among the explicit args — so scanning the args works regardless of
  # pipe or arity.
  defp traverse({{:., _, [_module, :non_executable_binary_to_term]}, meta, args} = ast, issues, issue_meta)
       when is_list(args) do
    check_call(ast, args, meta, issues, issue_meta)
  end

  # Same, for an unqualified call — e.g. after `import Plug.Crypto`. The
  # `is_list(args)` guard excludes a bare variable of the same name (whose AST
  # third element is `nil`, not an argument list).
  defp traverse({:non_executable_binary_to_term, meta, args} = ast, issues, issue_meta) when is_list(args) do
    check_call(ast, args, meta, issues, issue_meta)
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp check_call(ast, args, meta, issues, issue_meta) do
    if safe_option?(args) do
      {ast, issues}
    else
      {ast, issues ++ [issue_for(issue_meta, meta[:line])]}
    end
  end

  defp safe_option?(args) do
    Enum.any?(args, fn arg -> is_list(arg) and :safe in arg end)
  end

  defp issue_for(issue_meta, line_no) do
    format_issue(
      issue_meta,
      message:
        "Call `Plug.Crypto.non_executable_binary_to_term/2` with the `:safe` option to prevent atom-table exhaustion from untrusted input.",
      trigger: "non_executable_binary_to_term",
      line_no: line_no
    )
  end
end
