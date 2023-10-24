function list_modified(target::String = get(ENV, "CI_DEFAULT_BRANCH", "main"))
  run(`git fetch origin $(target)`) # We need to fetch the origin to get the latest changes.
  readlines(`git diff --name-only origin/$(target)...`)
end

function is_pkg_modified(paths::AbstractVector{<:String})
  any(startswith("src"), paths)
end

# Potentially replace this with proper parsing from CodeTools when it becomes a separate package.
function is_pkg_dependent(path::String, pkg::String)
  pkg_r = Regex("(using|import) $(pkg)")
  open(path, "r") do io
    for line in eachline(io)
      if occursin(pkg_r, line)
        return true
      end
    end
    return false
  end
end
