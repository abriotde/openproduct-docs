#!/usr/local/bin/julia
using ArgParse
import HTTP, JSON, URIs
using Cascadia
DEBUG = true
SIMULMODE =true

include("OpenProductProducer.jl")


######### https://producteurspl.gogocarto.fr/api/elements.json?limit=1000&categories=
#############



# query_gogocarto("producteurspl")
# query_gogocarto("collectiffermierdupoitou")
query_gogocarto("openproduct")

DBInterface.close!(dbConnection)

exit(0)
