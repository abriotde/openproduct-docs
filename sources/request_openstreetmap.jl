#!/usr/local/bin/julia
using ArgParse
import HTTP, JSON, URIs
using Cascadia
DEBUG = false

include("OpenProductProducer.jl")


######### https://overpass-turbo.eu/?Q=%2F*%0AThis+has+been+generated+by+the+overpass-turbo+wizard.%0AThe+original+search+was%3A%0A%E2%80%9Cshop%3Dfarm+in+France%E2%80%9D%0A*%2F%0A%5Bout%3Ajson%5D%5Btimeout%3A25%5D%3B%0A%2F%2F+fetch+area+%E2%80%9CFrance%E2%80%9D+to+search+in%0A%7B%7BgeocodeArea%3AFrance%7D%7D-%3E.searchArea%3B%0A%2F%2F+gather+results%0Anwr%5B%22shop%22%3D%22farm%22%5D%28area.searchArea%29%3B%0A%2F%2F+print+results%0Aout+geom%3B&C=45.421588%3B5.31407%3B6&R=
#############


#=
Use https://overpass-turbo.eu to create query
=#
function queryOpenStreetMap()
	try
		if(DEBUG); println("queryOpenStreetMap()"); end
		tmpfile = "./request_openstreetmap.json"
		if false
			adressAPIurl = "https://overpass-api.de/api/interpreter"
			query = """//search:“shop=farm in France”
			[out:json][timeout:25];
			// {{geocodeArea:France}} : area(id:3602202162)
			area(id:3602202162)->.searchArea;
			nwr["shop"="farm"](area.searchArea);
			out geom;"""
			println("Query: ",query)
			params = URIs.escapeuri(Dict("data" =>query))
			response = HTTP.post(
				adressAPIurl,
				body=params
			)
			write(tmpfile, response.body);
			# datas = response.body |> String |> JSON.parse
		end
		datas = read(tmpfile, String) |> JSON.parse;
		# println(datas);
		datas
    catch err
        println("ERROR : fail queryOpenStreetMap() : ",err)
		nothing
    end
end

datas = queryOpenStreetMap()

#=
	@return OpenProductProducer
=#
function getOpenProductProducer(producer::Dict)
	if (!haskey(producer, "lat")) || (!haskey(producer,"lon"))
		println("ERROR : getOpenProductProducer(",producer,") : No coordinates found.")
		return false
	end
	lat = producer["lat"]
	lon = producer["lon"]
	tags = producer["tags"]
	address = getKey(tags, ["addr:housenumber"], "")*" "*getKey(tags, ["addr:street"], "")
	city = getKey(tags, ["addr:city"], "")
	postCode = getKey(tags, ["addr:postcode"], "")
	score = 0.99
	if tags["shop"]!="farm"
		println("ERROR : getOpenProductProducer(",producer,") : Wrong tag[shop]=",tags["shop"],".")
		return false
	end
	name = getKey(tags, ["name"], "")
	firstname = lastname = getKey(tags, ["operator"], "")
	website = getKey(tags, ["website", "contact:website"], "")
	phoneNumber = getKey(tags, ["phone"], "")
	if phoneNumber!=""
		phoneNumber = getPhoneNumber(replace(phoneNumber,"+33 "=>"0"))
	end
	email = getKey(tags, ["email"], "")
	shortDescription = "Agriculteur"
	text = getKey(tags, ["description"], "")
	facebook = getKey(tags, ["facebook","contact:facebook"], "")
	if facebook!=""
		text *= "\n Facebook:" * facebook
	end
	instagram = getKey(tags, ["instagram","contact:instagram"], "")
	if instagram!=""
		text *= "\n Instagram:" * instagram
	end
	openingHours = getKey(tags, ["opening_hours"], "")
	siret = getKey(tags, ["ref:FR:SIRET"], "")
	OpenProductProducer(
		lat, lon, score, name, firstname, lastname, city, postCode,
		address, phoneNumber, siret, email, website,
		shortDescription, text, openingHours, "A" # Only food product from query with shop=farm
	)
end

id::Int = 0
for data in datas["elements"]
	if DEBUG; println(data); end
	global id += 1
	if id>=0
		# println("> ",id," ",data)
		producer = getOpenProductProducer(data)
		if producer isa Bool
			println("ERROR : Fail getOpenProductProducer()")
		else
			insertOnDuplicateUpdate(producer)
		end
	end
end

DBInterface.close!(dbConnection)

exit(0)
