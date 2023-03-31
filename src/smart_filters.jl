function list_modified(target::String="main")
    readlines(git(["diff", "--name-only", "HEAD", "origin/" * target]))
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