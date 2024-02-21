#!/usr/local/bin/julia
using ArgParse
import MySQL, DBInterface, HTTP, Gumbo, JSON, URIs, StringDistances
using Cascadia
DEBUG = false

regexPhone = Regex("^[0-9]{10}\$")
regexEmail = Regex("^[a-z._-]+@[a-z._-]+.[a-z]{2,3}\$")

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
	text::String
	openingHours::String
	categories::String
end
function complete!(producer::OpenProductProducer)
	if strip(producer.address)=="" || producer.city=="" || producer.postCode==""
		lat, lon, score, postCode, city, address = getAddressFromXY(producer.lat, producer.lon)
		if lat==0
			println("ERROR : insertProducer(",producer,") : No coordinates found from getAddressFromXY().")
			return false
		end
		producer.lat .= lat
		producer.lon .= lon
		producer.score .= score
		producer.postCode .= postCode
		producer.city .= city
		producer.address .= address
	end
end

function getSimilarityScore(s1::String, s2::String)
	val = lowercase(strip(s1))
	oval = lowercase(strip(s2))
	if val!="" && oval!=""
		dist = StringDistances.Levenshtein()(oval, val)
		s = 10 ^ (dist/max(length(oval), length(val)))
		return 1/s
	end
	0
end
function getSimilarityScore(p::Dict, producer::OpenProductProducer)
	score = 0
	score += 10*getSimilarityScore(p[:name], producer.name)
	dist = ((p[:longitude]-producer.lon)^2) + ((p[:latitude]-(producer.lat))^2)
	score += 10*(1/(100 ^ (dist*100)))
	return score
end
#=
	Search if the producer exists in DB
	@return DBresult
	Any[
		Dict{Symbol, Any}(:longitude => 1.429549, :phoneNumber => "", :shortDescription => "", :wikiTitle => missing, :nbMailSend => 0, :text => " ", :firstname => "", :city => "Toulouse", :sendEmail => missing, :wikiDefaultTitle => "", :tokenAccess => missing, :postCode => 31300, :openingHours => "", :preferences => missing, :nbModeration => 0, :latitude => 43.598172, :geoprecision => 0.9753854545454544, :siret => "0", :status => "actif", :noteModeration => missing, :phoneNumber2 => missing, :name => "Ferme Attitude", :categories => "AG", :email => "", :websiteStatus => "unknown", :address => "4 Rue Villeneuve ", :id => 10129, :website => "", :lastname => ""),
		Dict{Symbol, Any}(:longitude => 1.449804, :phoneNumber => "0534335155", :shortDescription => "Produits : Fruits, Légumes, Viandes, Traiteur et charcuterie, Volaille et lapin, Fromages, Oeufs et produits laitiers, Pain et patisseries, Miels et confitures, Huiles et vinaigres, Épicerie, Vins et alcools, Jus et sirops", :wikiTitle => missing, :nbMailSend => 0, :text => "Le principe est simple, c’est la campagne qui s’invite en ville. Ferme Attitude accueille maintenant plus de 150 producteurs locaux, installés dans un rayon de 250km autour de Toulouse. HORAIRES Du lundi au samedi de 9h30 à 19h30. ", :firstname => "", :city => "Toulouse", :sendEmail => missing, :wikiDefaultTitle => "", :tokenAccess => missing, :postCode => 31000, :openingHours => "", :preferences => missing, :nbModeration => 0, :latitude => 43.600913, :geoprecision => 0.9781718181818182, :siret => "0", :status => "actif", :noteModeration => missing, :phoneNumber2 => missing, :name => "Ferme Attitude Saint Georges", :categories => "AG", :email => "", :websiteStatus => "ok", :address => "23 rue d’Astorg ", :id => 10130, :website => "https://www.fermeattitude.fr", :lastname => "")
	]
=#
function search(producer::OpenProductProducer)
	# println("search(",producer,")")
	name = producer.name
	if name == ""
		name = "XXXXXXXXXX"
	end
	if producer.lat==0 || producer.lon==0
		complete!(producer)
	end
	lat = producer.lat
	lon = producer.lon
	res = DBInterface.execute(sqlSearchXY, [lat, lat, lon, lon, name])
	producers = []
	numrows = 0
	for producerDB in res
		numrows += 1
		# TODO : avoid use Dict() when just one row.
		prod = Dict(propertynames(producerDB) .=> values(producerDB))
		push!(producers, prod)
	end
	len = length(producers)
	if len==0
		return nothing
	elseif len==1
		return producers[1]
	elseif len>1
		# println("\nsearch() => ",len," choice :")
		bestScore::AbstractFloat = 0.0
		bestId::Int = 0
		for (id, p) in enumerate(producers)
			score = getSimilarityScore(p, producer)
			if score>bestScore
				bestId = id
				bestScore = score
			end
		end
		return producers[bestId]
	end
	nothing
end
function insert!(producer::OpenProductProducer)
	complete!(producer)
	values = [
		producer.lat, producer.lon, producer.score, producer.name, producer.firstname, producer.lastname, producer.city, producer.postCode,
		producer.address, producer.phoneNumber, producer.siret, producer.email, producer.website,
		producer.shortDescription, producer.text, producer.openingHours, producer.categories
	]
	println("Insert producer : ", values)
	# DBInterface.execute(sqlInsert, values)
end
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

conn = DBInterface.connect(MySQL.Connection, "Localhost", "root", "osiris", 
	db = "openproduct",
	opts = Dict("found_rows"=>true)
)
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
	if (!haskey(producer, "lat")) || (!haskey(producer,"lon"))
		println("ERROR : insertProducer(",producer,") : No coordinates found.")
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

function update(producerDB, producer)
	if(DEBUG); println("update(",producerDB,", ",producer,")"); end
	sql = "UPDATE producer SET "
	sep = "";
	dbVal = producerDB[:name]
	if dbVal=="" && producer.name!=""
		sql *= sep*"name='"*MySQL.escape(conn, producer.name)*"'"
		sep = ","
	end
	dbVal = producerDB[:text]
	# println(dbVal, " VS ", producer.text)
	if (dbVal===missing || dbVal=="") && producer.text!=""
		sql *= sep*"text='"*MySQL.escape(conn, producer.text)*"'"
		sep = ","
	end
	dbVal = producerDB[:phoneNumber]
	if (dbVal===missing || dbVal=="") && producer.phoneNumber!=""
		sql *= sep*"phoneNumber='"*MySQL.escape(conn, producer.phoneNumber)*"'"
		sep = ","
	end
	dbVal = producerDB[:email]
	if (dbVal===missing || dbVal=="") && producer.email!=""
		sql *= sep*"email='"*MySQL.escape(conn, producer.email)*"', sendEmail=NULL"
		sep = ","
	end
	dbVal = producerDB[:openingHours]
	if (dbVal===missing || dbVal=="") && producer.openingHours!=""
		sql *= sep*"openingHours!='"*MySQL.escape(conn, producer.openingHours)*"'"
		sep = ","
	end
	dbVal = producerDB[:website]
	if (dbVal===missing || dbVal=="") && producer.website!=""
		sql *= sep*"website='"*MySQL.escape(conn, producer.website)*"'"
		sep = ","
	end
	dbVal = producerDB[:siret]
	if (dbVal===missing || dbVal=="") && producer.siret!=""
		sql *= sep*"siret='"*MySQL.escape(conn, producer.siret)*"'"
		sep = ","
	end
	if sep==","
		sql *= " WHERE id=" * string(producerDB[:id])
		println("SQL:",sql)
		# res = DBInterface.execute(conn, sql)
	end
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
			producerDB = search(producer)
			if producerDB==nothing
				if (producer.email!="" || producer.phoneNumber!="") && 
						producer.text!="" && producer.name!=""
					insert!(producer)
				else
					println("SKIP:",data,"")
				end
			else
				if DEBUG; println("Found:", producerDB); end
				update(producerDB, producer)
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

