#!/usr/local/bin/julia
using ArgParse

######### https://www.annuaire-metiersdart.com/recherche?mode=0&id_region=region4&page=1 #############
# TODO : Get number of pages per regions.


# Update openproduct.producer
# 	set address = if(LOCATE(concat(postCode," ",city), address)>0, SUBSTR(address, 1, length(address)-length(concat(postCode," ",city))-2),address)
# where LOCATE(concat(postCode," ",city), address)>0;

# Update openproduct.producer
# set phoneNumber = replace(phoneNumber, " ","");

import MySQL, DBInterface, HTTP, Gumbo, JSON, URIs

using Cascadia


areas = Dict(
        2=>19,
        4=>16,
        5=>18,
        6=>30,
        7=>22,
        11=>31,
        13=>23,
        15=>45,
        18=>45,
        19=>51,
        21=>31,
        23=>1
)
regexIdProducer = Regex("producteur([0-9]+)")

 fields = [
 	"name", "firstname", "lastname", 
 	"city", "postCode", "address", 
 	"phoneNumber", "siret", "email", "website", 
 	"shortDescription", "`text`", "openingHours", "categories"
 ]
sql::String = "Insert ignore into openproduct.producer (latitude, longitude, geoprecision"
for field in fields
	global sql *= ","*field
end
sql *= ") values (?,?,?"
for field in fields
	global sql *= ",?"
end
sql *= ") on duplicate key update "
sep = ""
for field in fields
	global sql *= sep*field*" = if(length(coalesce("*field*",''))<length(values("*field*")), values("*field*"), "*field*")"
	global sep = ","
end
# println("SQL:",sql)

conn = DBInterface.connect(MySQL.Connection, "Localhost", "root", "osiris")
sqlInsert = DBInterface.prepare(conn, sql)

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

function getPhoneNumber(phoneString)
	phoneNumber = ""
	for c in phoneString
		if c>='0' && c<='9'
			phoneNumber *= c
		end
	end
	phoneNumber
end

function getXYFromAddress(address)
	try
		println("getXYFromAddress(",address,")")
		adressAPIurl = "https://api-adresse.data.gouv.fr/search/?q="
		address = replace(strip(address), "\""=>"")
		url = adressAPIurl * URIs.escapeuri(address)
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
        println("Error : fail getXYFromAddress(",address,") : ",err)
        [0, 0, 0, 0, "", address]
    end
end


function parse_producer(url_prod, name)
    println("parse_producer(",url_prod,", ",name,")")
    
    response = HTTP.get(url_prod); html = response.body |> String |> Gumbo.parsehtml
    tmpfile = "./parse_annuaire_metierdart_prod_"*name*".html"
    # download(url_prod, tmpfile); htmlStr = read(tmpfile, String); html = Gumbo.parsehtml(htmlStr)
    description = address = website = phoneNumber = email = openingHours = postCode = city = ""
    firstname = lastname = shortDescription = ""
    x = y = score = 0
    ok = 0
    i = 0
    key = value = ""
    for div in eachmatch(sel"div#details-artisan ul li", html.root)
    	for elem in Gumbo.children(div)
    		if typeof(elem)==Gumbo.HTMLText
    			value = Gumbo.text(elem)
    		elseif Gumbo.tag(elem) == :strong
    			key = Gumbo.text(elem)
				key = rstrip(replace(key, ":"=>""))
    		end
    	end
    	# println(key, " => ", value)
    	if value!=""
			if key=="MÉTIER"
				shortDescription = value
				ok += 1
			elseif key=="DIPLÔMES" || key =="SPÉCIALITÉ" || key =="TYPE D'ACTIVITÉ" || key =="SECTEUR"
				description *= key*" : "*value*"; "
				ok += 1
			end
    	end
    end
    # println("Then:")
    for div in eachmatch(sel"div#bloc-coordonnees ul li", html.root)
    	for elem in Gumbo.children(div)
    		if typeof(elem)==Gumbo.HTMLText
    			value = strip(Gumbo.text(elem))
    		elseif Gumbo.tag(elem) == :strong
    			key = Gumbo.text(elem)
				key = rstrip(replace(key, ":"=>""))
    		elseif Gumbo.tag(elem) == :a
    			key = Gumbo.getattr(div, "class")
    			value = Gumbo.getattr(elem, "href")
    		end
    	end
    	# println(key, " => ", value)
    	if value!=""
			if key=="ADRESSE"
				m = match(r"\(.*\)(.*)", value)
				if m!=nothing
					value = m[1]
				end
				if match(r"[a-zA-Z]+", value)!=nothing
					address = value
				else
					println("Error : Address '",value,"' is Invalid!")
				end
			elseif key=="CODE POSTAL"
				postCode = getPhoneNumber(value)
			elseif key=="VILLE"
				city = value
				m = match(r"(?i)(.*) Cedex",city)
				if m!=nothing
					city = m[1]
				end
			elseif key=="PRENOM & NOM"
				firstname = lastname = value
			elseif key=="TÉLÉPHONE" || key=="TÉLÉPHONE PROFESSIONNEL"
				phoneNumber = getPhoneNumber(value)
			elseif key=="email"
				m = match(r"mailto:(.*)", value)
				if m!=nothing
					value = m[1]
				end
				email = value
			elseif key=="www"
				website = value
			end
    	end
    end
    addressQuery = postCode*" "*city
    if address!=""
    	addressQuery = address*", "*addressQuery
    end
    x, y , score, postCode, city, address = getXYFromAddress(addressQuery)
    if x==0
    	return 0
    end


    if ok > 2
        # (latitude, longitude, name, city, postCode,
        #  address, phoneNumber, siret, email, website,
        #  `text`, openingHours, geoprecision)
        values = [
            x, y, score, name, firstname, lastname, city, postCode,
            address, phoneNumber, 0, email, website,
            shortDescription, description, openingHours, "O" # Only food product from that website
        ]
        println("Insert producer : ", values)
        DBInterface.execute(sqlInsert, values)
        1
    else
        println("Error : parse_producer(",url_prod,", ",name,") OK=",ok)
        0
    end
end

#=

=#
function parse_area(areaNum::Int64; pageNum::Int64=0)
    nbProducers = 0
    # try
    	if pageNum==0
    		numberOfPages = areas[areaNum]
    		nextPageNum = 1
    		while nextPageNum>0
    			nextPageNum = parse_area(areaNum, pageNum=nextPageNum)
    		end
			return
    	end
        
        println("parse_area(",areaNum,", page=", pageNum,")")
        areaNumStr = string(areaNum)
        tmpfile = "./parse_annuaire_metierdart_"*areaNumStr*".html"
        base_url = "https://www.annuaire-metiersdart.com"
        url = base_url*"/recherche?mode=0&id_region=region"*areaNumStr*"&page="*string(pageNum)
        
        # download(url,tmpfile); htmlStr = read(tmpfile, String); html = Gumbo.parsehtml(htmlStr)
        response = HTTP.get(url); html = response.body |> String |> Gumbo.parsehtml

	    # Iterate over <div id="producteur2201" class="col-12">
	    for producerDiv in eachmatch(sel"div#liste-reponses ul.item li a", html.root)
		    url_prod = Gumbo.getattr(producerDiv, "href")
		    producerName = Gumbo.getattr(producerDiv, "title")
		    if url_prod=="/annuaire/"
		    	println("Error : Page not exists for ", producerName)
		    else
		    	parse_producer(base_url*url_prod, producerName)
		    end
	    end
	    
	    for producerDiv in eachmatch(sel"div.pager a.suivant", html.root)
	    	return pageNum+1
	    end
	    0
    # catch err
    #     println("Error : fail parse_departement(",deptnum,") : ",err)
    # end
end


args = parse_commandline()
if args["area"]!=nothing
	println("Parse area", args["area"])
    parse_area(args["area"])
elseif args["all"]!=nothing
     for num in 1:25
     	if haskey(areas, num)
     		parse_area(num)
     	end
     end
end

#
# parse_producer("2201", "https://www.jours-de-marche.fr/producteur-local/la-ferme-de-mon-repos-2201.html", "la ferme de mon repos")
# parse_producer("1364", "https://www.jours-de-marche.fr/producteur-local/renauflor-1364.html", "renauflor")
# getXYFromAddress(" Mon repos 35730 Pleurtuit")


DBInterface.close!(conn)

exit()
