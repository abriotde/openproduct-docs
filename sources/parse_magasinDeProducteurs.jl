#!/usr/local/bin/julia
using ArgParse

######### https://www.mon-producteur.com #############
# TODO : Get label, sell products
# TODO : manage inoherence, if line not insert


# Update openproduct.producer
# 	set address = if(LOCATE(concat(postCode," ",city), address)>0, SUBSTR(address, 1, length(address)-length(concat(postCode," ",city))-2),address)
# where LOCATE(concat(postCode," ",city), address)>0;

# Update openproduct.producer
# set phoneNumber = replace(phoneNumber, " ","");

import MySQL, DBInterface, HTTP, Gumbo, JSON, URIs

using Cascadia

regexIdProducer = Regex("producteur([0-9]+)")

include("connect.jl")

function parse_producer(url_prod, name)
    println("parse_producer(",url_prod,", ",name,")")
    response = HTTP.get(url_prod); html = response.body |> String |> Gumbo.parsehtml
	base_url, id = split(url_prod, "=")
    tmpfile = "./parse_magasindeproducteurs_"*id*".html"
	# download(url_prod,tmpfile); htmlStr = read(tmpfile, String); html = Gumbo.parsehtml(htmlStr)
    description = address = website = phoneNumber = email = openingHours = postCode = city = ""
    firstname = lastname = shortDescription = ""
    x = y = score = 0
    ok = 0
    i = 0
    for p in eachmatch(sel"div#presentation p", html.root)
    	# println(div)
    	val = Gumbo.text(p)
		if val!="" && val!="Ce magasin n'a pas encore mis à jour toutes ses informations.  Merci de votre indulgence"
			class = ""
			try
				class = Gumbo.getattr(p, "class")
			catch err
				class = "NO_CLASS"
			end
			if class=="a_justify"
				ok += 1
				description *= val*". "
			elseif class=="NO_CLASS"
				ok += 1
				description *= "Spécialités : "*val
			end
		end
    end
    for p in eachmatch(sel"img.picto", html.root)
		if shortDescription == ""
			shortDescription = "Produits : "
			ok += 1
		else
			shortDescription *= ", "
		end
    	shortDescription *=  Gumbo.getattr(p, "title")
	end
	i = 0
    for p in eachmatch(sel"div#infos_utiles div.contact p", html.root)
		i += 1
		val = Gumbo.text(p)
		if val!=""
			if i==1
				x, y , score, postCode, city, address = getXYFromAddress(val)
				if x>0
					ok += 2
				end
			elseif i==2
				phoneNumber = getPhoneNumber(val)
				ok += 1
			elseif i==3
				if val!="-"
					website = val
					ok += 1
				end
			end
		end
	end
    for p in eachmatch(sel"div#infos_utiles div.horaires p", html.root)
		if Gumbo.text(p)!="HORAIRES"
			println("Found horraire : ", Gumbo.text(p))
			exit();
		end
	end

    if ok > 2
        # (latitude, longitude, name, city, postCode,
        #  address, phoneNumber, siret, email, website,
        #  `text`, openingHours, geoprecision)
        values = [
            x, y, score, name, firstname, lastname, city, postCode,
            address, phoneNumber, 0, email, website,
            shortDescription, description, openingHours, "AG" # Only food product from that website
        ]
        println("Insert producer : ", values)
        DBInterface.execute(sqlInsert, values)
        1
    else
        println("ERROR : parse_producer(",url_prod,", ",name,") OK=",ok)
        0
    end
end

#=

=#
function parse_all()
    nbProducers = 0
    # try
        println("parse_all()")
        tmpfile = "./parse_magasindeproducteurs.html"
        url = "https://www.magasin-de-producteurs.fr/liste-des-magasins-de-producteurs.php"

		response = HTTP.get(url); html = response.body |> String |> Gumbo.parsehtml
		# download(url, tmpfile); htmlStr = read(tmpfile, String); html = Gumbo.parsehtml(htmlStr)

	    # Iterate over producers
	    for producerA in eachmatch(sel"ul#list_allmags li div.info_shop a", html.root)
			producerName = strip(Gumbo.text(producerA))
			url_prod = Gumbo.getattr(producerA, "href")
			println(url_prod, producerName)
	    	parse_producer("https://www.magasin-de-producteurs.fr/"*url_prod, producerName)
	    end
    # catch err
    #     println("ERROR : fail parse_all() : ",err)
    # end
end

parse_all()
# parse_producer("https://www.magasin-de-producteurs.fr/shop.php?id_shop=16", "Les Fermiers de la Dombes")


DBInterface.close!(dbConnection)

exit()
