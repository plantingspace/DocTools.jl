
"""
Given a selection of notebooks, check individually for each notebook if there are 
any cells that errored.
If it is the case print out, for each notebook, the content of the failing cells
and the output messages.
"""
function check_for_failed_notebooks(result::NamedTuple)
    failed_notebooks = Dict{String,Vector}()
    for notebook in result.notebook_sessions
      # check for every notebook that no cell errored
      state = notebook.run.original_state
      errored_cells = findall(cell -> cell["errored"], state["cell_results"])
      isempty(errored_cells) && continue
      failed_notebooks[notebook.path] = [
        (input = state["cell_inputs"][id]["code"], output = state["cell_results"][id]["output"]["body"][:msg]) for
        id in errored_cells
      ]
    end
    if !isempty(failed_notebooks)
      error_msgs = ""
      for (key, cells) in pairs(failed_notebooks)
        error_msgs *= "$key:\n"
        for (input, output) in cells
          error_msgs *= "\t$input => $output\n"
        end
        error_msgs *= "\n"
      end
      error("The following Pluto notebooks failed to run successfully: $(keys(failed_notebooks))\n\n", error_msgs)
    end
  end

"""
Based on a list of html pages (built from PlutoSliderServer), create markdown 
files compatible with Documenter.jl encapsulating the notebooks into an
<iframe>
"""
function build_notebook_md(md_outdir::AbstractString, html_dir::AbstractString)
  mkpath(md_outdir) # create directory if not existing
  # For each html file produced, make a .md file for Documenter which will 
  # encapsulate the html file. This should be seen as a workaround
  map(filter!(endswith(".html"), readdir(html_dir))) do f
    file_path = joinpath(md_outdir, strip_extension(f) * ".md")
    open(file_path, "w") do io
      # Fake an inside HTML page in documenter
      write(
        io,
        """# $(strip_extension(f))

```@raw html
<script src="https://cdnjs.cloudflare.com/ajax/libs/iframe-resizer/4.3.2/iframeResizer.min.js" integrity="sha512-dnvR4Aebv5bAtJxDunq3eE8puKAJrY9GBJYl9GC6lTOEC76s1dbDfJFcL9GyzpaDW4vlI/UjR8sKbc1j6Ynx6w==" crossorigin="anonymous" referrerpolicy="no-referrer"></script>
<iframe id="pluto_notebook" width="100%" title="Pluto Notebook" src="$(joinpath(html_dir, f))"></iframe>
<script>
  document.addEventListener('DOMContentLoaded', function(){
    var myIframe = document.getElementById("pluto_notebook");
    iFrameResize({log:false}, myIframe);
});
</script>
```
""",
      )
    end
    file_path
  end
end
