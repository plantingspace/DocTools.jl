# DocTools

General tools to generate documentation in the different PlantingSpace repositories.

[![Docs](https://img.shields.io/badge/docs-latest-blue.svg)](https://plantingspace.gitlab.io/doctools/)

It contains 4 main functions:

- `build_pluto`: given a folder build all Pluto notebooks using [`PlutoSliderServer.jl`](https://github.com/JuliaPluto/PlutoSliderServer.jl)
and process them to make them `Documenter` compatible.
- `build_literate`: similar to `build_pluto` but for [`Literate.jl`](https://github.com/fredrikekre/Literate.jl) files.
- `default_makedocs`: opinionated version of `makedocs` with given defaults and other.
- `is_mainCI`: check for Gitlab CI to see if it is run on `master/main` or on a MR.

A typical `make.jl` file looks like:

```julia
using DocTools
pluto_pages = build_pluto(DocTools, "pluto_notebooks")
literate_pages = build_literate(DocTools, "literate_notebooks")

default_makedocs(;
    sitename="Doctools.jl",
    modules=[DocTools],
    authors="PlantingSpace",
    repo="https://github.com/plantingspace/doctools/-/blob/{commit}{path}#{line}",
    macros=Dict(:ps => ["{PlantingSpace}"], :Lc => ["\\mathcal{L}"]),
    notebooks=[pluto_pages; literate_pages],
    pages=["Home" => "index.md"],
    editlink="main",
)
```
