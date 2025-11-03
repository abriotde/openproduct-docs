
using Memoize
include("../lib/OpenProduct.jl/src/OpenProduct.jl")

using .OpenProduct
ENV="dev"
conffile = "../.env.production"
if isfile(conffile)
	println("Production environment")
	ENV="prod"
else
	println("Development environment")
end

CURDIR=pwd()
include_path = ".."
if ENV=="dev"
	include_path = "../../openproduct-web-svelte4"
end
include(include_path*"/scripts/connect.jl")
OpenProduct.GetConnection() = get_connection(ROOT_PATH)
