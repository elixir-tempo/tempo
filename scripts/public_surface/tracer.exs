# A compile tracer that records every call to a function of a Tempo module,
# with the module, the function and the line it is made from. Used by
# `scripts/public_surface/run.sh`; it writes to the file `SURFACE_CALLS` names.
defmodule PublicSurface.Tracer do
  @remote [:remote_function, :imported_function, :remote_macro, :imported_macro]
  @local [:local_function, :local_macro]

  def trace({kind, meta, module, name, arity}, env) when kind in @remote do
    note(module, name, arity, env, meta)
  end

  def trace({kind, meta, name, arity}, env) when kind in @local do
    note(env.module, name, arity, env, meta)
  end

  def trace(_event, _env) do
    :ok
  end

  defp note(module, name, arity, env, meta) do
    if tempo?(module) do
      {caller, caller_arity} = env.function || {:"(module body)", 0}
      site = "#{Path.relative_to_cwd(env.file)}:#{Keyword.get(meta, :line, 0)}"

      fields = [
        inspect(module),
        name,
        arity,
        inspect(env.module),
        "#{caller}/#{caller_arity}",
        site
      ]

      File.write!(System.fetch_env!("SURFACE_CALLS"), Enum.join(fields, "\t") <> "\n", [:append])
    end

    :ok
  end

  defp tempo?(module) do
    case Atom.to_string(module) do
      "Elixir.Tempo" -> true
      "Elixir.Tempo." <> _rest -> true
      "Elixir.Enumerable.Tempo" <> _rest -> true
      "Elixir.Inspect.Tempo" <> _rest -> true
      "Elixir.String.Chars.Tempo" <> _rest -> true
      _other -> false
    end
  end
end
