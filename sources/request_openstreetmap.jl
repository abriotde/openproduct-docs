#!/usr/local/bin/julia
using ArgParse
import MySQL, DBInterface, HTTP, Gumbo, JSON, URIs
using Cascadia
DEBUG = false
######### https://overpass-turbo.eu/?Q=%2F*%0AThis+has+been+generated+by+the+overpass-turbo+wizard.%0AThe+original+search+was%3A%0A%E2%80%9Cshop%3Dfarm+in+France%E2%80%9D%0A*%2F%0A%5Bout%3Ajson%5D%5Btimeout%3A25%5D%3B%0A%2F%2F+fetch+area+%E2%80%9CFrance%E2%80%9D+to+search+in%0A%7B%7BgeocodeArea%3AFrance%7D%7D-%3E.searchArea%3B%0A%2F%2F+gather+results%0Anwr%5B%22shop%22%3D%22farm%22%5D%28area.searchArea%29%3B%0A%2F%2F+print+results%0Aout+geom%3B&C=45.421588%3B5.31407%3B6&R=
#############

dictionary = Dict(
	"duck" => "canard"
)

mutable struct OpenProductProducer
	lat::AbstractFloat
	lon::AbstractFloat
	score::AbstractFloat
	name::String
	firstname::String
	lastname::String
	city::String
	postCode::String
	address::String
	phoneNumber::String
	siret::String
	email::String
	website::String
	shortDescription::String
	description::String
	openingHours::String
	categories::String
end
#=
	Search if the producer exists in DB
	@return DBresult
=#
function search(producer::OpenProductProducer)
	lat = producer.lat
	lon = producer.lon
	res = DBInterface.execute(sqlSearchXY, [lat, lat, lon, lon, producer.name])
	for producerDB in res
		return producerDB
	end
	nothing
end
function insert(producer::OpenProductProducer)
	values = [
		producer.lat, producer.lon, producer.score, producer.name, producer.firstname, producer.lastname, producer.city, producer.postCode,
		producer.address, producer.phoneNumber, producer.siret, producer.email, producer.website,
		producer.shortDescription, producer.description, producer.openingHours, producer.categories
	]
	println("Insert producer : ", values)
	DBInterface.execute(sqlInsert, values)
end
#=
Use https://overpass-turbo.eu to create query
=#
function queryOpenStreetMap()
	try
		println("queryOpenStreetMap()")
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
function getSqlInsert()
	fields = [
		"name", "firstname", "lastname", 
		"city", "postCode", "address", 
		"phoneNumber", "siret", "email", "website", 
		"shortDescription", "`text`", "openingHours", "categories"
	]
	sql::String = "Insert ignore into openproduct.producer (latitude, longitude, geoprecision"
	for field in fields
		sql *= ","*field
	end
	sql *= ") values (?,?,?"
	for field in fields
		sql *= ",?"
	end
	sql *= ") on duplicate key update "
	sep = ""
	for field in fields
		sql *= sep*field*" = if(length(coalesce("*field*",''))<length(values("*field*")), values("*field*"), "*field*")"
		sep = ","
	end
	# println("SQL:",sql)
	sql
end

datas = queryOpenStreetMap()

conn = DBInterface.connect(MySQL.Connection, "Localhost", "root", "osiris")
sql ="SELECT * FROM openproduct.producer
	WHERE (latitude between ?-0.002 AND ?+0.002 
		AND longitude between ?-0.002 AND ?+0.002
	) OR name like ?"
sqlSearchXY = DBInterface.prepare(conn, sql)
sqlInsert = DBInterface.prepare(conn, getSqlInsert())
#=
	@return [latitude, longitude, score, postcode, city, adressName]; if nothing found, return latitude = 0
=#
function getAddressFromXY(latitude, longitude)
	try
		if DEBUG; println("getAddressFromXY(",latitude, ", ", longitude,")"); end
		ADRESS_API_URL = "https://api-adresse.data.gouv.fr/reverse/"
		url = ADRESS_API_URL * "?lon="*string(longitude)*"&lat="*string(latitude)
		response = HTTP.get(url)
		jsonDatas = response.body |> String |> JSON.parse
		addr = jsonDatas["features"][1]
		# println(place)
		props = addr["properties"]
		coordinates = addr["geometry"]["coordinates"]
		[coordinates[2], coordinates[1], props["score"], props["postcode"], props["city"], props["name"]]
    catch err
        println("ERROR : fail getAddressFromXY() : ",err)
        [0, 0, 0, 0, "", 0]
    end
end
function getPhoneNumber(phoneString::String)
	phoneNumber = ""
	for c in phoneString
		if c>='0' && c<='9'
			phoneNumber *= c
		end
	end
	phoneNumber
end
function getKey(array::Dict, keys, defaultValue)
	for key in keys
		if haskey(array, key)
			return array[key]
		end
	end
	defaultValue
end
#=
	@return OpenProductProducer
=#
function getOpenProductProducer(producer::Dict)

	lat = producer["lat"]
	lon = producer["lon"]
	tags = producer["tags"]
	address = getKey(tags, ["addr:housenumber"], "")*" "*getKey(tags, ["addr:street"], "")
	city = getKey(tags, ["addr:city"], "")
	postCode = getKey(tags, ["addr:postcode"], "")
	score = 0.99
	if address==" " || city=="" || postCode==""
		lat, lon, score, postCode, city, address = getAddressFromXY(lat, lon)
	end
	if lat==0
		println("ERROR : insertProducer(",producer,") : No coordinates found.")
		return false
	end
	if tags["shop"]!="farm"
		println("ERROR : insertProducer(",producer,") : Wrong tag[shop]=",tags["shop"],".")
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
	description = getKey(tags, ["description"], "")
	facebook = getKey(tags, ["facebook","contact:facebook"], "")
	if facebook!=""
		description *= "\n Facebook:" * facebook
	end
	instagram = getKey(tags, ["instagram","contact:instagram"], "")
	if instagram!=""
		description *= "\n Instagram:" * instagram
	end
	openingHours = getKey(tags, ["opening_hours"], "")
	siret = getKey(tags, ["ref:FR:SIRET"], "")
	OpenProductProducer(
		lat, lon, score, name, firstname, lastname, city, postCode,
		address, phoneNumber, siret, email, website,
		shortDescription, description, openingHours, "A" # Only food product from query with shop=farm
	)
end

id::Int = 0
for data in datas["elements"]
	if DEBUG; println(data); end
	global id += 1
	print("> ",id)
	if id>2
		producer = getOpenProductProducer(data)
		if producer isa Bool
			println("Fail getOpenProductProducer()")
		else
			producerDB = search(producer)
			if producerDB==nothing
				if producer.email!="" && producer.description!="" && producer.name!=""
					insert(producer)
				else
					println(" : skip")
				end
			else
				if DEBUG; println("Found:", producerDB); end
			end
		end
	end
end

DBInterface.close!(conn)

exit(0)


function getXYFromAddress(address)
	try
		println("getXYFromAddress(",address,")")
		ADRESS_API_URL = "https://api-adresse.data.gouv.fr/search/"
		address = replace(strip(address), "\""=>"")
		url = ADRESS_API_URL * "?q=" * URIs.escapeuri(address)
		# println("CALL: ",url)
		response = HTTP.get(url)
		jsonDatas = response.body |> String |> JSON.parse
		addr = jsonDatas["features"][1]
		coordinates = addr["geometry"]["coordinates"]
		props = addr["properties"]
		m=match(Regex("(.*)\\s*"*props["postcode"]*"\\s*"*props["city"]), address)
		if m!=nothing
			address = m[1]
		end
		[coordinates[2], coordinates[1], props["score"], props["postcode"], props["city"], address]
    catch err
        println("ERROR : fail getXYFromAddress() : ",err)
        [0, 0, 0, 0, "", address]
    end
end

