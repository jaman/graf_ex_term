defmodule GrafExTerm.Entry do
  @moduledoc """
  Task that launches the terminal UI and halts the VM when it exits.

  Started by `GrafExTerm.Application` only in a packaged release, where the
  BEAM has no other reason to keep running once the UI is closed. Both a
  clean exit and a crash call `System.halt/1` — with status 0 and 1
  respectively — so the process never returns to its supervisor and
  `restart: :temporary` is what the supervisor sees.

  Diagnostics, including the resolution and load of Drafter's termios NIF, are
  appended to `/tmp/graf_ex_term_debug.log`.
  """

  use Task, restart: :temporary

  @debug_log "/tmp/graf_ex_term_debug.log"

  @doc """
  Starts the UI task and returns immediately.

  `opts` is forwarded to `GrafExTerm.run/1`. Also probes and loads the Drafter
  termios NIF, logging what it found.
  """
  @spec start_link(keyword()) :: {:ok, pid()}
  def start_link(opts) do
    debug("Entry.start_link called")
    diagnose_nif()
    Task.start_link(__MODULE__, :run, [opts])
  end

  @doc """
  Runs the terminal UI and halts the VM when it finishes.

  `opts` is forwarded to `GrafExTerm.run/1`. Never returns: the VM exits with
  status 0 when the user quits normally and 1 when the UI raises or throws,
  after appending the reason to the debug log.
  """
  @spec run(keyword()) :: no_return()
  def run(opts) do
    debug("Entry.run called, launching TUI")
    GrafExTerm.run(opts)
    debug("Entry.run TUI exited normally")
    System.halt(0)
  rescue
    error ->
      debug(
        "Entry crashed: #{Exception.message(error)}\n#{Exception.format(:error, error, __STACKTRACE__)}"
      )

      System.halt(1)
  catch
    kind, reason ->
      debug("Entry caught #{kind}: #{inspect(reason)}")
      System.halt(1)
  end

  defp diagnose_nif do
    priv_dir = :code.priv_dir(:drafter) |> to_string()
    debug("drafter priv_dir: #{priv_dir}")

    nif_path = Path.join(priv_dir, "termios_nif.so")
    debug("NIF file exists? #{File.exists?(nif_path)}")

    nif_load_path = :filename.join(:code.priv_dir(:drafter), ~c"termios_nif")
    load_result = :erlang.load_nif(nif_load_path, 0)
    debug("load_nif result: #{inspect(load_result)}")

    file_info = File.stat(nif_path)
    debug("NIF file stat: #{inspect(file_info)}")

    {file_output, _} = System.cmd("file", [nif_path], stderr_to_stdout: true)
    debug("NIF file type: #{String.trim(file_output)}")
  end

  defp debug(msg) do
    File.write!(@debug_log, "#{DateTime.utc_now()} #{msg}\n", [:append])
  end
end
