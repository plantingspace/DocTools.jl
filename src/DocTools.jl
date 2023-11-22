module DocTools

using Dates
using Documenter
using Literate
using Pkg
using PlutoSliderServer
using PlutoSliderServer.Pluto: is_pluto_notebook

export build_pluto, build_literate, default_makedocs, is_mainCI, update_notebooks_versions

include("smart_filters.jl")
include("pluto_notebooks.jl")

"Remove the last extension from a filename, e.g. `index.html` -> `index`"
strip_extension(s::AbstractString) = s[1:(findlast(==('.'), s) - 1)]

"Detect if the current run is on master/main or on a MR"
is_mainCI()::Bool =
  get(ENV, "CI", nothing) == "true" && !(haskey(ENV, "CI_MERGE_REQUEST_ID"))

@deprecate is_masterCI is_mainCI
"""
Build notebooks using PlutoSliderServer and create Markdown file containing them
in an iframe.
It returns the list of the paths of the created markdown pages.

## Arguments
- `pkg/root`: The module containing the docs or the absolute path of the directory root.
- `notebooks_path`: The path of the notebooks. If this is a relative path, it will be taken as relative to the root of the module.

## Keyword Arguments
- `run`: Whether to run the notebooks or not.
- `src_dir`: The source directory of the docs (default is "docs/src").
- `md_dir`: The output directory for the Markdown files (default is "docs/src/notebooks").
- `html_dir`: The output directory for the HTML files (default is "docs/src/assets/notebooks").
- `exclude_list`: Array of files to exclude from the rendering.
- `recursive`: Also treats the subfolder (and return the same structure).
- `activate_folder`: Activate the environment of the folder containing the notebooks.
- `smart_filter`: Decide which notebooks to run based on changes (direct change or change `src/`).
- `use_cache`: Use the caching function of `PlutoSliderServer`.
"""
function build_pluto(
  mod::Module,
  notebooks_dir::String,
  root::String = pkgdir(mod);
  run::Bool = true, # This is currently always true
  src_dir::String = joinpath(root, "docs", "src"),
  md_dir::String = joinpath(src_dir, "notebooks"),
  html_dir::String = joinpath(src_dir, "assets", "notebooks"),
  exclude_list::AbstractVector{<:String} = String[],
  recursive::Bool = true,
  activate_folder::Bool = true,
  smart_filter::Bool = true,
  use_cache::Bool = false,
)::Vector{String}
  run || return String[]
  if !isabspath(notebooks_dir)
    notebooks_dir = joinpath(root, notebooks_dir)
  end
  # Create folders if they do not exist already
  mkpath(md_dir)
  mkpath(html_dir)
  # Paths to each notebook, relative to notebook directory.
  notebook_paths = get_pluto_notebook_paths(notebooks_dir; recursive)
  modified_files = list_modified()
  modified_notebooks = map(x -> relpath(x, notebooks_dir), filter(startswith(notebooks_dir), modified_files))
  pkg_modified = is_pkg_modified(modified_files)
  if !is_mainCI() && smart_filter
    foreach(notebook_paths) do path
      # To not be excluded: the notebook must be modified or there was a change in the src package and the notebook depends on it.
      if !(path ∈ modified_notebooks || (pkg_modified && is_pkg_dependent(joinpath(notebooks_dir, path), repr(mod))))
        @info "Skipping notebook $path"
        push!(exclude_list, path)
      end
    end
  end
  # PlutoSliderServer automatically detect which files are Pluto notebooks,
  # we just give it a directory to explore.
  # But first we preinstantiate the workbench directory.
  curr_env = dirname(Pkg.project().path)
  try
    if activate_folder
      Pkg.activate(notebooks_dir)
      Pkg.instantiate()
    end
    t = @elapsed if use_cache
      PlutoSliderServer.export_directory(
        notebooks_dir;
        Export_create_index = false,
        Export_output_dir = html_dir,
        Export_cache_dir = joinpath(html_dir, "cache"),
        Export_baked_state = false,
        Export_baked_notebookfile = false,
        Export_offer_binder = false,
        Export_exclude = exclude_list,
        on_ready = check_for_failed_notebooks,
        notebook_paths,
      )
    else
      PlutoSliderServer.export_directory(
        notebooks_dir;
        Export_create_index = false,
        Export_output_dir = html_dir,
        Export_exclude = exclude_list,
        on_ready = check_for_failed_notebooks,
        notebook_paths,
      )
    end
    @info "Running the Pluto notebooks took $(t)s"
    build_notebook_md(md_dir, html_dir, notebooks_dir)
  finally
    if activate_folder
      Pkg.activate(curr_env)
    end
  end
end

function get_pluto_notebook_paths(dir::String; recursive::Bool = true)
  if recursive
    sort(PlutoSliderServer.find_notebook_files_recursive(dir))
  else
    String[file for file in readdir(dir) if is_pluto_notebook(joinpath(dir, file))]
  end
end

"Curried function to check if a path contain the given string in its parents folder"
has_parent(parent::String) = path -> has_parent(path, parent)
has_parent(path::String, parent::String) = parent in splitpath(path)

"""
Builds notebooks using the literate format and returns the list of the output files.

## Arguments
- `pkg/root`: The module containing the docs or the absolute path of the directory root.
- `literate_path`: The relative path of the notebooks relative to the root of the module.

## Keyword Arguments
- `run`: Whether to run the notebooks or not.
- `src_dir`: The source directory of the docs (default is "docs/src").
- `md_dir`: The output directory for the Markdown files (default is "docs/src/notebooks").
- `activate_folder`: Whether to activate the environment of the folder containing the notebooks.
"""
function build_literate(
  mod::Module,
  literate_path::String,
  root::String = pkgdir(mod);
  run::Bool = true,
  src_dir::String = joinpath(root, "docs", "src"),
  md_dir::String = joinpath(src_dir, "notebooks"),
  exclude_list::AbstractVector{<:String} = String[],
  recursive::Bool = true,
  activate_folder::Bool = true,
  smart_filter::Bool = true,
  use_cache::Bool = false,
)::Vector{String}
  run || return String[]
  if !isabspath(literate_path)
    literate_path = joinpath(root, literate_path)
  end
  curr_env = dirname(Pkg.project().path)
  dir_parser = recursive ? walkdir : list_dir
  modified_files = list_modified()
  modified_literate = filter(startswith(literate_path), modified_files) # Get list of modified files in the `literate_path` dir.
  pkg_modified = is_pkg_modified(modified_files)
  try
    if activate_folder
      Pkg.activate(literate_path)
      Pkg.instantiate()
    end
    mapreduce(vcat, dir_parser(literate_path); init = String[]) do (path, _, _)
      md_subpath = normpath(joinpath(md_dir, relpath(path, literate_path)))
      filtered_list = filter!(readdir(path; join = true)) do file
        out = endswith(file, ".jl") && file ∉ exclude_list # Basic check
        if smart_filter
          out &= is_mainCI() || file ∈ modified_literate || (pkg_modified && is_pkg_dependent(file, repr(mod)))
          if !out && endswith(file, ".jl")
            @info "Skipping literate file $file"
          end
        end
        out
      end
      map(filtered_list) do file
        author, date = get_last_author_date(file)
        source_hash = readchomp(`md5sum $(file)`)
        if use_cache
          filepath = joinpath(md_subpath, strip_extension(basename(file)) * ".md")
          prev_source_hash = get_sourcefile_hash(filepath)
          if prev_source_hash == source_hash
            @info "$file already rendered in cache, skipping"
            return filepath
          end
        end
        t = @elapsed path = Literate.markdown(
          file,
          md_subpath;
          flavor = Literate.DocumenterFlavor(),
          execute = true,
          postprocess = append_hash(source_hash) ∘ add_author_data(author, date),
        )::String
        @info "Evaluated literate file in $(t)s"
        path
      end
    end
  finally
    if activate_folder
      Pkg.activate(curr_env)
    end
  end
end

function list_dir(path::String)
  ((path, String[], String[]),)
end

function get_sourcefile_hash(filepath)
  if isfile(filepath)
    hash_lines = filter(x -> !isnothing(match(r"Source file hash: (.*)", x)), readlines(filepath))
    if isempty(hash_lines)
      @info "Could not find a hash in $(filepath)."
      return ""
    elseif length(hash_lines) > 1
      @info "$(filepath) seems to have multiple hashes written down, it will be rerendered."
      return ""
    else
      hashes = match(r"Source file hash: (.*)", only(hash_lines))
      return only(hashes)
    end
  else
    @info "Did not find markdown file $(filepath)"
    return ""
  end
end

function append_hash(file_hash)
  function append_hash(str)
    str *
    "Source file hash: $(file_hash)"
  end
end

function get_last_author_date(file::String)
  pretty = "format:%an (%ae)\n%as"
  author, date = readlines(`git log -n 1 --pretty=$(pretty) -- $(file)`)
  date = Date(date)
  author, "$(monthname(date)) $(day(date)), $(year(date))"
end

function add_author_data(author, date)
  function process_str(str)
    "!!! info\n" *
    "    This file was last modified on $(date), by $(author).\n\n" * str
  end
end

"""
Default call to Documenter.makedocs, gives some default keyword arguments,
and make some internals like `macros` more accessible.

## Keyword Arguments
- `macros`: `Dict` of LaTeX "\\newcommand". For example `\\newcommand{\\Lc}{\\mathcal{L}}` 
is written as `:Lc => ["\\mathcal{L}"]`, and `\\newcommand{\\bf}{\\mathsymbol{#1}}` is 
written as `:bf => ["\\bf{#1}", 1]`.
- `prettify`: Adapt the URL if the run is local, on CI master or CI MR.
- `notebooks`: File list of rendered notebooks.
- `pages`: The usual `pages` argument from `makedocs`
"""
function default_makedocs(;
  macros::Dict{Symbol, <:AbstractVector} = Dict{Symbol, Vector}(),
  prettify::Bool = is_mainCI(),
  notebooks::AbstractVector = String[],
  notebook_path::String = "notebooks",
  pages::AbstractVector{<:Pair{String, <:Any}} = Pair{String, Any}[],
  repo::Union{Nothing, AbstractString} = nothing,
  size_threshold::Union{Nothing, Integer} = nothing, # Is normally 200 * 2^10
  kwargs...,
)
  mathengine = Documenter.MathJax2(Dict(:TeX => Dict(:Macros => macros)))
  notebook_pages = if isempty(notebooks)
    []
  else
    "Notebooks" => rework_paths(notebooks, notebook_path)
  end
  if isnothing(repo)
    kwargs = (; kwargs..., remotes = nothing)
    repo = ""
  else
    repo = Remotes.GitLab(repo)
  end
  makedocs(;
    format = Documenter.HTML(; prettyurls = prettify, mathengine, size_threshold),
    pages = [pages; notebook_pages],
    repo,
    kwargs...,
  )
end

function rework_paths(paths::AbstractVector{<:String}, notebook_path::String)
  top_dir = Dict{String, Any}()
  map(paths) do f
    dirs_file = splitpath(f)
    pos = findfirst(==(notebook_path), dirs_file)
    isnothing(pos) && error("$(notebook_path) could not be found in the path $(f)")
    sub_dirs = dirs_file[(pos + 1):(end - 1)] # Get the relpath of the file
    i = 1
    d = top_dir # We start at the root
    while true
      iter = iterate(sub_dirs, i)
      if isnothing(iter)
        push!(get!(Vector{String}, d, "files"), joinpath(dirs_file[pos:end]...))
        return
      else
        d = get!(Dict{String, Any}, d, first(iter)) # Create a new dict for a dir if it doesn't exist
      end
      i += 1
    end
  end
  dict_to_pairs(top_dir)
end

function dict_to_pairs(d::Dict)
  mapreduce(vcat, pairs(d)) do (key, val)
    if key == "files"
      val
    else
      [key => dict_to_pairs(val)]
    end
  end
end

end
