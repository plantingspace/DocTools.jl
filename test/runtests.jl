using DocTools
using Test

const DOCS_DIR = abspath(joinpath(@__DIR__, "..", "docs"))
const BUILD_DIR = abspath(joinpath(DOCS_DIR, "build"))
const NOTEBOOKS_DIR = abspath(joinpath(BUILD_DIR, "notebooks"))
const SRC_ASSETS_DIR = abspath(joinpath(DOCS_DIR, "src", "assets"))
const SRC_NOTEBOOKS_DIR = abspath(joinpath(DOCS_DIR, "src", "notebooks"))

function build_docs_with_options(;
  recursive = true,
  pluto = true,
  literate = true,
  smart_filter = true,
  use_cache = false,
)
  pluto_pages = pluto ? build_pluto(DocTools, "pluto_notebooks"; recursive, smart_filter, use_cache) : String[]

  literate_pages =
    literate ? build_literate(DocTools, "literate_notebooks"; recursive, smart_filter, use_cache) : String[]

  default_makedocs(;
    root = DOCS_DIR,
    sitename = "Doctools.jl",
    modules = [DocTools],
    authors = "PlantingSpace",
    repo = "https://gitlab.com/plantingspace/doctools/",
    macros = Dict(:ps => ["{PlantingSpace}"], :Lc => ["\\mathcal{L}"]),
    notebooks = [pluto_pages; literate_pages],
    pages = ["Home" => "index.md"],
  )
end

const ismain = is_mainCI()
prettified(str, ismain::Bool = false) = ismain ? joinpath(str, "index.html") : str * ".html"

function rm_docs_build()
  cd(joinpath(@__DIR__, ".."))
  for dir in [BUILD_DIR, SRC_ASSETS_DIR, SRC_NOTEBOOKS_DIR]
    isdir(dir) && rm(dir; recursive = true)
  end
end

rm_docs_build()

@testset "DocTools.jl" begin
  # Tests are happening via the doc rendering itself using DocTools.
  @testset "With recursion" begin
    try
      build_docs_with_options(recursive = true, smart_filter = false)
      @test isfile(joinpath(BUILD_DIR, "assets", "notebooks", "Pluto Notebook.html"))
      @test isfile(joinpath(BUILD_DIR, "assets", "notebooks", "Subfolder Pluto", "Subfolder Pluto Notebook.html"))
      @test isfile(joinpath(NOTEBOOKS_DIR, prettified("Literate Notebook", ismain)))
      @test isfile(joinpath(NOTEBOOKS_DIR, prettified("Pluto Notebook", ismain)))
      @test isfile(joinpath(NOTEBOOKS_DIR, "Subfolder Literate", prettified("Subfolder Literate Notebook", ismain)))
      @test isfile(joinpath(NOTEBOOKS_DIR, "Subfolder Pluto", prettified("Subfolder Pluto Notebook", ismain)))
    catch e
      rethrow(e)
    finally
      rm_docs_build()
    end
  end
  @testset "Without recursion" begin
    try
      build_docs_with_options(recursive = false, smart_filter = false)
      @test isfile(joinpath(BUILD_DIR, "assets", "notebooks", "Pluto Notebook.html"))
      @test !isfile(joinpath(BUILD_DIR, "assets", "notebooks", "Subfolder Pluto", "Subfolder Pluto Notebook.html"))
      @test isfile(joinpath(NOTEBOOKS_DIR, prettified("Literate Notebook", ismain)))
      @test isfile(joinpath(NOTEBOOKS_DIR, prettified("Pluto Notebook", ismain)))
      @test !isfile(joinpath(NOTEBOOKS_DIR, "Subfolder Literate", prettified("Subfolder Literate Notebook", ismain)))
      @test !isfile(joinpath(NOTEBOOKS_DIR, "Subfolder Pluto", prettified("Subfolder Pluto Notebook", ismain)))
    catch e
      rethrow(e)
    finally
      rm_docs_build()
    end
  end

  @testset "Testing caching" begin
    # Reason we check the cache only is that for some reason on a second run the .plutostate is modified.
    # See 
    get_hash(folder::String) = readchomp(
      pipeline(`find $(folder) -type f -exec md5sum '{}' +`, `sort`, `md5sum`),
    )
    CACHE_DIR = joinpath(SRC_ASSETS_DIR, "notebooks", "cache")
    mkpath(CACHE_DIR)
    @testset "Working with cache" begin
      try
        build_docs_with_options(recursive = false, smart_filter = false, use_cache = true)
        # We create a hash of the directory to detect any change
        curr_cache_hash = get_hash(CACHE_DIR)
        curr_notebook_hash = get_hash(SRC_NOTEBOOKS_DIR)
        build_docs_with_options(recursive = false, smart_filter = false, use_cache = true)
        # If the notebook would have been rerun we would have a different value for the non-deterministic 
        # cell and the hash would be different.
        new_cache_hash = get_hash(CACHE_DIR)
        new_notebook_hash = get_hash(SRC_NOTEBOOKS_DIR)
        @test new_cache_hash == curr_cache_hash
        @test new_notebook_hash == curr_notebook_hash
      catch e
        rethrow(e)
      finally
        rm_docs_build()
      end
    end
  end

  @testset "Updating of dependencies" begin
    isbackup(file) = endswith(file, r"backup [0-9].jl")
    dir = joinpath(@__DIR__, "test_data")
    for file in readdir(dir; join = true)
      # Test that there is no present backup
      @test !isbackup(file)
      @test !isnothing(match(r"julia_version = \"1\.7", read(file, String)))
    end
    try
      update_notebooks_versions(dir; backup = true)
      for file in readdir(dir; join = true)
        if !isbackup(file)
          @test !isnothing(match(Regex("julia_version = \"$(VERSION.major).$(VERSION.minor)"), read(file, String)))
        end
      end
    catch e
      rethrow(e)
    finally
      # Restore the original files using the backups
      for file in readdir(dir; join = true, sort = false)
        if !isbackup(file) && !(endswith(file, ".old"))
          rm(file)
        else
          mv(file, replace(file, r" backup [0-9].jl" => ".jl.old")) # Temp allocation as .old.
        end
      end
      for file in readdir(dir; join = true)
        mv(file, file[begin:(end - 4)]) # Remove the .old.
      end
    end
    # Test that all modified files were replaced by the backups
    for file in readdir(dir; join = true)
      # Test that there is no backup
      @test !isbackup(file)
      @test !isnothing(match(r"julia_version = \"1\.7", read(file, String)))
    end
  end
end
