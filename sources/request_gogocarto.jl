#!/usr/local/bin/julia
using ArgParse
import HTTP, JSON, URIs
using Cascadia
DEBUG = true
SIMULMODE =true

include("OpenProductProducer.jl")


######### https://producteurspl.gogocarto.fr/api/elements.json?limit=1000&categories=
#############


#=
Use https://overpass-turbo.eu to create query
=#
function getdatas_gogocarto(source::AbstractString; usecacheFile=false)
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
		datas
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
		# exit(1);
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
#=
	@return OpenProductProducer
=#
function getOpenProductProducer(producer::Dict, source::AbstractString)
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


function query_gogocarto(source::AbstractString)
	nb::Int = 0
	datas = getdatas_gogocarto(source, usecacheFile=true)
	for data in datas["data"]
		# if DEBUG; println(data); end
		producer = getOpenProductProducer(data, source)
		println("Producer:",producer)
		if producer isa Bool
			println("ERROR : Fail getOpenProductProducer()")
		else
			force = false
			if source=="openproduct"
				force = true
			end
			nb += 1
			insertOnDuplicateUpdate(producer, forceInsert=true, forceUpdate=force)
		end
	end
	nb
end

# query_gogocarto("producteurspl")
# query_gogocarto("collectiffermierdupoitou")
query_gogocarto("openproduct")

DBInterface.close!(dbConnection)

exit(0)
