#!/usr/local/bin/julia
using ArgParse

######### https://www.mon-producteur.com #############
# TODO : Get label, sell products
# TODO : manage inoherence, if line not insert


import MySQL, DBInterface, HTTP, Gumbo, JSON, URIs

using Cascadia


departements = Dict(
        1=>"ain",
        2=>"aisne",
        3=>"allier",
        4=>"alpes-de-haute-provence",
        5=>"hautes-alpes",
        6=>"alpes-maritimes",
        7=>"ardeche",
        8=>"ardennes",
        9=>"ariege",
        10=>"aube",
        11=>"aude",
        12=>"aveyron",
        13=>"bouches-du-rhone",
        14=>"calvados",
        15=>"cantal",
        16=>"charente",
        17=>"charente-maritime",
        18=>"cher",
        19=>"correze",
        20=>"corse",
        21=>"cote-d-or",
        22=>"cotes-d-armor",
        23=>"creuse",
        24=>"dordogne",
        25=>"doubs",
        26=>"drome",
        27=>"eure",
        28=>"eure-et-loir",
        29=>"finistere",
        30=>"gard",
        31=>"haute-garonne",
        32=>"gers",
        33=>"gironde",
        34=>"herault",
        35=>"ille-et-vilaine",
        36=>"indre",
        37=>"indre-et-loire",
        38=>"isere",
        39=>"jura",
        40=>"landes",
        41=>"loir-et-cher",
        42=>"loire",
        43=>"haute-loire",
        44=>"loire-atlantique",
        45=>"loiret",
        46=>"lot",
        47=>"lot-et-garonne",
        48=>"lozere",
        49=>"maine-et-loire",
        50=>"manche",
        51=>"marne",
        52=>"haute-marne",
        53=>"mayenne",
        54=>"meurthe-et-moselle",
        55=>"meuse",
        56=>"morbihan",
        57=>"moselle",
        58=>"nievre",
        59=>"nord",
        60=>"oise",
        61=>"orne",
        62=>"pas-de-calais",
        63=>"puy-de-dome",
        64=>"pyrenees-atlantiques",
        65=>"hautes-pyrenees",
        66=>"pyrenees-orientales",
        67=>"bas-rhin",
        68=>"haut-rhin",
        69=>"rhone",
        70=>"haute-saone",
        71=>"saone-et-loire",
        72=>"sarthe",
        73=>"savoie",
        74=>"haute-savoie",
        75=>"paris",
        76=>"seine-maritime",
        77=>"seine-et-marne",
        78=>"yvelines",
        79=>"deux-sevres",
        80=>"somme",
        81=>"tarn",
        82=>"tarn-et-garonne",
        83=>"var",
        84=>"vaucluse",
        85=>"vendee",
        86=>"vienne",
        87=>"haute-vienne",
        88=>"vosges",
        89=>"yonne",
        90=>"territoire-de-belfort",
        91=>"essonne",
        92=>"hauts-de-seine",
        93=>"seine-saint-denis",
        94=>"val-de-marne",
        95=>"val-d-oise"
)
regexIdProducer = Regex("producteur([0-9]+)")

include("connect.jl")

function parse_commandline()
	s = ArgParseSettings()
	@add_arg_table s begin
	 "--dept"
		 help = "Import a uniq departement."
		 arg_type = Int
	 "--all", "-a"
		 help = "Import all departements (default none)."
		 action = :store_true
	end
	return parse_args(s)
end

function parse_producer(url_prod, name, shortDescription)
    println("parse_producer(",url_prod,", ",name,", ",shortDescription,")")
    response = HTTP.get(url_prod)
    html = response.body |> String |> Gumbo.parsehtml
    tmpfile = "./parse_monproducteur_prod_"*name*".html"
    # download(url_prod,tmpfile); htmlStr = read(tmpfile, String); html = Gumbo.parsehtml(htmlStr)
    description = address = website = phoneNumber = email = openingHours = postCode = city = ""
    firstname = lastname = description = ""
    x = y = score = 0
    ok = 0
    i = 0
    for div in eachmatch(sel"div#product_coords p", html.root)
    	# println(div)
    	vals = split.(string(div), "<br/>")
    	for val in vals
	    	val = strip(replace(val, r"</?p>"=>""))
    		# println("- ",i," : ",val)
    		if val!=""
				if i==0
					lastname = val
					ok += 1
				elseif i==1
                	x, y , score, postCode, city, address = getXYFromAddress(val)
					ok += 2
				elseif i==3
					phoneNumber = getPhoneNumber(val)
					ok += 1
				end
			end
    		i+=1
    	end
    end
    for div in eachmatch(sel"div.titre-prod h2", html.root)
    	name = strip(Gumbo.text(div))
    end
    for div in eachmatch(sel"div.titre-prod h3", html.root)
    	shortDescription =  strip(Gumbo.text(div))
    end
    sep = "Produits proposés : "
    for div in eachmatch(sel"td.precisions", html.root)
    	description *=  sep*strip(Gumbo.text(div))
	    sep = "; "
    end


    if ok > 2
        # (latitude, longitude, name, city, postCode,
        #  address, phoneNumber, siret, email, website,
        #  `text`, openingHours, geoprecision)
        values = [
            x, y, score, name, firstname, lastname, city, postCode,
            address, phoneNumber, 0, email, website,
            shortDescription, description, openingHours, "A" # Only food product from that website
        ]
        println("Insert producer : ", values)
        DBInterface.execute(sqlInsert, values)
        1
    else
        println("ERROR : parse_producer(",url_prod,", ",producer,", ",shortDescription,") OK=",ok)
        0
    end
end

#=

=#
function parse_departement(deptnum::Int64; pageNum::Int64=0)
    nbProducers = 0
    # try
        deptname = departements[deptnum]
        println("parse_departement(",deptnum,", ",deptname,", page=", pageNum,")")
        deptnumStr = lpad(string(deptnum), 2, "0")
        tmpfile = "./parse_monproducteur_"*deptnumStr*".html"
        url = "https://www.mon-producteur.com/recherche/"*deptnumStr*"-"*deptname
        if pageNum>0
        	url = url*"?p="*string(pageNum)
        end
        # download(url,tmpfile); htmlStr = read(tmpfile, String); html = Gumbo.parsehtml(htmlStr)
        response = HTTP.get(url)
        html = response.body |> String |> Gumbo.parsehtml
        if pageNum==0 # We want all pages, we get the first one by default, get the others
			for pagination in eachmatch(sel"div#pagination ul.pagination li a", html.root)
				paginationVal = Gumbo.text(pagination)
				if paginationVal[1]>='0' && paginationVal[1]<='9'
					parse_departement(deptnum, pageNum=parse(Int64, paginationVal))
				end
			end
		end

	    # Iterate over <div id="producteur2201" class="col-12">
	    for producerDiv in eachmatch(sel"ul#product_list li h3", html.root)
	    	url_prod = ""
	    	producerName = ""
	    	shortDescription = ""
	    	for child in Gumbo.children(producerDiv)
	    		childtype = typeof(child)
	    		if childtype==Gumbo.HTMLText
		    		shortDescription = strip(Gumbo.text(child))
	    		elseif childtype==Gumbo.HTMLElement{:a}
		    		url_prod = Gumbo.getattr(child, "href")
		    		producerName = Gumbo.getattr(child, "title")
	    		end
	    	end
	    	parse_producer(url_prod, producerName, shortDescription)
	    end
    # catch err
    #     println("ERROR : fail parse_departement(",deptnum,") : ",err)
    # end
end

args = parse_commandline()
if args["dept"]!=nothing
    parse_departement(args["dept"])
elseif args["all"]!=nothing
     for num in 1:99
     	if haskey(departements, num)
     		parse_departement(num)
     	end
     end
end

#
# parse_producer("2201", "https://www.jours-de-marche.fr/producteur-local/la-ferme-de-mon-repos-2201.html", "la ferme de mon repos")
# parse_producer("1364", "https://www.jours-de-marche.fr/producteur-local/renauflor-1364.html", "renauflor")
# getXYFromAddress(" Mon repos 35730 Pleurtuit")


DBInterface.close!(dbConnection)

exit()
