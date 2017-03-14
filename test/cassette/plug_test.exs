defmodule Cassette.PlugTest do
  use ExUnit.Case, async: true
  use Plug.Test

  import ExUnit.CaptureLog

  setup tags do
    if tags[:session] do
      session_opts = Plug.Session.init(store: :cookie, key: "_session_key",
                                   encryption_salt: "NaCl", signing_salt: "KCl")

      conn = conn(:get, tags[:path] || "/", tags[:body] || %{})
      |> Plug.Session.call(session_opts)
      |> Plug.Conn.fetch_session()
      |> Plug.Conn.fetch_query_params()

      {:ok, conn: conn}
    else
      :ok
    end
  end

  @tag session: true
  test "call/2 with no user in session and no ticket redirects to auth", %{conn: conn} do
    assert %Plug.Conn{status: 307, halted: true, resp_headers: headers} = Cassette.Plug.call(conn, [cassette: CassetteMock])

    assert Enum.member?(headers, {"location", "#{CassetteMock.config.base_url}/login?service=http://www.example.com/"})
  end

  @tag session: true
  test "call/2 a user in session does not halt the connection", %{conn: conn} do
    conn = conn |> Plug.Conn.put_session("cas_user", CassetteMock.valid_user)

    assert %Plug.Conn{halted: false} = Cassette.Plug.call(conn, [cassette: CassetteMock])
  end

  @tag session: true, path: "/?ticket=#{CassetteMock.valid_ticket}"
  test "call/2 with no user and valid ticket does not halt the connection", %{conn: conn} do
    assert %Plug.Conn{halted: false} = Cassette.Plug.call(conn, [cassette: CassetteMock])
  end

  @tag session: true, path: "/?ticket=#{CassetteMock.valid_ticket}"
  test "call/2 with no user and valid ticket sets the user in the session", %{conn: conn} do
    assert CassetteMock.valid_user ==
      conn
      |> Cassette.Plug.call([cassette: CassetteMock])
      |> Plug.Conn.get_session("cas_user")
  end

  @tag session: true, path: "/?ticket=#{CassetteMock.invalid_ticket}"
  test "call/2 with no user and invalid ticket halts the connection with forbidden", %{conn: conn} do
    capture_log fn ->
      assert %Plug.Conn{halted: true, status: 403} = Cassette.Plug.call(conn, [cassette: CassetteMock])
    end
  end

  @tag session: true, path: "/?ticket=#{CassetteMock.invalid_ticket}"
  test "call/2 logs the authentication failure", %{conn: conn} do
    log = capture_log fn ->
      Cassette.Plug.call(conn, [cassette: CassetteMock])
    end

    assert log =~ "Validation of \"#{CassetteMock.invalid_ticket}\" failed"
  end
end
