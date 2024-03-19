

include("../lib/OpenProduct.jl/src/OpenProduct.jl")
# using OpenProduct
dbConnection = OpenProduct.dbConnect("../../openproduct-web/db/connection.yml")
OpenProduct.op_start(dbConnection)
