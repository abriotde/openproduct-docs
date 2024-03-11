#!/usr/local/bin/julia
using ArgParse
import HTTP, JSON, URIs
using Cascadia
DEBUG = true

include("OpenProductProducer.jl")


######### https://producteurspl.gogocarto.fr/api/elements.json?limit=1000&categories=
#############


#=
Use https://overpass-turbo.eu to create query
=#
function getdatas_gogocarto(source::AbstractString)
	try
		if(DEBUG); println("getdatas_gogocarto()"); end
		tmpfile = "./query_gogocarto.json"
		if false
			adressAPIurl = "https://"*source*".gogocarto.fr/api/elements.json?limit=1000&categories="
			response = HTTP.get(adressAPIurl)
			write(tmpfile, response.body)
			# datas = response.body |> String |> JSON.parse
		end
		datas = read(tmpfile, String) |> JSON.parse;
		# println(datas);
		datas
    catch err
        println("ERROR : fail getdatas_gogocarto() : ",err)
		nothing
    end
end

function getCategory(name::AbstractString)
	if name=="Éleveur" || name=="Bovins viande" || name=="Ovins" || name=="Porcins" || (!isnothing(findfirst("Volailles", name)))
		return "A2"
	elseif name=="Maraîcher" || name=="Maraîchage" || name=="Arboriculteur"
		return "AM"
	elseif name=="Apiculteur" || name=="Héliciculteur" || name=="Miel"
		return "AN"
	elseif name=="Pisciculteur"
		return "AP"
	elseif name=="Spirulinier" || name=="Pâtissier" || name=="Boulanger" || name=="Chocolatier"
		return "AX"
	elseif name=="Herboriste" || name=="Pépiniériste"
		return "3"
	elseif name=="Fromager" || name=="Laitier" || (!isnothing(findfirst("fromages et produits laitiers", name)))
		return "AL"
	elseif name=="Viticulture" || name=="Fruits" || name=="Brasseur" || name=="Distillateur" || name=="Confiturier" || name=="Vigneron" || name=="Vinaigrier"
		return "AF"
	elseif name=="Grandes cultures"
		return "AC"
	elseif name=="Myciculteur"
		return "AF3"
	elseif name=="Fleuriste"
		return "4"
	elseif name=="Autres"
		return ""
	else
		println("Error getCategory(",name,") : unknown category")
		# exit(1)
	end
	""
end
#=
	@return OpenProductProducer
=#
function getOpenProductProducer(producer::Dict, source::AbstractString)
	# println(producer)
	name = getKey(producer, ["name"], "")
	geo = producer["geo"]
	lat = geo["latitude"]
	lon = geo["longitude"]
	addr = producer["address"]
	address = getKey(addr, ["streetAddress"], "")
	city =  getKey(addr, ["addressLocality"], "")
	postCode = getKey(addr, ["postalCode"], "")
	shortDescription = categories = ""
	c = producer["categories"][1]
	categories = getCategory(c)
	shortDescription = c
	score = 0.99
	openingHours = text = website = phoneNumber = phoneNumber2 = email = siret = ""
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
		"", ""
	)
end


function query_gogocarto(source::AbstractString)
	nb::Int = 0
	datas = getdatas_gogocarto(source)
	for data in datas["data"]
		# if DEBUG; println(data); end
		producer = getOpenProductProducer(data, source)
		println("Producer:",producer)
		if producer isa Bool
			println("ERROR : Fail getOpenProductProducer()")
		else
			nb += 1
			insertOnDuplicateUpdate(producer, force=true)
		end
	end
	nb
end

# query_gogocarto("producteurspl")
query_gogocarto("collectiffermierdupoitou")

DBInterface.close!(dbConnection)

exit(0)
