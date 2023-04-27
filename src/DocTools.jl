module DocTools

using Dates
using Documenter
using Git: git
using Literate
using Pkg
using PlutoSliderServer
using PlutoSliderServer.Pluto: is_pluto_notebook

export build_pluto, build_literate, default_makedocs, is_masterCI

include("smart_filters.jl")
include("pluto_notebooks.jl")

"Remove the last extension from a filename, e.g. `index.html` -> `index`"
strip_extension(s::AbstractString) = s[1:(findlast(==('.'), s) - 1)]

"Detect if the current run is on master/main or on a MR"
is_masterCI()::Bool = get(ENV, "CI", nothing) == "true" && !(haskey(ENV, "CI_MERGE_REQUEST_ID"))

"""
Build notebooks using PlutoSliderServer and create Markdown file containing them
in an iframe.
It returns the list of the paths of the created markdown pages.

## Arguments
- `pkg/root`: The module containing the docs or the absolute path of the directory root.
- `notebooks_path`: The relative path of the notebooks relative to the root of the module.

## Keyword Arguments
- `run`: Whether to run the notebooks or not.
- `src_dir`: The source directory of the docs (default is "docs/src").
- `md_dir`: The output directory for the Markdown files (default is "docs/src/notebooks").
- `html_dir`: The output directory for the HTML files (default is "docs/src/assets/notebooks").
- `exclude_list`: Array of files to exclude from the rendering.
- `recursive`: Also treats the subfolder (and return the same structure).
- `activate_folder`: Activate the environment of the folder containing the notebooks.
"""
function build_pluto(
    mod::Module,
    notebooks_dir::String,
    root::String=pkgdir(mod);
    run::Bool=true, # This is currently always true
    src_dir::String=joinpath(root, "docs", "src"),
    md_dir::String=joinpath(src_dir, "notebooks"),
    html_dir::String=joinpath(src_dir, "assets", "notebooks"),
    exclude_list::AbstractVector{<:String}=String[],
    recursive::Bool=true,
    activate_folder::Bool=true,
    smart_filter::Bool=true,
    )
    run || return String[]
    # Create folders if they do not exist already
    mkpath(md_dir)
    mkpath(html_dir)
    # Path to the notebook directory.
    notebooks_path = joinpath(root, notebooks_dir)
    # Paths to each notebook, relative to notebook directory.
    notebook_paths = if recursive
        PlutoSliderServer.find_notebook_files_recursive(notebooks_dir)
    else
        String[file for file in readdir(notebooks_path, sort=false) if is_pluto_notebook(joinpath(notebooks_path, file))]
    end
    modified_notebooks = map(x->relpath(x, notebooks_dir), filter!(startswith(notebooks_dir), list_modified()))
    if !is_masterCI() && smart_filter
        foreach(notebook_paths) do path
            if path ∉ modified_notebooks && !is_pkg_dependent(joinpath(notebooks_path, path), repr(mod))
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
        PlutoSliderServer.export_directory(
            notebooks_dir;
            Export_create_index = false,
            Export_output_dir = html_dir,
            Export_exclude = exclude_list,
            on_ready = check_for_failed_notebooks,
            notebook_paths
        )
        build_notebook_md(md_dir, html_dir, notebooks_dir)
    finally
        if activate_folder
            Pkg.activate(curr_env)
        end
    end
end

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
    root::String=pkgdir(mod);
    run::Bool=true,
    src_dir::String=joinpath(root, "docs", "src"),
    md_dir::String=joinpath(src_dir, "notebooks"),
    exclude_list::AbstractVector{<:String}=String[],
    recursive::Bool=true,
    activate_folder::Bool=true,
    smart_filter::Bool=true,
)
    run || return String[]
    curr_env = dirname(Pkg.project().path)
    dir_parser = recursive ? walkdir : list_dir
    modified_files = joinpath.(root, filter!(startswith(literate_path), list_modified())) # Get list of modified files in the `literate_path` dir. 
    try
        literate_folder = joinpath(root, literate_path)
        if activate_folder
            Pkg.activate(literate_folder)
            Pkg.instantiate()
        end
        mapreduce(vcat, dir_parser(literate_folder)) do (path, _, _)
            md_subpath = path == literate_folder ? md_dir : joinpath(md_dir, relpath(path, literate_folder))
            filtered_list = filter!(readdir(path; join=true)) do file
                out = endswith(file, ".jl") && file ∉ exclude_list # Basic check
                if smart_filter
                    out &= is_masterCI() || file ∈ modified_files || is_pkg_dependent(file, repr(mod))
                    if !out && endswith(file, ".jl")
                        @info "Skipping literate file $file"
                    end
                end
                out
            end
            map(filtered_list) do file
                author, date = get_last_author_date(file)
                Literate.markdown(file, md_subpath; flavor=Literate.DocumenterFlavor(), execute=true, postprocess=add_author_data(author, date))::String
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

function get_last_author_date(file::String)
    author, date = readlines(git(["log", "-n 1", "--pretty=format:%an (%ae)\n%as", "--", file]))
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
- `strict`: Decides if the run should error in case some rendering fails.
- `prettify`: Adapt the URL if the run is local, on CI master or CI MR.
- `notebooks`: File list of rendered notebooks.
- `pages`: The usual `pages` argument from `makedocs`
"""
function default_makedocs(;
   macros::Dict{Symbol,<:AbstractVector}=Dict{Symbol,Vector}(),
   strict::Bool=true,
   prettify::Bool=is_masterCI(),
   notebooks::AbstractVector=String[],
   notebook_path::String="notebooks",
   pages::AbstractVector{<:Pair{String,<:Any}}=Pair{String,Any}[],
   kwargs...
    )
    mathengine = Documenter.MathJax2(Dict(:TeX => Dict(:Macros => macros)))
    notebook_pages = if isempty(notebooks)
        []
    else
        "Notebooks" => rework_paths(notebooks, notebook_path)
    end
    makedocs(;
        strict,
        format=Documenter.HTML(;prettyurls=prettify, mathengine),
        pages=[pages; notebook_pages],
        kwargs...
    )
end

function rework_paths(paths::AbstractVector{<:String}, notebook_path::String)
    top_dir = Dict{String,Any}()
    map(paths) do f
        dirs_file = splitpath(f)
        pos = findfirst(==(notebook_path), dirs_file)
        isnothing(pos) && error("$(notebook_path) could not be found in the path $(f)")
        sub_dirs = dirs_file[pos+1:end-1] # Get the relpath of the file
        i = 1
        d = top_dir # We start at the root
        while true
            iter = iterate(sub_dirs, i)
            if isnothing(iter)
                push!(get!(Vector{String}, d, "files"), joinpath(dirs_file[pos:end]...))
                return
            else
                d = get!(Dict{String,Any}, d, first(iter)) # Create a new dict for a dir if it doesn't exist
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
