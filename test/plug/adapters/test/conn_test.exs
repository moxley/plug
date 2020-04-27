defmodule Plug.Adapters.Test.ConnTest do
  use ExUnit.Case, async: true

  import Plug.Test

  test "read_req_body/2" do
    conn = conn(:get, "/", "abcdefghij")
    {adapter, state} = conn.adapter

    assert {:more, "abcde", state} = adapter.read_req_body(state, length: 5)
    assert {:more, "f", state} = adapter.read_req_body(state, length: 1)
    assert {:more, "gh", state} = adapter.read_req_body(state, length: 2)
    assert {:ok, "ij", state} = adapter.read_req_body(state, length: 5)
    assert {:ok, "", _state} = adapter.read_req_body(state, length: 5)
  end

  test "custom params" do
    conn = conn(:head, "/posts", page: 2)
    assert conn.body_params == %Plug.Conn.Unfetched{aspect: :body_params}
    assert conn.params == %{"page" => "2"}
    assert conn.req_headers == []

    conn = conn(:get, "/", a: [b: 0, c: 5], d: [%{e: "f"}])
    assert conn.body_params == %Plug.Conn.Unfetched{aspect: :body_params}
    assert conn.params == %{"a" => %{"b" => "0", "c" => "5"}, "d" => [%{"e" => "f"}]}

    conn = conn(:get, "/?foo=bar", %{foo: "baz"})
    assert conn.body_params == %Plug.Conn.Unfetched{aspect: :body_params}
    assert conn.params == %{"foo" => "baz"}

    conn = conn(:get, "/?foo=bar", %{biz: "baz"})
    assert conn.body_params == %Plug.Conn.Unfetched{aspect: :body_params}
    assert conn.params == %{"foo" => "bar", "biz" => "baz"}

    conn = conn(:get, "/?f=g", a: "b", c: [d: "e"])
    assert conn.body_params == %Plug.Conn.Unfetched{aspect: :body_params}
    assert conn.params == %{"a" => "b", "c" => %{"d" => "e"}, "f" => "g"}

    conn = conn(:post, "/?foo=bar", %{foo: "baz", answer: 42})
    assert conn.body_params == %{"foo" => "baz", "answer" => 42}
    assert conn.params == %{"foo" => "baz", "answer" => 42}

    conn = conn(:post, "/?foo=bar", %{biz: "baz"})
    assert conn.body_params == %{"biz" => "baz"}
    assert conn.params == %{"foo" => "bar", "biz" => "baz"}
  end

  test "custom struct params" do
    conn = conn(:get, "/", a: "b", file: %Plug.Upload{})

    assert conn.params == %{
             "a" => "b",
             "file" => %Plug.Upload{content_type: nil, filename: nil, path: nil}
           }

    conn = conn(:get, "/", a: "b", file: %{__struct__: "Foo"})
    assert conn.params == %{"a" => "b", "file" => %{"__struct__" => "Foo"}}
  end

  test "custom function params" do
    conn = conn(:get, "/", action: fn -> "this is fine" end)

    assert %{"action" => _action} = conn.params
    assert conn.params["action"].() == "this is fine"
  end

  test "no body or params" do
    conn = conn(:get, "/")
    {adapter, state} = conn.adapter
    assert conn.req_headers == []
    assert {:ok, "", _state} = adapter.read_req_body(state, length: 10)
  end

  test "no path" do
    conn = conn(:get, "http://www.elixir-lang.org")
    assert conn.path_info == []
  end

  test "custom params sets no content-type for GET/HEAD requests" do
    conn = conn(:head, "/")
    assert conn.req_headers == []
    conn = conn(:get, "/")
    assert conn.req_headers == []
    conn = conn(:get, "/", foo: "bar")
    assert conn.req_headers == []
  end

  test "custom params sets content-type to multipart/mixed when content-type is not set" do
    conn = conn(:post, "/", foo: "bar")
    assert conn.req_headers == [{"content-type", "multipart/mixed; boundary=plug_conn_test"}]
  end

  test "custom params does not change content-type when set" do
    conn =
      conn(:get, "/", foo: "bar")
      |> Plug.Conn.put_req_header("content-type", "application/vnd.api+json")
      |> Plug.Adapters.Test.Conn.conn(:get, "/", foo: "bar")

    assert conn.req_headers == [{"content-type", "application/vnd.api+json"}]
  end

  test "use existing conn.host if exists" do
    conn_with_host = conn(:get, "http://www.elixir-lang.org/")
    assert conn_with_host.host == "www.elixir-lang.org"

    child_conn = Plug.Adapters.Test.Conn.conn(conn_with_host, :get, "/getting-started/", nil)
    assert child_conn.host == "www.elixir-lang.org"
  end

  test "inform adds to the informational responses to the list" do
    conn =
      conn(:get, "/")
      |> Plug.Conn.inform(:early_hints, [{"link", "</style.css>; rel=preload; as=style"}])
      |> Plug.Conn.inform(:early_hints, [{"link", "</script.js>; rel=preload; as=script"}])

    informational_requests = Plug.Test.sent_informs(conn)

    assert {103, [{"link", "</style.css>; rel=preload; as=style"}]} in informational_requests
    assert {103, [{"link", "</script.js>; rel=preload; as=script"}]} in informational_requests
  end

  test "push adds to the pushes list" do
    conn =
      conn(:get, "/")
      |> Plug.Conn.push("/static/application.css", [{"accept", "text/css"}])
      |> Plug.Conn.push("/static/application.js", [{"accept", "application/javascript"}])

    pushes = Plug.Test.sent_pushes(conn)

    assert {"/static/application.css", [{"accept", "text/css"}]} in pushes
    assert {"/static/application.js", [{"accept", "application/javascript"}]} in pushes
  end

  test "full URL overrides existing conn.host" do
    conn_with_host = conn(:get, "http://www.elixir-lang.org/")
    assert conn_with_host.host == "www.elixir-lang.org"

    child_conn =
      Plug.Adapters.Test.Conn.conn(conn_with_host, :get, "http://www.example.org/", nil)

    assert child_conn.host == "www.example.org"
  end

  test "use existing conn.remote_ip if exists" do
    conn_with_remote_ip = %Plug.Conn{conn(:get, "/") | remote_ip: {151, 236, 219, 228}}
    child_conn = Plug.Adapters.Test.Conn.conn(conn_with_remote_ip, :get, "/", foo: "bar")
    assert child_conn.remote_ip == {151, 236, 219, 228}
  end

  test "use custom peer data" do
    peer_data = %{address: {127, 0, 0, 1}, port: 111_317}
    conn = conn(:get, "/") |> put_peer_data(peer_data)
    assert peer_data == Plug.Conn.get_peer_data(conn)
  end
end
