defmodule SymphonyElixir.P2E.Client do
  @moduledoc """
  Thin P2E REST client for the tracker surface.
  """

  require Logger

  alias SymphonyElixir.Config

  @default_limit 100
  @token_scope "tracker:read tracker:write"
  @json_headers [{"Content-Type", "application/json"}]
  @form_headers [{"Content-Type", "application/x-www-form-urlencoded"}]

  @type request_fun ::
          (atom(), String.t(), keyword() -> {:ok, %{status: integer(), body: term()}} | {:error, term()})

  @spec list_stories(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_stories(product_slug, opts \\ []) when is_binary(product_slug) and is_list(opts) do
    query =
      opts
      |> list_query()
      |> URI.encode_query()

    product_slug
    |> path_join(["products", product_slug, "stories"])
    |> with_query(query)
    |> authed_request(:get, opts)
    |> case do
      {:ok, %{"data" => stories}} when is_list(stories) -> {:ok, stories}
      {:ok, _body} -> {:error, :p2e_unexpected_list_payload}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec get_story(String.t()) :: {:ok, map()} | {:error, term()}
  def get_story(story_id), do: get_story(story_id, [])

  @spec get_story(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_story(story_id, opts) when is_binary(story_id) and is_list(opts) do
    story_id
    |> path_join(["stories", story_id])
    |> authed_request(:get, opts)
    |> case do
      {:ok, %{"story" => story}} when is_map(story) -> {:ok, story}
      {:ok, _body} -> {:error, :p2e_unexpected_story_payload}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec transition(String.t(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def transition(story_id, state_name, reason), do: transition(story_id, state_name, reason, [])

  @spec transition(String.t(), String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def transition(story_id, state_name, reason, opts)
      when is_binary(story_id) and is_binary(state_name) and is_binary(reason) and is_list(opts) do
    story_id
    |> path_join(["stories", story_id, "transitions"])
    |> authed_request(:post, opts,
      json: %{to: state_name, actor: "symphony", reason: reason},
      headers: @json_headers
    )
  end

  @spec append_log(String.t(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def append_log(story_id, kind, message), do: append_log(story_id, kind, message, [])

  @spec append_log(String.t(), String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def append_log(story_id, kind, message, opts)
      when is_binary(story_id) and is_binary(kind) and is_binary(message) and is_list(opts) do
    story_id
    |> path_join(["stories", story_id, "log"])
    |> authed_request(:post, opts,
      json: %{kind: kind, message: message},
      headers: @json_headers
    )
  end

  defp list_query(opts) do
    statuses =
      opts
      |> Keyword.get(:statuses, [])
      |> Enum.map(&to_string/1)
      |> Enum.reject(&(&1 == ""))

    status_params = Enum.map(statuses, &{"statuses[]", &1})
    limit = opts |> Keyword.get(:limit, @default_limit) |> to_string()
    cursor = Keyword.get(opts, :cursor)

    status_params
    |> Kernel.++([{"limit", limit}])
    |> maybe_append_cursor(cursor)
  end

  defp maybe_append_cursor(params, cursor) when is_binary(cursor) and cursor != "",
    do: params ++ [{"cursor", cursor}]

  defp maybe_append_cursor(params, _cursor), do: params

  defp authed_request(url, method, opts, request_opts \\ []) do
    with {:ok, token} <- bearer_token(opts),
         request_opts <- merge_headers(request_opts, [{"Authorization", "Bearer #{token}"}]),
         {:ok, response} <- request(method, url, request_opts, opts) do
      decode_response(response, method, url)
    end
  end

  defp bearer_token(opts) do
    case Keyword.get(opts, :api_key) || Config.settings!().tracker.api_key do
      token when is_binary(token) and token != "" ->
        {:ok, token}

      _ ->
        fetch_access_token(opts)
    end
  end

  defp fetch_access_token(opts) do
    tracker = Config.settings!().tracker

    with client_id when is_binary(client_id) <- tracker.client_id,
         client_secret when is_binary(client_secret) <- tracker.client_secret,
         token_endpoint <- token_endpoint(),
         body <- URI.encode_query(%{grant_type: "client_credentials", scope: @token_scope}),
         headers <- basic_auth_headers(client_id, client_secret) ++ @form_headers,
         {:ok, response} <-
           request(:post, token_endpoint, [headers: headers, body: body], opts),
         {:ok, %{"access_token" => token}} when is_binary(token) <-
           decode_response(response, :post, token_endpoint) do
      {:ok, token}
    else
      nil -> {:error, :missing_p2e_auth}
      {:ok, _body} -> {:error, :p2e_unexpected_token_payload}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :missing_p2e_auth}
    end
  end

  defp basic_auth_headers(client_id, client_secret) do
    encoded = Base.encode64("#{client_id}:#{client_secret}")
    [{"Authorization", "Basic #{encoded}"}]
  end

  defp request(method, url, request_opts, opts) do
    request_fun = Keyword.get(opts, :request_fun, &req_request/3)
    request_fun.(method, url, request_opts)
  end

  defp req_request(method, url, request_opts) do
    request_opts
    |> Keyword.put(:method, method)
    |> Keyword.put(:url, url)
    |> Req.request()
  end

  defp decode_response(%{status: status, body: body}, _method, _url) when status in 200..299 do
    decode_body(body)
  end

  defp decode_response(%{status: status, body: body}, method, url) do
    Logger.error("P2E REST request failed method=#{method} url=#{url} status=#{status} body=#{summarize_body(body)}")
    {:error, {:p2e_api_status, status}}
  end

  defp decode_body(body) when is_map(body), do: {:ok, body}

  defp decode_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
      {:ok, _decoded} -> {:error, :p2e_unexpected_json_payload}
      {:error, reason} -> {:error, {:p2e_json_decode, reason}}
    end
  end

  defp decode_body(_body), do: {:error, :p2e_unexpected_response_body}

  defp summarize_body(body) when is_binary(body) do
    body
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, 1_000)
    |> inspect()
  end

  defp summarize_body(body), do: inspect(body, limit: 20, printable_limit: 1_000)

  defp merge_headers(request_opts, headers) do
    Keyword.update(request_opts, :headers, headers, fn existing -> existing ++ headers end)
  end

  defp path_join(_value, segments) do
    segments =
      Enum.map(segments, fn segment ->
        segment
        |> to_string()
        |> URI.encode(&URI.char_unreserved?/1)
      end)

    api_base_url() <> "/" <> Enum.join(segments, "/")
  end

  defp with_query(url, ""), do: url
  defp with_query(url, query), do: url <> "?" <> query

  defp api_base_url do
    endpoint = base_endpoint()

    if String.ends_with?(endpoint, "/api/v1") do
      endpoint
    else
      endpoint <> "/api/v1"
    end
  end

  defp token_endpoint do
    case Config.settings!().tracker.token_endpoint do
      endpoint when is_binary(endpoint) and endpoint != "" ->
        endpoint

      _ ->
        base_endpoint()
        |> String.replace_suffix("/api/v1", "")
        |> Kernel.<>("/api/better-auth/mcp/token")
    end
  end

  defp base_endpoint do
    Config.settings!().tracker.endpoint
    |> to_string()
    |> String.trim()
    |> String.trim_trailing("/")
  end
end
