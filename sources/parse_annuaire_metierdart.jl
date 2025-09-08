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

using Cascadia, Dates


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

include("connect.jl")
using .OpenProduct

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

categoriesByUnivers = Dict(
	"Equipement de la maison et agencement intérieur" => "O",
	"Jeux et jouets" => "OU",
	"Ameublement et Décoration" => "O0",
	"Orfèvrerie" => "O0",
	"Luminaires" => "O0",
	"Objets décoratifs" => "O0",
	"Saveurs sucrées" => "AX",
	"Vannier" => "O0",
	"Maître verrier (Vitrailliste)" => "OV",
	"Brodeur" => "HT",
	"Couverture" => "",
	"Toiture" => "",
	"Charpente" => "",
	"Sculpture et travail de la pierre" => "OZ",
	"Equipements et accessoires de cuisine" => "OF",
	"Ferronnerie" => "OF",
	"Orfèvre" => "OF",
	"Tailleur de pierre" => "OZ",
	"Céramiste" => "OQ",
	"Mobilier" => "O0",
	"Haute-couture et prêt-à-porter" => "HT",
	"Lunetier" => "H1",
	"Menuisier" => "O0",
	"Sellier-maroquinier" => "H2",
	"Luthier en guitare et/ou Restaurateur de guitares" => "O0",
	"Peintre sur mobilier" => "O0",
	"Ebéniste" => "O0",
	"Musique" => "O5",
	"Imprimeur" => "OS",
	"Bijoutier fantaisie" => "OB",
	"Fabricant de serrures" => "OF",
	"Cartonnier" => "O",
	"Coutelier" => "OR",
	"Feutrier" => "HT",
	"Tisserand" => "HT",
	"Boissons et spiritueux" => "AF",
)

function parse_producer(url_prod)
	println("parse_producer(",url_prod,")")
    
    response = HTTP.get(url_prod); html = response.body |> String |> Gumbo.parsehtml
    tmpfile = "./parse_annuaire_metierdart_prod.html"
    # download(url_prod, tmpfile); htmlStr = read(tmpfile, String); html = Gumbo.parsehtml(htmlStr)
    description = address = website = phoneNumber = email = openingHours = postCode = city = ""
    firstname = lastname = shortDescription = ""
    x = y = score = 0
    ok = 0
    i = 0
	name = ""
	for div in eachmatch(sel"h1.presentation-intro__title span", html.root)
		name = Gumbo.text(div)
	end
	addressQuery = website = ""
	for div in eachmatch(sel"div.contact-card__content", html.root)
		for sdiv in eachmatch(sel"address span", div)
			addressQuery = Gumbo.text(sdiv)
			addressQuery = rstrip(replace(addressQuery, "\n"=>","))
		end
		for sdiv in eachmatch(sel"a", div)
			website = Gumbo.getattr(sdiv, "href") |> String
		end
	end
    x, y , score, postCode, city, address = getXYFromAddress(addressQuery)
    if x==0
    	return 0
    end
	email = phoneNumber = univers = ""
	for div in eachmatch(sel"ul.presentation-summary-buttons a", html.root)
		href = Gumbo.getattr(div, "href") |> String
		if startswith(href, "tel:")
			phoneNumber = replace(href[5:end], " "=>"")
		elseif startswith(href, "http:") || startswith(href, "https:")
			website = href
		elseif startswith(href, "mailto:")
			email = href[8:end]
		end
	end
	createDate = category = ""
	univers = description = sep = ""
	for div in eachmatch(sel"dl.presentation-summary-details", html.root)
		values = []
		for sdiv in eachmatch(sel"dd", div)
			push!(values, Gumbo.text(sdiv))
			# println("Value: ", Gumbo.text(sdiv))
		end
		i=0
		for sdiv in eachmatch(sel"dt", div)
			key = lowercase(strip(Gumbo.text(sdiv)))
			value = values[i+1]
			if key=="domaines / métier d'art"
				univers = value
			elseif key=="univers de marché"
				if univers==""
					univers = value
				end
				shortDescription *= sep*key*": "*value
				sep = "; "
			elseif key=="année de création"
				createDate *= "01-01-"*value
			elseif key!="région"
				# println("Key: ", key, " Value: ", value)
				shortDescription *= sep*key*": "*value
				sep = "; "
			end
			i+=1
		end
	end
	for div in eachmatch(sel"div.presentation-info-content p", html.root)
		description *= Gumbo.text(div)
	end
	for uni in split(univers, [';', ',', '-'])
		uni = strip(uni)
		if category=="" || category=="_"
			category = get(categoriesByUnivers, uni, "_")
		end
	end
	if category == "_"
		# println("WARNING : Unknown univers '", univers, "' for producer ", name, description, "")
		println("'", univers, "' => '',")
	end
	siret = ""

	producerObj = OpenProductProducer(
		x, y, score, name, firstname, lastname, 
		city, postCode, address, phoneNumber, "",
		siret, email, website,
		shortDescription, description, openingHours, category, createDate, "", now()
	)
	# println("Insert producer : ", producerObj)
	insertOnDuplicateUpdate(producerObj, forceInsert=true)
	1
end
function read_json(file)
    open(file,"r") do f
        return JSON.parse(f)
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
        
        areaNumStr = string(areaNum)
        tmpfile = "./parse_annuaire_metierdart_"*areaNumStr*".html"
        base_url = "https://annuaire.institut-savoirfaire.fr"
        url = base_url*"/recherche?mode=0&id_region=region"*areaNumStr*"&page="*string(pageNum)

		url = "https://annuaire.institut-savoirfaire.fr/views/ajax?_wrapper_format=drupal_ajax&view_name=authors&view_display_id=list&view_args=&view_path=%2Fannuaire-des-acteurs&view_base_path=annuaire-des-acteurs&view_dom_id=19a22ce7c0092a6eb3df19920f7024de3201c02a554c8feedf88a6d1407e61ae&pager_element=0&region="*areaNumStr*"&business_type=All&page=1&_drupal_ajax=1&ajax_page_state%5Btheme%5D=inma&ajax_page_state%5Btheme_token%5D=&ajax_page_state%5Blibraries%5D=eJx1kVuWwyAIhjcU45JyiNKUFsUB005m9WNq05k-9IUDHz83hRirQN48PJ3xpJLrMDP8bH4mGeEC30MQRR91LcDjSTQNC8qJkOOUoPhXsIgsjDt7FyTQK-oUeLWK-p6TGypDKZSXLrNCEbUJdKCcwMNaz6KOyWoHsyLEoGuaexxAozPeqw5QcRHderSwzMDd35u0QY5yVXGGoZLkZ0paWYvc3u5Ai3Qv490Yaz0mmAQC_ttp6kv6dgfm6L5W1M0VUEjYauxNE8lgZnRX3O6i0VzjEiSVNgAHQ9BwnqDQ9J_7D3ywrT1p8jMYDhXCxfzDvnytCGugdm5uXzt-yBjqjQLanr9RO9Y_7JgkrowdTZRPlKniZEGFuUvcQV2nvzvM504"
        println("parse_area(",areaNum,", page=", pageNum,") : url=", url)
        # download(url, tmpfile); json = read_json(tmpfile)
    	response = HTTP.get(url); json = response.body |> String |> JSON.parse
		settings = json[1]["settings"]
		settings = get(settings, "geofield_google_map", [])
		# println("JSON:",settings)
		for i in keys(settings)
			data = settings[i]["data"]["features"]
			for d in data
				link = d["properties"]["data"]["title"]
				# println("   => ", link)
				m = match(r"<a href=\"([^ \"]*)\".*", link)
				if !isnothing(m)
					# println("Link is ", m[1])
					nbProducers += parse_producer(base_url*m[1])
				end
			end
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


DBInterface.close!(dbConnection)

exit()
