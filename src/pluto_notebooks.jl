
"""
Given a selection of notebooks, check individually for each notebook if there are 
any cells that errored.
If it is the case print out, for each notebook, the content of the failing cells
and the output messages.
"""
function check_for_failed_notebooks(result::NamedTuple)
  failed_notebooks = Dict{String, Vector}()
  # notebook session is a `NotebookSession` from PlutoSliderServer.jl.
  for notebook_session in result.notebook_sessions
    # Check for every notebook that no cell errored.
    # State is a large JSON style `Dict` containing all the informations about the ran notebook.
    # You can find the definition in Pluto.jl/src/webserver/Dynamic.jl/notebook_to_js.
    state = notebook_session.run.original_state
    errored_cells = findall(cell -> cell["errored"], state["cell_results"])
    isempty(errored_cells) && continue
    failed_notebooks[notebook_session.path] =
      map(sort(errored_cells; by = id -> findfirst(==(id), state["cell_order"]))) do id
        input = state["cell_inputs"][id]["code"]
        body = state["cell_results"][id]["output"]["body"]
        output =
          haskey(body, :msg) ? body[:msg] :
          haskey(body, "msg") ? body["msg"] :
          error(
            "the notebook structure changed and the cell output is not reachable, this might be due to a new Pluto version.",
          )
        (; input, output)
      end
  end
  if !isempty(failed_notebooks)
    io = IOBuffer()
    for (key, cells) in pairs(failed_notebooks)
      printstyled(IOContext(io, :color => true), "$key:\n"; bold = true, color = :green, underline = true)
      for (input, output) in cells
        printstyled(IOContext(io, :color => true), "• $input"; color = :blue)
        print(io, " => ")
        printstyled(IOContext(io, :color => true), "$output\n"; color = :red)
      end
      println(io)
    end
    error_msgs = String(take!(io))
    error(
      "The following Pluto notebook",
      length(failed_notebooks) > 1 ? "s" : "",
      " failed to run successfully: $(keys(failed_notebooks))\n\n",
      error_msgs,
    )
  end
end

"""
Based on a list of html pages (built from PlutoSliderServer), create markdown 
files compatible with Documenter.jl encapsulating the notebooks into an
<iframe>
"""
function build_notebook_md(
  md_outdir::AbstractString,
  html_dir::AbstractString,
  jl_dir::AbstractString,
  ismaster::Bool = is_mainCI(),
)
  mkpath(md_outdir) # create directory if not existing
  # For each html file produced, make a .md file for Documenter which will 
  # encapsulate the html file. This should be seen as a workaround
  path_to_html = joinpath(ismaster ? ".." : "", relpath(html_dir, md_outdir))
  mapreduce(vcat, walkdir(html_dir)) do (path, _, files)
    subpath = relpath(path, html_dir) # The subfolder structure
    depth = subpath == "." ? 0 : length(splitpath(subpath)) # We need the depth to get the relative path of subfolder notebooks.
    md_subpath = normpath(joinpath(md_outdir, subpath)) # The output folder for the md file
    mkpath(md_subpath) # Build the dir when needed
    map(filter!(f -> endswith(f, ".html") && has_matching_jl(f, jl_dir, subpath), files)) do f
      html_file = joinpath(path, f)
      add_base_target!(html_file)
      author, date = get_last_author_date(matching_jl(f, jl_dir, subpath))
      file_path = joinpath(md_subpath, strip_extension(f) * ".md")
      open(file_path, "w") do io
        # Fake an inside HTML page in documenter.
        write(
          io,
          """# $(strip_extension(f))

```@raw html
<script src="https://cdnjs.cloudflare.com/ajax/libs/iframe-resizer/4.3.2/iframeResizer.min.js" integrity="sha512-dnvR4Aebv5bAtJxDunq3eE8puKAJrY9GBJYl9GC6lTOEC76s1dbDfJFcL9GyzpaDW4vlI/UjR8sKbc1j6Ynx6w==" crossorigin="anonymous" referrerpolicy="no-referrer"></script>
<iframe id="pluto_notebook" width="100%" title="Pluto Notebook" src="$(normpath(joinpath(fill("..", depth)..., path_to_html, subpath, f)))"></iframe>
<script>
  document.addEventListener('DOMContentLoaded', function(){
    var myIframe = document.getElementById("pluto_notebook");
    iFrameResize({log:false}, myIframe);
});
</script>
```
""" |> add_author_data(author, date),
        )
      end
      file_path
    end
  end
end

"""
Add `<base target="_blank">` in the `<head>` of the html file.
"""
function add_base_target!(file::AbstractString)
  lines = readlines(file)
  open(file, "w") do io
    for line in lines
      println(io, line)
      if !isnothing(match(r"<head>", line))
        println(io, """<base target="_blank">""")
      end
    end
  end
end

function update_notebooks_versions(dir::String; backup::Bool = false, recursive::Bool = true)
  notebook_paths = get_pluto_notebook_paths(dir; recursive)
  for notebook in notebook_paths
    @info "Updating packages in $(notebook)"
    PlutoSliderServer.Pluto.update_notebook_environment(joinpath(dir, notebook); backup)
    @info "Updating of $(notebook) done\n"
  end
end
