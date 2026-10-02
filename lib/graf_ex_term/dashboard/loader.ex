defmodule GrafExTerm.Dashboard.Loader do
  @moduledoc """
  Fetches raw Grafana dashboard JSON from a URI.

  Produces the decoded JSON map only; turning it into structs is
  `GrafExTerm.Dashboard.Parser`'s job.

      GrafExTerm.Dashboard.Loader.load("file:///etc/dashboards/node.json")
  """

  @doc """
  Reads and decodes the dashboard at `uri`.

  Two schemes are recognised:

    * `file://` followed by an absolute path — read from disk
    * `http://` or `https://` — fetched with `Req.get/1`, and the response
      body must already be a decoded map

  Returns `{:ok, map}` on success. Failures are `{:error, reason}`:
  `{:unsupported_scheme, uri}` for any other scheme, a `File` posix atom or a
  `Jason.DecodeError` for local reads, `{:unexpected_body, body}` when an HTTP
  response carries something other than a map, and the transport error
  otherwise.

  The returned map is whatever the source contained; it may be a bare
  dashboard or one wrapped under a `"dashboard"` key, and the parser accepts
  either.
  """
  @spec load(String.t()) :: {:ok, map()} | {:error, term()}
  def load("file://" <> path) do
    with {:ok, body} <- File.read(path) do
      Jason.decode(body)
    end
  end

  def load("http" <> _ = url) do
    with {:ok, response} <- Req.get(url),
         body when is_map(body) <- response.body do
      {:ok, body}
    else
      {:ok, response} -> {:error, {:unexpected_body, response.body}}
      {:error, reason} -> {:error, reason}
      other -> {:error, {:unexpected, other}}
    end
  end

  def load(uri), do: {:error, {:unsupported_scheme, uri}}
end
