using DocTools
using Test

function build_docs_with_options(;recursive=true, pluto=true, literate=true, smart_filter=true)
    cd(joinpath(@__DIR__, "..", "docs"))
    pluto_pages = pluto ? build_pluto(DocTools, "pluto_notebooks"; recursive, smart_filter) : String[]

    literate_pages = literate ? build_literate(DocTools, "literate_notebooks"; recursive, smart_filter) : String[]

    default_makedocs(;
        sitename="Doctools.jl",
        modules=[DocTools],
        authors="PlantingSpace",
        repo="https://github.com/plantingspace/doctools/-/blob/{commit}{path}#{line}",
        macros=Dict(:ps => ["{PlantingSpace}"], :Lc => ["\\mathcal{L}"]),
        notebooks=[pluto_pages; literate_pages],
        pages=["Home" => "index.md"],
    )
end

function rm_docs_build()
    cd(joinpath(@__DIR__, ".."))
    rm(joinpath(@__DIR__, "..", "docs", "build"); recursive=true)
end

rm_docs_build()

@testset "DocTools.jl" begin
    # Tests are happening via the doc rendering itself using DocTools.
    @testset "Test use of recursion" begin
        try
            build_docs_with_options(recursive=true, smart_filter=false)
            @test 
        catch e
            rethrow(e)
        finally
            rm_docs_build()
        end
    end

end
