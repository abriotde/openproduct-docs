#!/usr/local/bin/julia
using ArgParse
import MySQL, DBInterface, HTTP, JSON, URIs, StringDistances
using Cascadia, YAML

regexPhone = Regex("^[0-9]{10}\$")
regexEmail = Regex("^[a-z._-]+@[a-z._-]+.[a-z]{2,3}\$")
regexHttpSchema = Regex("^https?://.*")

######### https://overpass-turbo.eu/?Q=%2F*%0AThis+has+been+generated+by+the+overpass-turbo+wizard.%0AThe+original+search+was%3A%0A%E2%80%9Cshop%3Dfarm+in+France%E2%80%9D%0A*%2F%0A%5Bout%3Ajson%5D%5Btimeout%3A25%5D%3B%0A%2F%2F+fetch+area+%E2%80%9CFrance%E2%80%9D+to+search+in%0A%7B%7BgeocodeArea%3AFrance%7D%7D-%3E.searchArea%3B%0A%2F%2F+gather+results%0Anwr%5B%22shop%22%3D%22farm%22%5D%28area.searchArea%29%3B%0A%2F%2F+print+results%0Aout+geom%3B&C=45.421588%3B5.31407%3B6&R=
#############

dictionary = Dict(
	"duck" => "canard"
)

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

function dbConnect()
	DB_CONFIGURATION_FILE = "../../openproduct-web/db/connection.yml"
	dbconfiguration = YAML.load_file(DB_CONFIGURATION_FILE)
	dbconf = dbconfiguration["dev"]
	DBInterface.connect(MySQL.Connection, 
		dbconf["host"], dbconf["username"], dbconf["password"], 
		db = dbconf["database"],
		opts = Dict("found_rows"=>true)
	)
end
dbConnection = dbConnect()
sql ="SELECT * FROM openproduct.producer
	WHERE (latitude between ?-0.001 AND ?+0.001
		AND longitude between ?-0.001 AND ?+0.001
	) OR name like ?"
sqlSearchXY = DBInterface.prepare(dbConnection, sql)
sqlInsert = DBInterface.prepare(dbConnection, getSqlInsert())


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
	startdate::String
	enddate::String
end
OpenProductProducer() = OpenProductProducer(
	0.0,0.0,0.0,"","","","","","","","","","","","","","","",""
)
function complete(producer::OpenProductProducer)
	if strip(producer.address)=="" || producer.city=="" || producer.postCode==""
		lat, lon, score, postCode, city, address = getAddressFromXY(producer.lat, producer.lon)
		if lat==0
			println("ERROR : insertProducer(",producer,") : No coordinates found from getAddressFromXY().")
			return false
		end
		producer.lat = lat
		producer.lon = lon
		producer.score = score
		producer.postCode = postCode
		producer.city = city
		producer.address = address
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
=#
function search(producer::OpenProductProducer)
	# println("search(",producer,")")
	name = producer.name
	if name == ""
		name = "XXXXXXXXXX"
	end
	if producer.lat==0 || producer.lon==0
		complete(producer)
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
function insert(producer::OpenProductProducer)
	complete(producer)
	values = [
		producer.lat, producer.lon, producer.score, producer.name, producer.firstname, producer.lastname, producer.city, producer.postCode,
		producer.address, producer.phoneNumber, producer.siret, producer.email, producer.website,
		producer.shortDescription, producer.text, producer.openingHours, producer.categories
	]
	println("Insert producer : ", values)
	DBInterface.execute(sqlInsert, values)
end


function update(producerDB, producer)
	if(DEBUG); println("update(",producerDB,", ",producer,")"); end
	sql = "UPDATE producer SET "
	sep = "";
	dbVal = producerDB[:name]
	if (dbVal===missing || dbVal=="") && producer.name!=""
		sql *= sep*"name='"*MySQL.escape(dbConnection, producer.name)*"'"
		sep = ","
	end
	dbVal = producerDB[:firstname]
	if (dbVal===missing || dbVal=="") && producer.firstname!=""
		sql *= sep*"firstname='"*MySQL.escape(dbConnection, producer.firstname)*"'"
		sep = ","
	end
	dbVal = producerDB[:lastname]
	if (dbVal===missing || dbVal=="") && producer.lastname!=""
		sql *= sep*"lastname='"*MySQL.escape(dbConnection, producer.lastname)*"'"
		sep = ","
	end
	dbVal = producerDB[:text]
	# println(dbVal, " VS ", producer.text)
	if (dbVal===missing || dbVal=="" || ((length(dbVal)<32) && length(producer.text)>32) ) && 
			producer.text!=""
		sql *= sep*"text='"*MySQL.escape(dbConnection, producer.text)*"'"
		sep = ","
	end
	dbVal = producerDB[:phoneNumber]
	if (dbVal===missing || dbVal=="") && producer.phoneNumber!=""
		sql *= sep*"phoneNumber='"*MySQL.escape(dbConnection, producer.phoneNumber)*"'"
		sep = ","
	end
	dbVal = producerDB[:email]
	status = producerDB[:sendEmail]
	if (dbVal===missing || dbVal=="" || dbVal=="wrongEmail") && producer.email!=""
		sql *= sep*"email='"*MySQL.escape(dbConnection, producer.email)*"', sendEmail=NULL"
		sep = ","
	end
	dbVal = producerDB[:openingHours]
	if (dbVal===missing || dbVal=="") && producer.openingHours!=""
		sql *= sep*"openingHours='"*MySQL.escape(dbConnection, producer.openingHours)*"'"
		sep = ","
	end
	dbVal = producerDB[:website]
	status = producerDB[:websiteStatus]
	if (dbVal===missing || dbVal=="" || (status!="ok" && status!="unknown")) && 
			producer.website!=""
		sql *= sep*"website='"*MySQL.escape(dbConnection, producer.website)*"',websiteStatus='unknown'"
		sep = ","
	end
	dbVal = producerDB[:siret]
	if (dbVal===missing || dbVal=="") && producer.siret!=""
		sql *= sep*"siret='"*MySQL.escape(dbConnection, producer.siret)*"'"
		sep = ","
	end
	dbVal = producerDB[:enddate]
	if (dbVal===missing || dbVal=="") && producer.enddate!=""
		sql *= sep*"enddate='"*MySQL.escape(dbConnection, producer.enddate)*"', status='hs'"
		sep = ","
	end
	dbVal = producerDB[:startdate]
	if (dbVal===missing || dbVal=="") && producer.startdate!=""
		sql *= sep*"startdate='"*MySQL.escape(dbConnection, producer.startdate)*"'"
		sep = ","
	end
	if sep==","
		sql *= " WHERE id=" * string(producerDB[:id])
		println("SQL:",sql,";")
		# res = DBInterface.execute(dbConnection, sql)
	end
end

function insertOnDuplicateUpdate(producer::OpenProductProducer; force=false)
	producerDB = search(producer)
	if producerDB==nothing
		if (force || producer.email!="" || producer.phoneNumber!="" || producer.website!="" || producer.siret!="") && 
				producer.text!="" && producer.name!=""
			insert(producer)
			1
		else
			println("SKIP:",producer,"")
			0
		end
	else
		if DEBUG; println("Found:", producerDB); end
		update(producerDB, producer)
		2
	end
end

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
		if haskey(array, key) && array[key]!==nothing
			return array[key]
		end
	end
	defaultValue
end

function getWebSiteStatus(url)
	# println("getWebSiteStatus(",url,")")
	websiteStatus = "unknown"
	try
		r = HTTP.get(url, timeout=30, status_exception=false)
		# println("Response:",r)
		if r.status==200
			websiteStatus = "ok"
		elseif r.status==404
			println("=> ",r.status, "; URL:",url)
		elseif r.status>=400 && r.status<500
			websiteStatus = "400"
		elseif r.status==500 || r.status==503
			websiteStatus = "ko"
		else
			println(" =>",r.status, "; URL:",url)
		end
	catch  err
		if isa(err, HTTP.ConnectError)
			websiteStatus = "ConnectionError"
		elseif isa(err, ArgumentError)
			m = match(regexHttpSchema, url)
			if m==nothing
				newUrl = "https://"*url
				ok = getWebSiteStatus(newUrl)
				if ok=="ok"
					println("Change URL : ",url," => ",newUrl)
					sql2 = "UPDATE producer
						SET website='"*newUrl*"'
						WHERE website='"*url*"'"
					DBInterface.execute(dbConnection, sql2)
				end
				return ok
			end
			println("ERROR:",err)
			exit(1);
		elseif isa(err, HTTP.Exceptions.StatusError)
			websiteStatus = "400"
			println("Status: for ", err)
			exit(1)
		else
			println("ERROR:",err)
			exit(1);
		end
	end
	# print("getWebSiteStatus(",url,") => ", websiteStatus)
	websiteStatus
end

