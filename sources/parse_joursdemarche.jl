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

include("OpenProductProducer.jl")

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

function parse_producer(id, url, name)
    println("parse_producer(",id,", ",url,", ",name,")")
    response = HTTP.get(url)
    html = response.body |> String |> Gumbo.parsehtml
    divNb = 1
    description = address = website = phoneNumber = email = openingHours = postCode = city = ""
    x = y = score = 0

    ok = 0
    for infoDiv in eachmatch(sel"div.rounded", html.root)
        # println(infoDiv)
        if divNb==1
            # println("div nb 1")
            # Get phoneNumber
            for phoneNumberDiv in eachmatch(sel"a.btn-jaune", infoDiv)
                phoneNumber = getPhoneNumber(Gumbo.getattr(phoneNumberDiv, "href"))
                # println("phoneNumber:",phoneNumber)
            end
            # Get descriptions
            for textDiv in eachmatch(sel"p:not(.visible-xs)", infoDiv)
                description = Gumbo.text(textDiv)
                # println("description:", description)
            end
        elseif divNb==2
            # println("div nb 2")
            # Get address
            for addressP in eachmatch(sel"p", infoDiv)
                vals = split.(string(addressP), "<br/>")
                address = join(vals[3:length(vals)])
                address = replace(address, "</p>" => "", "<br/>"=>"", r"\s+"=>" ");
                # println("address:", address)
                x, y , score, postCode, city = getXYFromAddress(address)
                ok += 2
            end
            # Get phoneNumber - email - website
            for aLink in eachmatch(sel"a", infoDiv)
                href = Gumbo.getattr(aLink, "href")
                indexType = findfirst(":", href)[1]
                type = first(href, (indexType-1))
                if type=="tel"
                    phoneNumber = href[indexType+1:length(href)]
                    ok += 1
                elseif type=="mailto"
                    email = href[indexType+1:length(href)]
                    ok += 1
                elseif type=="http" || type=="https"
                    website = href
                    ok += 1
                else
                    println("Warning : unthreated link href type : ",type)
                end
            end
            # println("email:", email, "; website:",website, "; phone:",phoneNumber)
        elseif divNb==4
            # Get openingHours
            val = string(infoDiv)
            if findfirst("Lieux de vente", Gumbo.text(infoDiv))!=nothing
                vals = split.(val, "<br/>")
                if length(vals)>2
                    openingHours = vals[2]
                    ok += 1
                end
                # println("openingHours:", openingHours)
            end
        end
        divNb += 1
    end
    if ok > 2
        # (latitude, longitude, name, city, postCode,
        #  address, phoneNumber, siret, email, website,
        #  `text`, openingHours, geoprecision)
        producer = OpenProductProducer(
            x, y, score, name, "","", city, postCode,
            address, phoneNumber, "", email, website,
            "", description, openingHours, "A", # Only food product from that website
			"", ""
		)
        println("producer : ", producer)
		insertOnDuplicateUpdate(producer)
        1
    else
        println("ERROR : parse_producer(",id,", ",url,", ",name,") OK=",ok)
        0
    end
end


function parse_departement(deptnum)
    nbProducers = 0
    try
        deptname = departements[deptnum]
        println("parse_departement(",deptnum,", ",deptname,")")
        deptnumStr = lpad(string(deptnum), 2, "0")
        tmpfile = "./parse_joursdemarche_"*deptnumStr*".html"
        url = "https://www.jours-de-marche.fr/producteur-local/"*deptnumStr*"-"*deptname*"/"
        download(url,tmpfile)
        # response = HTTP.get(url)
        # html = response.body |> String |> parsehtml
        htmlStr = read(tmpfile, String)
        html = Gumbo.parsehtml(htmlStr)
        # Iterate over <div id="producteur2201" class="col-12">
        for producerDiv in eachmatch(sel"div.col-12", html.root)
            id = try
                Gumbo.getattr(producerDiv, "id")
            catch e
                ""
            end
            m=match(regexIdProducer, id)
            if m!=nothing
                producerId = m[1]
                # println(producerDiv)
                for link in eachmatch(sel"h3 a", producerDiv)
                    producerUrl = Gumbo.getattr(link, "href")
                    # println("link:",producerUrl)
                    println("Producer nb ", nbProducers)
                    nbProducers += parse_producer(producerId, producerUrl, Gumbo.text(link))
                end
            end
        end
    catch err
        println("ERROR : fail parse_departement(",deptnum,") : ",err)
    end
end

args = parse_commandline()
if args["dept"]!=nothing
    parse_departement(args["dept"])
elseif args["all"]!=nothing
     for num in departements
         parse_departement(num.first)
     end
end

#
# parse_producer("2201", "https://www.jours-de-marche.fr/producteur-local/la-ferme-de-mon-repos-2201.html", "la ferme de mon repos")
# parse_producer("1364", "https://www.jours-de-marche.fr/producteur-local/renauflor-1364.html", "renauflor")



DBInterface.close!(dbConnection)

exit()
