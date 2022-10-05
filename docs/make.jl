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
)
