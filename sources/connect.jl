
using Memoize
include("../lib/OpenProduct.jl/src/OpenProduct.jl")
# using OpenProduct
@memoize OpenProduct.GetConnection() = OpenProduct.dbConnect("../../openproduct-web/db/connection.yml")
dbConnection = OpenProduct.dbConnect("../../openproduct-web/db/connection.yml")
OpenProduct.op_start(dbConnection)
