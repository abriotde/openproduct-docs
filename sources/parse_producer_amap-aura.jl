#!/usr/local/bin/julia --startup=no
using ArgParse

######### https://www.jours-de-marche.fr/producteur-local #############
# TODO : Get label, sell products
# TODO : manage inoherence, if line not insert

DEBUG = false

# Update openproduct.producer
# 	set address = if(LOCATE(concat(postCode," ",city), address)>0, SUBSTR(address, 1, length(address)-length(concat(postCode," ",city))-2),address)
# where LOCATE(concat(postCode," ",city), address)>0;

# Update openproduct.producer
# set phoneNumber = replace(phoneNumber, " ","");

import MySQL, DBInterface, HTTP, Gumbo, JSON, URIs

using Cascadia

regexIdProducer = Regex("producteur([0-9]+)")

include("OpenProductProducer.jl")



function parse_proucer_amapAura()
    nbProducers = 0
	println("parse_proucer_amapAura()")
	tmpfile = "./parse_proucer_amapAura.json"
	url = "https://amap-aura.org/wp-json/cap/v1/amaps?mode=geoJSON&filter=amap&cp=69,01,73,38,74,15,43,63,03,26,07,42"
	# download(url,tmpfile)
	# response = HTTP.get(url)
	# jsonDatas = response.body |> String |> JSON.parse
	jsonDatas = read(tmpfile, String) |> JSON.parse
	for data in jsonDatas["features"]
		if data["type"]!="Feature"
			println("ERROR : parse_proucer_amapAura() : Not a Feature : ", )
			exit(1)
		end
		# println(data)
		vals = data["properties"]
		coord = vals["coordGps"]
		lat = parse(Float64, coord["latitude"])
		lon = parse(Float64, coord["longitude"])
		email = getKey(vals, ["email"], "")
		hours = vals["livraisonHoraires"]
		openingHours = ""
		for h in hours
			openingHours *= h["saison"] *" : "* h["jour"]*": "*h["debut"] *"-"* h["fin"]*"; "
		end
		website = getKey(vals, ["url"], "")
		description = "Production : "
		if vals["typeProduction"]!=nothing
			for p in vals["typeProduction"]
				if p!=nothing
					description *= ", "*p
				end
			end
		end
		addr = vals["adresse"]
		city = addr["ville"]
		postCode = addr["cp"]
		address = addr["rue"]
		producer = OpenProductProducer(
			lat, lon, 0.9, vals["nom"], "","", city, postCode,
			address, "", "", "", email, website,
			"AMAP", description, openingHours, "AG", # Only food product from that website
			"", ""
		)
		nbProducers += 1
		# println("producer : ", producer)
		if vals["amapEtat"]!="attente"
			if (vals["amapEtat"]!="fonctionnement" && vals["amapEtat"]!="creation") || vals["type"]!="amap"
				println("ERROR : parse_proucer_amapAura() : Not activ producer : ", vals["amapEtat"])
				exit(2)
			end
			insertOnDuplicateUpdate(producer, forceInsert=true)
		end
	end
	nbProducers
end

parse_proucer_amapAura()


DBInterface.close!(dbConnection)

exit()
