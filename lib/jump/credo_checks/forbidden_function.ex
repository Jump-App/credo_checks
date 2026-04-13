defmodule Jump.CredoChecks.ForbiddenFunction do
  @moduledoc """
  Forbids calls to specific functions.

  Similar to `Credo.Check.Warning.ForbiddenModule`, but for specific functions
  within a module rather than entire modules.

  ## Configuration

  Configure with a list of `{module, function, message}` tuples:

      {Jump.CredoChecks.ForbiddenFunction,
       functions: [
         {:erlang, :binary_to_term, "Use Plug.Crypto.non_executable_binary_to_term/2 instead."}
       ]}
  """
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      functions: []
    ],
    explanations: [
      check: """
      Some functions may be hazardous if used directly. Use this check to
      forbid specific functions while allowing the module itself.

      For example, `:erlang.binary_to_term/1` is vulnerable to arbitrary code
      execution exploits when deserializing untrusted data. Use
      `Plug.Crypto.non_executable_binary_to_term/2` instead, which disallows
      anonymous functions in the deserialized term.
      """,
      params: [
        functions: """
        List of `{module, function, message}` tuples specifying forbidden functions.

        Example:
            functions: [
              {:erlang, :binary_to_term, "Use Plug.Crypto.non_executable_binary_to_term/2 instead."}
            ]
        """
      ]
    ]

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    functions = Params.get(params, :functions, __MODULE__)
    forbidden_map = build_forbidden_map(functions)

    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta, forbidden_map))
  end

  defp build_forbidden_map(functions) do
    {qualified, bare} =
      Enum.split_with(functions, fn
        {module, function, _message} when is_atom(module) and is_atom(function) -> true
        _ -> false
      end)

    qualified_map =
      Map.new(qualified, fn {module, function, message} -> {{module, function}, message} end)

    bare_map =
      Map.new(bare, fn {function, arity, message} -> {{function, arity}, message} end)

    {qualified_map, bare_map}
  end

  # Handle calls to erlang modules like :erlang.binary_to_term(x)
  defp traverse({{:., meta, [module, function]}, _call_meta, _args} = ast, issues, issue_meta, {qualified_map, _})
       when is_atom(module) and is_atom(function) do
    case Map.get(qualified_map, {module, function}) do
      nil ->
        {ast, issues}

      message ->
        trigger = "#{inspect(module)}.#{function}"
        {ast, [create_issue(issue_meta, meta[:line], trigger, message) | issues]}
    end
  end

  # Handle calls to Elixir modules like Module.function(x)
  # Guard ensures all module_parts are atoms (excludes __MODULE__ etc.)
  defp traverse(
         {{:., meta, [{:__aliases__, _, module_parts}, function]}, _call_meta, _args} = ast,
         issues,
         issue_meta,
         {qualified_map, _}
       )
       when is_atom(function) and is_list(module_parts) do
    if Enum.all?(module_parts, &is_atom/1) do
      module = Module.concat(module_parts)

      case Map.get(qualified_map, {module, function}) do
        nil ->
          {ast, issues}

        message ->
          trigger = "#{inspect(module)}.#{function}"
          {ast, [create_issue(issue_meta, meta[:line], trigger, message) | issues]}
      end
    else
      # module_parts contains non-atoms like {:__MODULE__, _, _}, skip
      {ast, issues}
    end
  end

  # Handle unqualified (bare) function calls like function_exported?(mod, :func, 1)
  defp traverse({function, meta, args} = ast, issues, issue_meta, {_, bare_map})
       when is_atom(function) and is_list(args) do
    arity = length(args)

    case Map.get(bare_map, {function, arity}) do
      nil ->
        {ast, issues}

      message ->
        trigger = "#{function}/#{arity}"
        {ast, [create_issue(issue_meta, meta[:line], trigger, message) | issues]}
    end
  end

  defp traverse(ast, issues, _issue_meta, _forbidden_map), do: {ast, issues}

  defp create_issue(issue_meta, line_no, trigger, message) do
    format_issue(
      issue_meta,
      message: "#{trigger} is forbidden: #{message}",
      trigger: trigger,
      line_no: line_no
    )
  end
end
