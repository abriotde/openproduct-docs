#!/bin/env julia
using ArgParse

# 


# Update openproduct.producer
# 	set address = if(LOCATE(concat(postCode," ",city), address)>0, SUBSTR(address, 1, length(address)-length(concat(postCode," ",city))-2),address)
# where LOCATE(concat(postCode," ",city), address)>0;

# Update openproduct.producer
# set phoneNumber = replace(phoneNumber, " ","");

import DBInterface, HTTP, CSV, Gumbo, URIs
using DataFrames, Dates

using Cascadia

include("connect.jl")
dbConnection = OpenProduct.get_connection(ROOT_PATH)

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

function get_text_from_xpath(xpath::Selector, text::Gumbo.HTMLElement)
	elem = get_from_xpath(xpath, text)
	if ismissing(elem)
		elem = get_from_xpath(sel"div.alert", text)
		if !ismissing(elem)
			println("WARNING : ", Gumbo.text(elem))
		end
		missing
	else
		Gumbo.text(elem)
	end
end
function get_from_xpath(xpath::Selector, text::Gumbo.HTMLElement)
	for value in eachmatch(xpath, text)
		return value
	end
	missing
end
function parse_marquesdefrance_get_website(url::String)
	println("parse_marquesdefrance_get_website(",url,");")
	tmpfile = "parse_marquesdefrance_get_website.html"
	# println("Download ", url); download(url, tmpfile); println("Download done")
	# datas = read(tmpfile, String); html = Gumbo.parsehtml(datas)
	response = HTTP.get(url); html = response.body |> String |> Gumbo.parsehtml
	elem = get_from_xpath(sel"a[title='Voir le site officiel']", html.root)
	# elem = get_from_xpath(sel".py-3 > div:nth-child(2) > div:nth-child(1) > a:nth-child(1)", html.root)
	if ismissing(elem)
		elem
	else
		Gumbo.getattr(elem, "href")
	end
end
#=

=#
function parse_marquesdefrance_atelier(url::String)
	println("parse_marquesdefrance_atelier(",url,");")
	tmpfile = "parse_marquesdefrance_atelier.html"
	# println("Download ", url); download(url, tmpfile); println("Download done")
	# datas = read(tmpfile, String); html = Gumbo.parsehtml(datas)
	response = HTTP.get(url); html = response.body |> String |> Gumbo.parsehtml
	name = get_text_from_xpath(sel".sticky-top > div:nth-child(1) > div:nth-child(1) > h1:nth-child(1)", html.root)
	# println("Name: ", name)
	text = get_text_from_xpath(sel".sticky-top > div:nth-child(1) > div:nth-child(1) > p:nth-child(2)", html.root)
	website = String[]
	addressQuery = email = phoneNumber = phoneNumber2 = missing
	firstname = lastname = sourcekey = imageurl = missing
	addressQuery = get_text_from_xpath(sel"a[href='#map-canvas']", html.root)
	lat = lon = score = postCode = city = address = missing
	categories = "I"
	imageurl = missing
	for value in eachmatch(sel"div.col-12 > a", html.root)
		link = Gumbo.getattr(value, "href")
		txt = Gumbo.text(value)
		if link=="#map-canvas"
			addressQuery = txt
		elseif startswith("http:", link) || startswith("https:", link)
			push!(website, link)
		elseif startswith("tel:", link)
			if ismissing(phoneNumber)
				phoneNumber = push!(website, link[5:end])
			else ismissing(phoneNumber2)
				phoneNumber2 = push!(website, link[5:end])
			end
		end
	end
	if !ismissing(addressQuery)
		lat, lon , score, postCode, city, address = OpenProduct.getXYFromAddress2(addressQuery)
	end
	shortDescription = ""
	sep = "Producteur pour les marque : '"
	for value in eachmatch(sel"a.listing-card", html.root)
		shortDescription *= sep*Gumbo.getattr(value, "title")
		sep = "', '"
		brand_url = Gumbo.getattr(value, "href")
		website_0 = parse_marquesdefrance_get_website(brand_url)
		if !ismissing(website_0)
			push!(website, website_0)
		end
	end
	if shortDescription!=""
		shortDescription *= "'"
	end
	if ismissing(text)
		text = shortDescription
		println("Warning : no shop for '",name,"' (",url,") ?")
	end
	dateformater = dateformat"y-m-dTH:M:S"
	lastUpdateDate = now() # Dates.format(now(), dateformater)
	siret = openingHours = missing
	startdate = "1900-01-01"
	tag = 1 # PME
	producer = OpenProductProducer(
		lat, lon, 1.0, name, firstname, lastname, city, postCode,
		address, phoneNumber, phoneNumber2, siret, email, website,
		shortDescription, text, sourcekey, imageurl, openingHours, categories, 
		startdate, missing, lastUpdateDate, tag
	)
	id = insertOnDuplicateUpdate(dbConnection, producer)
	if id<=0
		println("Fail insert producer : ",producer)
	end
end

function parse_marquesdefrance()
	# scraping web selenium
	# https://www.pythoniaformation.com/blog/tutoriels-python-par-categories/automatiser-avec-python/comment-faire-web-scraping-selenium-python
	# https://datascientest.com/selenium-python-web-scraping
    lstfile = "./parse_marquesdefrance.lst"
	open(lstfile, "r") do fd
		for line in readlines(fd)
			parse_marquesdefrance_atelier(line)
		end
	end
	
end

args = parse_commandline()
parse_marquesdefrance()

#
# parse_producer("2201", "https://www.jours-de-marche.fr/producteur-local/la-ferme-de-mon-repos-2201.html", "la ferme de mon repos")
# parse_producer("1364", "https://www.jours-de-marche.fr/producteur-local/renauflor-1364.html", "renauflor")
# getXYFromAddress(" Mon repos 35730 Pleurtuit")


DBInterface.close!(dbConnection)

exit()
