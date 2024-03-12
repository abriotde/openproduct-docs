#!/usr/local/bin/julia
using ArgParse
import MySQL, DBInterface, HTTP, JSON, URIs, StringDistances
using Cascadia, YAML, Dates

regexPhone = Regex("^[0-9]{10}\$")
regexPhoneLarge = Regex("^\\+?[0-9 ]{10,20}\$")
regexEmail = Regex("^[a-z._-]+@[a-z._-]+.[a-z]{2,3}\$")
regexHttpSchema = Regex("^https?://.*")

######### https://overpass-turbo.eu/?Q=%2F*%0AThis+has+been+generated+by+the+overpass-turbo+wizard.%0AThe+original+search+was%3A%0A%E2%80%9Cshop%3Dfarm+in+France%E2%80%9D%0A*%2F%0A%5Bout%3Ajson%5D%5Btimeout%3A25%5D%3B%0A%2F%2F+fetch+area+%E2%80%9CFrance%E2%80%9D+to+search+in%0A%7B%7BgeocodeArea%3AFrance%7D%7D-%3E.searchArea%3B%0A%2F%2F+gather+results%0Anwr%5B%22shop%22%3D%22farm%22%5D%28area.searchArea%29%3B%0A%2F%2F+print+results%0Aout+geom%3B&C=45.421588%3B5.31407%3B6&R=
#############

dictionary = Dict(
	"duck" => "canard"
)

PRODUCER_UPDATE_FIELDS = [
	"name", "firstname", "lastname", 
	"city", "postCode", "address", 
	"phoneNumber", "phoneNumber2", "siret", "email", "website", 
	"shortDescription", "text", "openingHours", "categories"
]
PRODUCER_UPDATE_FIELDS_KEY = [
	:name, :firstname, :lastname, 
	:city, :postCode, :address, 
	:phoneNumber, :phoneNumber2, :siret, :email, :website, 
	:shortDescription, :text, :openingHours, :categories
]
function getSqlInsert()
	sql::String = "Insert ignore into producer (latitude, longitude, geoprecision"
	for field in PRODUCER_UPDATE_FIELDS
		sql *= ",`"*field*"`"
	end
	sql *= ") values (?,?,?"
	for field in PRODUCER_UPDATE_FIELDS
		sql *= ",?"
	end
	sql *= ") on duplicate key update "
	sep = ""
	for field in PRODUCER_UPDATE_FIELDS
		sql *= sep*"`"*field*"` = if(length(coalesce(`"*field*"`,''))<length(values(`"*field*"`)), values(`"*field*"`), `"*field*"`)"
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
sqlSelectTag = DBInterface.prepare(dbConnection, "SELECT * FROM produce WHERE fr like ?")
sqlInsertTag = DBInterface.prepare(dbConnection, "INSERT INTO produce(fr) VALUES (?)")
sqlInsertTagLink = DBInterface.prepare(dbConnection, "INSERT IGNORE INTO product_link(producer, produce) VALUES (?,?)")

mutable struct OpenProductProducer
	lat::AbstractFloat
	lon::AbstractFloat
	score::AbstractFloat
	name::String
	firstname::String
	lastname::String
	city::String
	postCode::Union{Missing, Int32}
	address::String
	phoneNumber::String
	phoneNumber2::String
	siret::String
	email::String
	website::String
	shortDescription::String
	text::String
	openingHours::String
	categories::String
	startdate::String
	enddate::String
	lastUpdateDate::DateTime
end
OpenProductProducer() = OpenProductProducer(
	0.0,0.0,0.0,"","","","","","","","","","","","","","","","","",now()
)
function complete(producer::OpenProductProducer)
	if (strip(producer.address)=="" || producer.city=="" || producer.postCode=="") && 
			producer.lat>0 && producer.lon>0
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
	elseif (producer.city!="" && producer.postCode!="") && 
			(producer.lat==0 || producer.lon==0)
		lat, lon, score, postCode, city, address = getXYFromAddress(producer.address*" "*producer.postCode*" "*producer.city)
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
function insert(producer::OpenProductProducer)::Int32
	complete(producer)
	values = [
		producer.lat, producer.lon, producer.score, producer.name, producer.firstname, producer.lastname, producer.city, producer.postCode,
		producer.address, producer.phoneNumber, producer.phoneNumber2, producer.siret, producer.email, producer.website,
		producer.shortDescription, producer.text, producer.openingHours, producer.categories
	]
	if DEBUG
		println("Insert producer : ", values)
	end
	if !SIMULMODE
		results = DBInterface.execute(sqlInsert, values)
		v = DBInterface.lastrowid(results)
		convert(Int32, v)
	else
		println("Insert producer : ", values)
	end
end


function update(producerDB, producer; force=false)
	# complete(producer)
	# if(DEBUG); println("update(",producerDB,", ",producer,")"); end
	sql::String = ""
	sep = "";
	for field in PRODUCER_UPDATE_FIELDS_KEY
		dbVal = producerDB[field]
		val = getfield(producer, field)
		ok, postSQL = getUpdateVal(field, dbVal, val, force)
		if ok
			println("DBval1:'",dbVal,"'(",typeof(dbVal),"); val:'",val,"'(",typeof(val),")")
			sql *= sep*"`"*string(field)*"`='"*MySQL.escape(dbConnection, val)*"'"*postSQL
			sep = ", "
		end
	end
	if sql!=""
		sql = "UPDATE producer SET "*sql*" WHERE id=" * string(producerDB[:id])
		if DEBUG || SIMULMODE; println("SQL:",sql,";"); end
		if !SIMULMODE
			res = DBInterface.execute(dbConnection, sql)
		end
	end
	producerDB[:id]
end

function getUpdateVal(field, dbVal::Union{Missing, Integer}, val::Union{Missing, Integer}, force::Bool)
	if ismissing(val) || val=="NULL"
		val = 0
	end
	if ismissing(dbVal)
		dbVal = 0
	end
	ok::Bool = false
	postSQL::String = ""
	if force
		ok = (dbVal!=val) && val!=0
	elseif val!=0 && (dbVal!=val) # Case !force
		if dbVal==0
			ok = true
		end
	end
	[ok, postSQL]
end
function getUpdateVal(field, dbVal::Union{Missing, String}, val::Union{Missing, String}, force::Bool)
	if ismissing(val) || val=="NULL"
		val = ""
	end
	if ismissing(dbVal)
		dbVal = ""
	end
	ok::Bool = false
	postSQL::String = ""
	if force
		if field==:categories
			ok = false
		else
			dbVal=strip(replace(dbVal, ","=>" ", "\n"=>" ", "\r"=>"", "\""=>"")) # TODO : For import in gogocarto we had to remove ","
			val=strip(replace(val, ","=>" ", "\n"=>" ", "\r"=>"", "\""=>""))
			ok = ((dbVal!=val) && val!="")
		end
	elseif val!="" && (dbVal!=val) # Case !force
		if dbVal==""
			ok = true
		elseif field==:text
			if length(dbVal)<32 && length(val)>32
				ok = true
			end
		elseif field==:email
			if producerDB[:sendEmail]=="wrongEmail"
				ok = true
				postSQL=",sendEmail=NULL"
			end
		elseif field==:website
			status = producerDB[:websiteStatus]
			if status!="ok" && status!="unknown"
				ok = true
				postSQL=",websiteStatus='unknown'"
			end
		end
		if field==:enddate && val!=""
			postSQL=",status='hs'"
		end
	end
	if ok
		println("DBval2:'",dbVal,"'(",typeof(dbVal),"); val:'",val,"'(",typeof(val),")")
	end
	[ok, postSQL]
end

#=
=#
function insertOnDuplicateUpdate(producer::OpenProductProducer; forceInsert=false, forceUpdate=false)::Int32
	producerDB = search(producer)
	if producerDB==nothing
		if (forceInsert || producer.email!="" || producer.phoneNumber!="" || producer.website!="" || producer.siret!="") && 
				producer.text!="" && producer.name!="" && producer.categories!=""
			insert(producer)
		else
			println("SKIP:",producer,"")
			0
		end
	else
		# if DEBUG; println("Found:", producerDB); end
		if forceUpdate && producerDB[:lastUpdateDate]<producer.lastUpdateDate
			force=true
		end
		update(producerDB, producer, force=force)
		producerDB[:id]
	end
end
#=
@param : id : id of producer
@param : tag : tag/produce name
=#
function setTagOnProducer(producerId::Int32, tagName::AbstractString)
	tagId = getTagIdDefaultInsert(tagName)
	DBInterface.execute(sqlInsertTagLink, [producerId, tagId])
end
function getTagIdDefaultInsert(tagname::AbstractString)::Int32
	results = DBInterface.execute(sqlSelectTag, [tagname])
	for res in results
		return res[:id]
	end
	results = DBInterface.execute(sqlInsertTag, [tagname])
	id = DBInterface.lastrowid(results)
	convert(Int32, id)
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

function getPhoneNumber(phoneString::AbstractString)
	phoneNumber = ""
	for c in phoneString
		if c>='0' && c<='9'
			phoneNumber *= c
		end
	end
	phoneNumber
end
function getPhoneNumber(phoneString::Integer)
	"0"*string(phoneString)
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

