using DocTools

pluto_pages = build_pluto(DocTools, "pluto_notebooks"; smart_filter = false, use_cache = true)

literate_pages = build_literate(DocTools, "literate_notebooks"; smart_filter = false, use_cache = true)

default_makedocs(;
  sitename = "Doctools.jl",
  modules = [DocTools],
  authors = "PlantingSpace",
  repo = "https://gitlab.com/plantingspace/doctools/",
  macros = Dict(:ps => ["{PlantingSpace}"], :Lc => ["\\mathcal{L}"]),
  notebooks = [pluto_pages; literate_pages],
  pages = ["Home" => "index.md"],
)
