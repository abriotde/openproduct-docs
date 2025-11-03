#!/usr/local/bin/julia
using ArgParse

######### https://data.economie.gouv.fr/api/explore/v2.1/catalog/datasets/entreprises-du-patrimoine-vivant-epv/exports/csv?lang=fr&timezone=Europe%2FParis&use_labels=true&delimiter=%3B #############
# TODO : Get number of pages per regions.


# Update openproduct.producer
# 	set address = if(LOCATE(concat(postCode," ",city), address)>0, SUBSTR(address, 1, length(address)-length(concat(postCode," ",city))-2),address)
# where LOCATE(concat(postCode," ",city), address)>0;

# Update openproduct.producer
# set phoneNumber = replace(phoneNumber, " ","");

import MySQL, DBInterface, HTTP, CSV, JSON, URIs
using DataFrames, Dates

using Cascadia

include("connect.jl")
dbConnection = get_connection(include_path)

function parse_commandline()
	s = ArgParseSettings()
	@add_arg_table s begin
	 "--area"
		 help = "Import a uniq departement."
		 arg_type = Int
	 "--all", "-a"
		 help = "Import all departements (default none)."
		 action = :store_true
	end
	return parse_args(s)
end

#=
=#
function insert_gogocarto_element(gogoid, data)
	# println("insert_gogocarto_element(",data,")")
	id = data[1]
	name = data[2][1]
	lat = data[3]
	lon = data[4]
	println("insert_gogocarto_element(",name," (",id,"; ",lat,", ",lon,")",")")
	url = "https://"*gogoid*".gogocarto.fr/api/elements/"*id
	response = HTTP.get(url); dataDetail = response.body |> String |> JSON.parse
	data = dataDetail["data"]
	println(data)
	addressDetails = data["address"]
	address = get(addressDetails, "streetNumber", "")*" "*get(addressDetails, "streetAddress", "")
	city = addressDetails["addressLocality"]
	postCode = parse(Int, addressDetails["postalCode"])
	days = Dict(
		"Mo" => "Lundi",
		"Tu" => "Mardi",
		"We" => "Mercredi",
		"Th" => "Jeudi",
		"Fr" => "Vendredi",
		"Sa" => "Samedi",
		"Su" => "Dimanche"
	)
	openingHours = ""
	for (k, v) in get(data, "openHours", Dict())
		day = days[k]
		openingHours *= day*" : "*v*"; "
	end
	text = data["description"]
	email = get(data, "email", missing)
	website = get(data, "text_1731593643321", missing)
	phoneNumber = get(data, "text_1731593645198", missing)
	phoneNumber2 = missing
	startdate = data["createdAt"]
	dateformater = dateformat"y-m-dTH:M:S"
	lastUpdateDate = DateTime(data["updatedAt"][1:19], dateformater)
	siret = missing
	shortDescription = "Heboriste"
	categories = "AX"
	sourcekey = "https://"*gogoid*".gogocarto.fr"
	imageurl = missing
	for image in get(data, "images", [])
		imageurl = image
	end
	producer = OpenProductProducer(
		lat, lon, 1.0, name, missing, missing, city, postCode,
		address, phoneNumber, phoneNumber2, siret, email, website,
		shortDescription, text, sourcekey, imageurl, openingHours, categories, 
		startdate, missing, lastUpdateDate
	)
	println(producer)
	insertOnDuplicateUpdate(producer)
	exit(0);
end

function parse_gogocarto(gogoid)
    tmpfile = "./parse_gogocarto.json"
	url="https://"*gogoid*".gogocarto.fr/api/elements?bounds=-16.65527%2C38.54817%2C47.94434%2C54.49557%3B&boundsJson=%5B%7B%22_southWest%22%3A%7B%22lat%22%3A38.54817%2C%22lng%22%3A-16.65527%7D%2C%22_northEast%22%3A%7B%22lat%22%3A54.49557%2C%22lng%22%3A47.94434%7D%7D%2C%7B%22_southWest%22%3A%7B%22lat%22%3A0%2C%22lng%22%3A0%7D%2C%22_northEast%22%3A%7B%22lat%22%3A0%2C%22lng%22%3A0%7D%7D%2C%7B%22_southWest%22%3A%7B%22lat%22%3A0%2C%22lng%22%3A0%7D%2C%22_northEast%22%3A%7B%22lat%22%3A0%2C%22lng%22%3A0%7D%7D%2C%7B%22_southWest%22%3A%7B%22lat%22%3A0%2C%22lng%22%3A0%7D%2C%22_northEast%22%3A%7B%22lat%22%3A0%2C%22lng%22%3A0%7D%7D%5D&categories=&fullRepresentation=false&ontology=gogocompact"
	# println("Download ", url); download(url, tmpfile); println("Download done")
	# datas = response.body |> String |> JSON.parse
	datas = read(tmpfile, String) |> JSON.parse;
	for data in datas["data"]
		insert_gogocarto_element(gogoid, data)
	end
end

args = parse_commandline()
parse_gogocarto("herboristes")

#
# parse_producer("2201", "https://www.jours-de-marche.fr/producteur-local/la-ferme-de-mon-repos-2201.html", "la ferme de mon repos")
# parse_producer("1364", "https://www.jours-de-marche.fr/producteur-local/renauflor-1364.html", "renauflor")
# getXYFromAddress(" Mon repos 35730 Pleurtuit")


DBInterface.close!(dbConnection)

exit()
