# # Literate Title 
using Distributions
# Using parent package
using DocTools
# Try something from Distributions.jl
rand(Exponential())
#
using StaticArrays
#
SVector{3}(1, 2, 3)
# ```math
# \Lc = 1.0
# ```
1 + 1
# !!! info
#     not really informative
#
# ``\ps`` is great!
