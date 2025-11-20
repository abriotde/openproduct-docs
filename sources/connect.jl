
import LibPQ
using Memoize

ENV="dev"
conffile = "../.env.production"
if isfile(conffile)
	println("Production environment")
	ENV="prod"
else
	println("Development environment")
end

CURDIR=pwd()
ROOT_PATH = ".."
if ENV=="dev"
	ROOT_PATH = "../../openproduct-web-svelte4"
end

include(ROOT_PATH*"/../OpenProduct.jl/src/OpenProduct.jl")
using .OpenProduct
# OpenProduct.GetConnection() = get_connection()
