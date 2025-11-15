#!/usr/local/bin/julia
using ArgParse

######### https://data.economie.gouv.fr/api/explore/v2.1/catalog/datasets/entreprises-du-patrimoine-vivant-epv/exports/csv?lang=fr&timezone=Europe%2FParis&use_labels=true&delimiter=%3B #############
# TODO : Get number of pages per regions.


# Update openproduct.producer
# 	set address = if(LOCATE(concat(postCode," ",city), address)>0, SUBSTR(address, 1, length(address)-length(concat(postCode," ",city))-2),address)
# where LOCATE(concat(postCode," ",city), address)>0;

# Update openproduct.producer
# set phoneNumber = replace(phoneNumber, " ","");

import MySQL, DBInterface, HTTP, CSV, Gumbo, URIs
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
function parse_bvbr_producer(name, url)
	println("parse_bvbr_producer(",name, ", ",url,");")
	tmpfile = "parse_bvbr_producer.html"
	url = url*"about/#tab_links_area"
	println("Download ", url); download(url, tmpfile); println("Download done")
	datas = read(tmpfile, String); html = Gumbo.parsehtml(datas)
	# response = HTTP.get(url); html = response.body |> String |> Gumbo.parsehtml
	website = []
	addressQuery = email = phoneNumber = phoneNumber2 = missing
	for link in eachmatch(sel"div#wcfm_store_header div.header_wrapper div.header_area a", html.root)
		href = Gumbo.getattr(link, "href")
		value = Gumbo.text(link)
		# println(" - ", value, " : ", href)
		if href=='#'
			println("TTTT");
		elseif startswith(href, "https://")
			val = href[9:end]
			if startswith(val, "google.com/")
				addressQuery = value
			elseif startswith(val, "www.facebook.com/")
				push!(website, href)
			elseif startswith(val, "www.instagram.com/")
				push!(website, href)
			else
				println("Unknown url : ", href)
			end
		elseif startswith(href, "mailto:")
			email=href[8:end]
		elseif startswith(href, "tel:")
			phoneNumber=href[5:end]
		else
			println("Warning : Unknown link : '", href,"'")
		end
	end
	firstname = lastname = sourcekey = imageurl = missing
	for link in eachmatch(sel"div#wcfm_store_header h1.wcfm_store_title", html.root)
		firstname = lastname = Gumbo.text(link)
	end
	text = missing
	for link in eachmatch(sel"div#wcfmmp_store_about div.wcfm_store_description", html.root)
		text = Gumbo.text(link)
	end
	lat = lon = score = postCode = city = address = missing
	if !ismissing(addressQuery)
		lat, lon , score, postCode, city, address = getXYFromAddress(addressQuery)
	end
	categories = "A"
	imageurl = missing
	for link in eachmatch(sel"div.banner_img img", html.root)
		imageurl = Gumbo.getattr(link, "src")
	end
	shortDescription = ""
	for link in eachmatch(sel"div#wcfmmp-store-content div.categories_list li a", html.root)
		shortDescription *= Gumbo.text(link)
	end
	dateformater = dateformat"y-m-dTH:M:S"
	lastUpdateDate = now() # Dates.format(now(), dateformater)
	siret = openingHours = missing
	startdate = "1900-01-01"
	producer = OpenProductProducer(
		lat, lon, 1.0, name, firstname, lastname, city, postCode,
		address, phoneNumber, phoneNumber2, siret, email, website,
		shortDescription, text, sourcekey, imageurl, openingHours, categories, 
		startdate, missing, lastUpdateDate
	)
	# println(producer)
	insertOnDuplicateUpdate(dbConnection, producer)
end

function parse_bvbr()
    tmpfile = "./parse_bvbr.html"
	url="https://www.bvbr.org/marche-ambulant/"
	# println("Download ", url); download(url, tmpfile); println("Download done")
	response = HTTP.get(url); html = response.body |> String |> Gumbo.parsehtml
	# datas = read(tmpfile, String); html = Gumbo.parsehtml(datas)
	for producerLink in eachmatch(sel"div#secondary div#text-2 p a", html.root)
		name = Gumbo.text(producerLink)
		href = Gumbo.getattr(producerLink, "href")
		parse_bvbr_producer(name, href)
	end
end

args = parse_commandline()
parse_bvbr()

#
# parse_producer("2201", "https://www.jours-de-marche.fr/producteur-local/la-ferme-de-mon-repos-2201.html", "la ferme de mon repos")
# parse_producer("1364", "https://www.jours-de-marche.fr/producteur-local/renauflor-1364.html", "renauflor")
# getXYFromAddress(" Mon repos 35730 Pleurtuit")


DBInterface.close!(dbConnection)

exit()
