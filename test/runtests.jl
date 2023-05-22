using DocTools
using Test

const DOCS_DIR = abspath(joinpath(@__DIR__, "..", "docs"))
const BUILD_DIR = abspath(joinpath(DOCS_DIR, "build"))
const NOTEBOOKS_DIR = abspath(joinpath(BUILD_DIR, "notebooks"))
const SRC_ASSETS_DIR = abspath(joinpath(DOCS_DIR, "src", "assets"))
const SRC_NOTEBOOKS_DIR = abspath(joinpath(DOCS_DIR, "src", "notebooks"))

function build_docs_with_options(;recursive=true, pluto=true, literate=true, smart_filter=true)
    pluto_pages = pluto ? build_pluto(DocTools, "pluto_notebooks"; recursive, smart_filter) : String[]

    literate_pages = literate ? build_literate(DocTools, "literate_notebooks"; recursive, smart_filter) : String[]

    default_makedocs(;
        root = DOCS_DIR,
        sitename="Doctools.jl",
        modules=[DocTools],
        authors="PlantingSpace",
        macros=Dict(:ps => ["{PlantingSpace}"], :Lc => ["\\mathcal{L}"]),
        notebooks=[pluto_pages; literate_pages],
        pages=["Home" => "index.md"],
    )
end


function rm_docs_build()
    cd(joinpath(@__DIR__, ".."))
    for dir in [BUILD_DIR, SRC_ASSETS_DIR, SRC_NOTEBOOKS_DIR]
        isdir(dir) && rm(dir; recursive=true)
    end
end

rm_docs_build()

@testset "DocTools.jl" begin
    # Tests are happening via the doc rendering itself using DocTools.
    @testset "Test use of recursion" begin
        try
            build_docs_with_options(recursive=true, smart_filter=false)
            @test isfile(joinpath(BUILD_DIR, "assets", "notebooks", "Pluto Notebook.html"))
            @test isfile(joinpath(BUILD_DIR, "assets", "notebooks", "Subfolder Pluto", "Subfolder Pluto Notebook.html"))
            @test isfile(joinpath(NOTEBOOKS_DIR, "Literate Notebook.html"))
            @test isfile(joinpath(NOTEBOOKS_DIR, "Pluto Notebook.html"))
            @test isfile(joinpath(NOTEBOOKS_DIR, "Subfolder Literate", "Subfolder Literate Notebook.html"))
            @test isfile(joinpath(NOTEBOOKS_DIR, "Subfolder Pluto", "Subfolder Pluto Notebook.html"))
        catch e
            rethrow(e)
        finally
            rm_docs_build()
        end
        try
            build_docs_with_options(recursive=false, smart_filter=false)
            @test isfile(joinpath(BUILD_DIR, "assets", "notebooks", "Pluto Notebook.html"))
            @test !isfile(joinpath(BUILD_DIR, "assets", "notebooks", "Subfolder Pluto", "Subfolder Pluto Notebook.html"))
            @test isfile(joinpath(NOTEBOOKS_DIR, "Literate Notebook.html"))
            @test isfile(joinpath(NOTEBOOKS_DIR, "Pluto Notebook.html"))
            @test !isfile(joinpath(NOTEBOOKS_DIR, "Subfolder Literate", "Subfolder Literate Notebook.html"))
            @test !isfile(joinpath(NOTEBOOKS_DIR, "Subfolder Pluto", "Subfolder Pluto Notebook.html"))
        catch e
            rethrow(e)
        finally
            rm_docs_build()
        end
    end
end
