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

function dbConnect()::DBInterface.Connection
	DB_CONFIGURATION_FILE = "../../openproduct-web/db/connection.yml"
	dbconfiguration = YAML.load_file(DB_CONFIGURATION_FILE)
	dbconf = dbconfiguration["dev"]
	DBInterface.connect(MySQL.Connection, 
		dbconf["host"], dbconf["username"], dbconf["password"], 
		db=dbconf["database"],
		opts=Dict("found_rows"=>true)
	)
end
dbConnection = dbConnect()
DATEFORMAT_MYSQL = DateFormat("yyyy-mm-dd H:M:S")
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

#######################################################################
#        Query gogocarto
#######################################################################

const GogoCartoDict = Dict
#=
Use https://overpass-turbo.eu to create query
=#
function getdatas_gogocarto(source::AbstractString; usecacheFile=false)::GogoCartoDict
	try
		if(DEBUG); println("getdatas_gogocarto()"); end
		tmpfile = "./query_gogocarto.json"
		adressAPIurl = "https://"*source*".gogocarto.fr/api/elements.json?limit=1000&categories="
		if usecacheFile && isfile(tmpfile)
			datas = read(tmpfile, String) |> JSON.parse;
		else
			response = HTTP.get(adressAPIurl)
			if usecacheFile
				write(tmpfile, response.body)
			end
			datas = response.body |> String |> JSON.parse
		end
		convert(GogoCartoDict, datas)
    catch err
        println("ERROR : fail getdatas_gogocarto() : ",err)
		nothing
    end
end

struct CategoryRow
	id::Int
	word::String
	category::Union{Missing, String}
	parent::Union{Missing, Int}
end
CategoryMap = Dict{String, CategoryRow}()
CategoryIdMap = Dict{Int, CategoryRow}()
function getCategory(name::AbstractString)::Union{Missing, CategoryRow}
	if haskey(CategoryMap, name)
		return CategoryMap[name]
	else
		sql ="SELECT id,fr,category,parent FROM produce WHERE fr=?"
		sqlGetCategoryByFR = DBInterface.prepare(dbConnection, sql)
		res = DBInterface.execute(sqlGetCategoryByFR, [name])
		cat = missing
		for row in res
			cat = CategoryRow(row[:id],row[:fr],row[:category],row[:parent])
			CategoryMap[row[:fr]] = cat
			CategoryIdMap[row[:id]] = cat
		end
		cat
	end
end
function getCategory(id::Integer)::CategoryRow
	if haskey(CategoryIdMap, id)
		return CategoryIdMap[id]
	else
		sql ="SELECT id,fr,category,parent FROM produce WHERE id=?"
		sqlGetCategory = DBInterface.prepare(dbConnection, sql)
		res = DBInterface.execute(sqlGetCategory, [id])
		cat = missing
		for row in res
			cat = CategoryRow(row[:id],row[:fr],row[:category],row[:parent])
			CategoryMap[row[:fr]] = cat
			CategoryIdMap[row[:id]] = cat
		end
		cat
	end
end
function getCategoriesString(name::String)
	categories = ""
	last = ""
	cat=getCategory(name)
	if ismissing(cat)
		println("Error getCategory(",name,") unknown category: ")
		exit(1);
	end
	while !ismissing(cat)
		if (!ismissing(cat.category)) && cat.category!=last
			last = cat.category
			categories *= last
		end
		if !ismissing(cat.parent)
			cat=getCategory(cat.parent)
			if ismissing(cat)
				println("Error getCategory(",cat.parent,") : ", cat)
				exit(1);
			end
		else
			cat = missing
		end
	end
	categories
end
function getDate(dateTU::String)::DateTime
	# FORMAT 2024-03-11T09:41:45+01:00
	GOGOCARTO_DATEFORMAT = DateFormat("y-m-dTH:M:S");
	date,tu = split(dateTU,"+")
	DateTime(date, GOGOCARTO_DATEFORMAT)
end
GOGOCARTO_LASTEXPORT_DATE="2024-03-11T09:41:45+01"


function getOpenProductProducer(producer::DBInterface.Cursor)::OpenProductProducer
	# TODO
end
#=
	@return OpenProductProducer
=#
function getOpenProductProducer(producer::GogoCartoDict, source::AbstractString)::Union{OpenProductProducer, Missing}
	name = getKey(producer, ["name"], "")
	geo = producer["geo"]
	lat = geo["latitude"]
	lon = geo["longitude"]
	addr = producer["address"]
	address = getKey(addr, ["streetAddress"], "")
	city =  getKey(addr, ["addressLocality"], "")
	postCode = parse(Int32, getKey(addr, ["postalCode"], "0"))
	if postCode==0; postCode = missing; end
	shortDescription = categories = ""
	c = producer["categories"][1]
	categories = getCategoriesString(c)
	shortDescription = c
	score = 0.99
	openingHours = text = website = phoneNumber = phoneNumber2 = email = siret = ""
	lastUpdateDate = Date("2019-01-01")
	if source=="producteurspl"
		firstname = lastname = getKey(producer,["Exploitant"],"")
		text = openingHours = ""
		if haskey(producer, "Produits") && producer["Produits"]!==nothing
			text = "Production : "*producer["Produits"]
		end
	elseif source=="collectiffermierdupoitou"
		firstname = getKey(producer,["prenom"],"")
		lastname = getKey(producer,["nom"],"")
		if name==""
			name=firstname*" "*lastname
		end
		website = getKey(producer,["site_internet"],"")
		text = shortDescription
		for key in ["telephone_1","telephone_2"]
			phone = getKey(producer,[key],"")
			if isa(phone, Integer)
				phone = getPhoneNumber(phone)
			end
			m=match(regexPhoneLarge, phone)
			if m!=nothing
				phone = getPhoneNumber(phone)
				if phoneNumber==""
					phoneNumber = phone
				else
					phoneNumber2 = phone
				end
			elseif (m=match(regexEmail, phone)) != nothing
				email = phone
			end
		end
	elseif source=="openproduct"
		# createdAt = getDate(producer["createdAt"])
		updatedAt = getDate(producer["updatedAt"])
		lastUpdateDate = updatedAt
		firstname = getKey(producer,["prenom"],"")
		lastname = getKey(producer,["nom_de_famille"],"")
		phoneNumber = getKey(producer,["telephone"],"")
		phoneNumber2 = getKey(producer,["telephone2"],"")
		email = getKey(producer,["email"],"")
		text = getKey(producer,["description"],"")
		shortDescription = ""
		# id = producer["categoriesFull"]["id"]
		println("Producer:",producer)
	else
		println("getOpenProductProducer(",source,") : unknown source.")
		exit(1)
	end
	#= println("Producer:",[
		lat, lon, score, name, firstname, lastname, city, postCode,
		address, phoneNumber, phoneNumber2, siret, email, website,
		shortDescription, text, openingHours, categories, 
		"", ""
	]) =#
	OpenProductProducer(
		lat, lon, score, name, firstname, lastname, city, postCode,
		address, phoneNumber, phoneNumber2, siret, email, website,
		shortDescription, text, openingHours, categories, 
		"", "", lastUpdateDate
	)
end


function query_gogocarto(source::AbstractString)::Int
	nb::Int = 0
	datas = getdatas_gogocarto(source, usecacheFile=true)
	for data in datas["data"]
		# if DEBUG; println(data); end
		producer = getOpenProductProducer(data, source)
		println("Producer:",producer)
		if ismissing(producer)
			println("ERROR : Fail getOpenProductProducer()")
		else
			force::Bool = false
			if source=="openproduct"
				force = true
			end
			nb += 1
			insertOnDuplicateUpdate(producer, forceInsert=true, forceUpdate=force)
		end
	end
	nb
end

function getAllAreas()
	areas::Vector{Int} = []
	sql = "SELECT distinct if(postCode>200, cast(postCode/1000 as int), postCode) as area
		from producer
		WHERE postCode IS NOT NULL
		ORDER BY area"
	areasRes = DBInterface.execute(dbConnection,sql)
	for area in areasRes
		if area[1] === missing
			println("Error : null postCode in producer")
			exit()
		end
		push!(areas, area[1])
	end
	areas
end

@enum ScriptStatus start ok ko
SCRIPT_UNIQ = ""
function op_start(dbCnx = nothing, comment::String = "")
	if isnothing(dbCnx)
		dbCnx = dbConnection
	end
	global SCRIPT_UNIQ = string(round(Int, datetime2unix(now())*1000), base = 35)
	if ismissing(SCRIPT_NAME)
		println("ERROR : Missing SCRIPT_NAME constant")
		exit(1)
	end
	sql = "INSERT INTO script_history (script, time, state ,uniq ,comment)
		VALUES ('"*SCRIPT_NAME*"', now(), 'start', '"*SCRIPT_UNIQ*"', '"*MySQL.escape(dbCnx, comment)*"')"
	DBInterface.execute(dbCnx,sql)
end
op_start()
function op_stop(returnValue::ScriptStatus; dbCnx = nothing, comment::String = "")
	println("op_stop("*SCRIPT_NAME*", "*SCRIPT_UNIQ*")")
	if isnothing(dbCnx)
		dbCnx = dbConnection
	end
	if ismissing(SCRIPT_NAME)
		println("ERROR : Missing SCRIPT_NAME constant")
		exit(1)
	end
	sql = "INSERT INTO script_history (script, time, state ,uniq ,comment)
		VALUES ('"*SCRIPT_NAME*"', now(), '"*string(returnValue)*"', '"*SCRIPT_UNIQ*"', '"*MySQL.escape(dbCnx, comment)*"')"
	DBInterface.execute(dbCnx,sql)
	DBInterface.close!(dbCnx)
end
function op_getPreviousScriptTime(returnValue::ScriptStatus; dbCnx=nothing)
	if isnothing(dbCnx)
		dbCnx = dbConnection
	end
	sql = "SELECT max(t) FROM (
			SELECT min(`time`) t, GROUP_CONCAT(state) s 
			FROM script_history
			WHERE script='"*SCRIPT_NAME*"'
			GROUP BY uniq HAVING count(*)>=2 AND s='start,ok'
		) a"
	if DEBUG
		println("SQL:",sql)
	end
	res = DBInterface.execute(dbCnx,sql)
	for row in res
		return row[1]
	end
end