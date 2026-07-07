defmodule Jump.CredoChecks.NoManualContentDisposition do
  @moduledoc false

  use Credo.Check,
    base_priority: :normal,
    category: :warning,
    explanations: [
      check: ~S"""
      Prefer `Phoenix.Controller.send_download/3` instead of manually setting `content-disposition`.

      This prevents injection attacks by sanitizing `filename` in the response header.
      This follows the suggestion from the
      [Cowboy security checklist](https://ninenines.eu/docs/en/cowboy/2.17/guide/security_checklist/):

      > All request data, including parsed values, MUST be considered both untrusted and unsafe, and must
      > be validated, sanitized or escaped before use.

          # ❌ Bad (manual, error-prone use of content-disposition header):
          conn
          |> put_resp_content_type(content_type)
          |> put_resp_header("content-disposition", "attachment; filename="#{filename}.csv")
          |> send_resp(200, content)

          # ✅ Good (Phoenix handles filename sanitization)
          send_download(conn, {:binary, content},
            filename: filename,
            content_type: content_type,
            charset: "utf-8",
            disposition: :inline
          )

          # 🆗 OK (need to stream response, can't use send_download)
          encoded_filename = URI.encode(filename, &URI.char_unreserved?/1)
          content_disposition = ~s[attachment; filename="#{encoded_filename}"; filename*=utf-8''#{encoded_filename}]

          conn
          |> put_resp_content_type("text/csv")
          # stream chunks, so send_download/3 cannot be used here
          # credo:disable-for-next-line Ev2.Credo.NoManualContentDisposition
          |> put_resp_header("content-disposition", content_disposition)
          |> send_chunked(200)
      """
    ]

  @message "Prefer `send_download/3` instead of setting the `content-disposition` header manually."

  @impl Credo.Check
  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  defp traverse({:put_resp_header, meta, args} = ast, issues, issue_meta) when is_list(args) do
    {ast, maybe_add_issue(args, meta, issues, issue_meta)}
  end

  defp traverse({{:., dot_meta, [_module, :put_resp_header]}, call_meta, args} = ast, issues, issue_meta)
       when is_list(args) do
    {ast, maybe_add_issue(args, Keyword.merge(call_meta, dot_meta), issues, issue_meta)}
  end

  defp traverse(ast, issues, _issue_meta) do
    {ast, issues}
  end

  defp maybe_add_issue(args, meta, issues, issue_meta) do
    if content_disposition_header?(args) do
      issues ++ [issue_for(meta[:line], issue_meta)]
    else
      issues
    end
  end

  defp content_disposition_header?(args) do
    case header_arg(args) do
      {:ok, header} when is_binary(header) -> String.downcase(header) == "content-disposition"
      _ -> false
    end
  end

  defp header_arg([header, _value]), do: {:ok, header}
  defp header_arg([_conn, header, _value]), do: {:ok, header}
  defp header_arg(_args), do: :error

  defp issue_for(line_no, issue_meta) do
    format_issue(
      issue_meta,
      message: @message,
      trigger: "content-disposition",
      line_no: line_no
    )
  end
end
