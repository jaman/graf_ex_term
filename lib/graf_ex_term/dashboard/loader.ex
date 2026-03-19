defmodule GrafExTerm.Dashboard.Loader do
  def load("file://" <> path) do
    with {:ok, body} <- File.read(path),
         {:ok, raw} <- Jason.decode(body) do
      {:ok, raw}
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
