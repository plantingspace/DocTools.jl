module DocTools

using Documenter
using Literate
using Pkg
using PlutoSliderServer

export build_pluto, build_literate, default_makedocs, is_masterCI

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
"""
function build_pluto(
    root::String,
    notebooks_path::String;
    run::Bool=true, # This is currently always true
    src_dir::String=joinpath(root, "docs", "src"),
    md_dir::String=joinpath(src_dir, "notebooks"),
    html_dir::String=joinpath(src_dir, "assets", "notebooks"),
    exclude_list::AbstractVector{<:String}=String[],
    )
    run || return String[]
    # Create folders if they do not exist already
    mkpath(md_dir)
    mkpath(html_dir)
    notebooks_dir = joinpath(root, notebooks_path)
    # PlutoSliderServer automatically detect which files are Pluto notebooks,
    # we just give it a directory to explore.
    # But first we preinstantiate the workbench directory.
    Pkg.activate(notebooks_dir)
    Pkg.instantiate()

    PlutoSliderServer.export_directory(
        notebooks_dir;
        Export_create_index = false,
        Export_output_dir = html_dir,
        Export_exclude = exclude_list,
        on_ready = check_for_failed_notebooks,
    )
    build_notebook_md(md_dir, html_dir)
end

function build_pluto(pkg::Module, notebooks_path::String; kwargs...)
    build_pluto(pkgdir(pkg), notebooks_path; kwargs...)
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
"""
function build_literate(
    root::String,
    literate_path::String;
    run::Bool=true,
    src_dir::String=joinpath(root, "docs", "src"),
    md_dir::String=joinpath(src_dir, "notebooks"),
)
    run || return String[]
    map(filter!(endswith(".jl"), readdir(joinpath(root, literate_path); join=true))) do file
        Literate.markdown(file, md_dir; flavor=Literate.DocumenterFlavor())
    end
end

function build_literate(pkg::Module, literate_path::String; kwargs...)
    build_literate(pkgdir(pkg), literate_path; kwargs...)
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
   notebooks::AbstractVector{<:String}=String[],
   pages::AbstractVector{<:Pair{String,<:Any}}=Pair{String,Any}[],
   kwargs...
    )
    mathengine = Documenter.MathJax2(Dict(:TeX => Dict(:Macros => macros)))
    notebook_pages = if isempty(notebooks)
        []
    else
        "Notebooks" => joinpath.(Ref("notebooks"), basename.(notebooks))
    end
    makedocs(;
        strict,
        format=Documenter.HTML(;prettyurls=prettify, mathengine),
        pages=[pages; notebook_pages],
        kwargs...
    )
end

end
