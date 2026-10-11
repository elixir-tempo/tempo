# Every function and macro a module under lib/ exports, with how its module
# and it are documented. Used by `scripts/public_surface/run.sh`; it writes to
# the file `SURFACE_EXPORTS` names.
status = fn
  :hidden -> "hidden"
  :none -> "none"
  %{} -> "documented"
end

# The callbacks of the behaviours and the protocol a module implements:
# functions a caller of the behaviour calls, which no caller names.
callbacks = fn module ->
  for behaviour <-
        module.module_info(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten(),
      Code.ensure_loaded?(behaviour),
      function_exported?(behaviour, :behaviour_info, 1),
      callback <- behaviour.behaviour_info(:callbacks),
      do: callback
end

rows =
  for module <- Application.spec(:ex_tempo, :modules),
      source =
        module.module_info(:compile)[:source]
        |> to_string()
        |> Path.relative_to_cwd(),
      String.starts_with?(source, "lib/"),
      {:docs_v1, _anno, _language, _format, moduledoc, _meta, docs} = Code.fetch_docs(module),
      implemented = callbacks.(module),
      {{kind, name, arity}, _anno, _signature, doc, meta} <- docs,
      kind in [:function, :macro] do
    Enum.join(
      [
        source,
        inspect(module),
        status.(moduledoc),
        kind,
        name,
        arity,
        Map.get(meta, :defaults, 0),
        status.(doc),
        {name, arity} in implemented
      ],
      "\t"
    )
  end

File.write!(System.fetch_env!("SURFACE_EXPORTS"), Enum.join(Enum.sort(rows), "\n") <> "\n")
