defmodule Clerk.HTTP do
  @domain "https://api.clerk.com"

  def get(url, params \\ %{}, opts \\ [], cast \\ __MODULE__.Response)

  def get(url, params, opts, cast) when is_struct(params) do
    params = omit_nil(params)

    get(url, params, opts, cast)
  end

  def get(url, params, opts, cast) do
    :get |> Finch.build(url(url, params), headers(opts)) |> request(cast)
  end

  defp omit_nil(struct) do
    struct
    |> Map.from_struct()
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Enum.into(%{})
  end

  def post(url, body, query_params \\ %{}, opts \\ [], cast \\ __MODULE__.Response) do
    :post
    |> Finch.build(url(url, query_params), headers(opts), Jason.encode!(body))
    |> request(cast)
  end

  def post_form(url, multipart, query_params \\ %{}, opts \\ []) do
    content_type = Multipart.content_type(multipart, "multipart/form-data")
    opts = Keyword.put(opts, :content_type, content_type)

    :post
    |> Finch.build(
      url(url, query_params),
      headers(opts),
      {:stream, Multipart.body_stream(multipart)}
    )
    |> request()
  end

  def put_form(url, multipart, query_params \\ %{}, opts \\ []) do
    content_type = Multipart.content_type(multipart, "multipart/form-data")
    opts = Keyword.put(opts, :content_type, content_type)

    :put
    |> Finch.build(
      url(url, query_params),
      headers(opts),
      {:stream, Multipart.body_stream(multipart)}
    )
    |> request()
  end

  def patch(url, body, query_params \\ %{}, opts \\ []) do
    :patch |> Finch.build(url(url, query_params), headers(opts), Jason.encode!(body)) |> request()
  end

  def put(url, body, query_params \\ %{}, opts \\ []) do
    :put |> Finch.build(url(url, query_params), headers(opts), Jason.encode!(body)) |> request()
  end

  def delete(url, query_params \\ %{}, opts \\ []) do
    :delete |> Finch.build(url(url, query_params), headers(opts)) |> request()
  end

  defp url(path, params) do
    # Normally arrays are encoded as foo[]=bar&foo[]=baz
    # but Clerk expects foo=bar&foo=baz so we need to flatten
    # the params list before encoding
    query =
      params
      |> Enum.flat_map(fn {k, v} ->
        if is_list(v) do
          Enum.map(v, fn x -> {k, x} end)
        else
          [{k, v}]
        end
      end)
      |> URI.encode_query()

    "#{@domain}#{path}?#{query}"
  end

  defp headers(opts) do
    headers = Keyword.get(opts, :headers, [])
    content_type = Keyword.get(opts, :content_type, "application/json")
    secret_key = Keyword.get(opts, :secret_key, Application.get_env(:clerk, :secret_key))

    headers ++
      [
        {"Content-Type", content_type},
        {"Authorization", "Bearer #{secret_key}"}
      ]
  end

  defp request(req, cast \\ __MODULE__.Response) do
    req |> Finch.request(ClerkHTTP) |> handle_response(cast)
  end

  defp handle_response({:ok, %Finch.Response{status: status, body: body}}, cast)
       when status in [200, 201] do
    body = Jason.decode!(body)
    {:ok, cast.new(body)}
  end

  defp handle_response({:ok, %Finch.Response{status: 204}}, _cast) do
    {:ok, nil}
  end

  defp handle_response({:ok, %Finch.Response{status: status, body: body}}, _cast)
       when status in [400, 401, 403, 404, 422] do
    {:error, Jason.decode!(body)}
  end
end
