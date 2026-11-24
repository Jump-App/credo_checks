defmodule Jump.CredoChecks.QuotedHEExInterpolation do
  @moduledoc "Warns about literal interpolation in quoted HEEx attribute values."
  use Credo.Check, category: :warning, explanations: [check: @moduledoc]

  @directive "<%!-- credo:disable-for-next-tag Jump.CredoChecks.QuotedHEExInterpolation --%>"
  # Consume balanced expressions as one token, including braces inside quoted strings.
  @expr ~S/(?<expr>\{(?:[^{}"']++|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|(?&expr))*\})/
  @text Regex.compile!("\\A(?:<%!--.*?--%>|<!--.*?-->|<%.*?%>|<[.:A-Za-z][\\w.:\\-]*|" <> @expr <> "|[^<{]++|.)", "s")
  @tag ~S"""
       \A(?:[^\s"'=<>/{]++\s*=\s*(?:"[^"]*"|'[^']*')|#{EXPR}|/?>|\s++|[^\s"'=<>/{]++|.)
       """
       |> String.trim()
       |> String.replace(~S(#{EXPR}), @expr)
       |> Regex.compile!("s")

  @impl Credo.Check
  def run(source_file, params \\ []) do
    issue =
      format_issue(IssueMeta.for(source_file, params),
        message: "Quoted HEEx attributes are literal. Use a braced string expression for interpolation."
      )

    {_, issues} =
      Macro.prewalk(SourceFile.ast(source_file), [], fn
        {:sigil_H, meta, [{:<<>>, _, [body]}, _]} = node, issues when is_binary(body) ->
          line = meta[:line] + if(meta[:delimiter] in ["\"\"\"", "'''"], do: 1, else: 0)
          {node, scan(body, line, :text, issue, issues)}

        node, issues ->
          {node, issues}
      end)

    issues
  end

  defp scan("", _, _, _, issues), do: issues

  defp scan(body, line, mode, issue, issues) do
    regex = if mode in [:text, :skip_next], do: @text, else: @tag
    [token] = Regex.run(regex, body, capture: :first)

    {next, issues} =
      case mode do
        _ when mode in [:text, :skip_next] -> {text_mode(mode, token), issues}
        _ when token in [">", "/>"] -> {:text, issues}
        :tag -> {:tag, flag_interpolation(token, line, issue, issues)}
        :skip_tag -> {:skip_tag, issues}
      end

    rest = binary_part(body, byte_size(token), byte_size(body) - byte_size(token))
    scan(rest, line + length(:binary.matches(token, "\n")), next, issue, issues)
  end

  defp text_mode(mode, token) do
    cond do
      token == @directive -> :skip_next
      mode == :skip_next and String.trim(token) == "" -> :skip_next
      Regex.match?(~r/^<[.:A-Za-z]/, token) -> if mode == :skip_next, do: :skip_tag, else: :tag
      true -> :text
    end
  end

  defp flag_interpolation(token, line, issue, issues) do
    if not String.starts_with?(token, "{") and String.contains?(token, ~S(#{)) do
      [%{issue | line_no: line, trigger: token} | issues]
    else
      issues
    end
  end
end
