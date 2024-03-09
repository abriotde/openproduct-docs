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

import MySQL, DBInterface, HTTP, CSV, DataFrames, URIs

using Cascadia

regexIdProducer = Regex("producteur([0-9]+)")


include("OpenProductProducer.jl")


function parse_amapBearn()
    nbProducers = 0
	println("parse_amapBearn()")
	regexTitle = Regex("^<h4>(.*)</h4>\$")
	regexWebsite = Regex("(.*)<a\\s+target='blank'\\s+href='(http.*)'>Site Web</a>")
	tmpfile  = "parse_amapBearn.csv"
	url = "https://www.amap-bearn.fr/wp-content/uploads/sites/69/2018/04/geolocalisationettextes2.csv"
	# download(url,tmpfile) # HTTP.get(url).body
	csv_reader = CSV.File(HTTP.get(url).body, delim='	')
	for row in csv_reader
		# println(row)
		lat = row[:lat]
		lon = row[:lon]
		lat, lon, score, postcode, city, address = getAddressFromXY(lat, lon)
		name = row[:title]
		m = match(regexTitle, name)
		if m!=nothing
			name = m[1]
		end
		text = row[:description]
		website = ""
		m = match(regexWebsite, text)
		if m!=nothing
			text = m[1]
			website = m[2]
		end
		producer = OpenProductProducer(
			lat, lon, score, name, "","", city, postcode,
			address, "", "", "", "", website,
			"", text, "AMAP", "AG", # Only AMAP here
			"", ""
		)
		# println("producer : ", producer)
		insertOnDuplicateUpdate(producer, force=true)
	end
end

parse_amapBearn()

DBInterface.close!(dbConnection)

exit()
