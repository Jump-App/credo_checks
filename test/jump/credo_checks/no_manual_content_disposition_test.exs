defmodule Jump.CredoChecks.NoManualContentDispositionTest do
  use Credo.Test.Case, async: true

  alias Jump.CredoChecks.NoManualContentDisposition

  test "accepts send_download" do
    """
    defmodule Sample do
      def download(conn) do
        send_download(conn, {:binary, "ok"}, filename: "export.csv")
      end
    end
    """
    |> to_source_file()
    |> run_check(NoManualContentDisposition)
    |> refute_issues()
  end

  test "accepts other response headers" do
    """
    defmodule Sample do
      def download(conn) do
        put_resp_header(conn, "content-type", "text/csv")
      end
    end
    """
    |> to_source_file()
    |> run_check(NoManualContentDisposition)
    |> refute_issues()
  end

  test "reports direct manual content-disposition headers" do
    """
    defmodule Sample do
      def download(conn) do
        put_resp_header(conn, "content-disposition", "attachment; filename=\\"export.csv\\"")
      end
    end
    """
    |> to_source_file()
    |> run_check(NoManualContentDisposition)
    |> assert_issue(%{
      message: ~r/Prefer `send_download\/3`/,
      trigger: "content-disposition",
      line_no: 3
    })
  end

  test "reports piped manual content-disposition headers" do
    """
    defmodule Sample do
      def download(conn) do
        conn
        |> put_resp_header("content-disposition", "attachment; filename=\\"export.csv\\"")
      end
    end
    """
    |> to_source_file()
    |> run_check(NoManualContentDisposition)
    |> assert_issue(%{
      message: ~r/Prefer `send_download\/3`/,
      trigger: "content-disposition",
      line_no: 4
    })
  end

  test "reports Plug.Conn manual content-disposition headers" do
    """
    defmodule Sample do
      def download(conn) do
        Plug.Conn.put_resp_header(conn, "Content-Disposition", "attachment; filename=\\"export.csv\\"")
      end
    end
    """
    |> to_source_file()
    |> run_check(NoManualContentDisposition)
    |> assert_issue(%{
      message: ~r/Prefer `send_download\/3`/,
      trigger: "content-disposition",
      line_no: 3
    })
  end

  test "reports aliased remote manual content-disposition headers" do
    """
    defmodule Sample do
      def download(conn) do
        Conn.put_resp_header(conn, "content-disposition", "attachment; filename=\\"export.csv\\"")
      end
    end
    """
    |> to_source_file()
    |> run_check(NoManualContentDisposition)
    |> assert_issue(%{
      message: ~r/Prefer `send_download\/3`/,
      trigger: "content-disposition",
      line_no: 3
    })
  end
end
