#!/usr/local/bin/julia --startup=no
using ArgParse

# TODO : OpenningHours && Case no description

DEBUG = false

import MySQL, DBInterface, HTTP, Gumbo, URIs

using Cascadia


include("OpenProductProducer.jl")


function parse_producer(url)
    println("parse_producer(",url,")")
	tmpfile = "parse_amap44_producer.html"
    # download(url,tmpfile); htmlStr = read(tmpfile, String); html = Gumbo.parsehtml(htmlStr)
    response = HTTP.get(url)
    html = response.body |> String |> Gumbo.parsehtml
    divNb = 1
    name = description = address = website = phoneNumber = phoneNumber2 = email = ""
	openingHours = postCode = city = ""
	firstname = lastname = ""
    lat = lon = score = 0
	tags = AbstractString[]

    ok = 0
	for producerHead in eachmatch(sel"div.entry-title-wrap", html.root)
		for title in eachmatch(sel"h1", producerHead)
			name = Gumbo.text(title)
			ok += 1
		end
		for title in eachmatch(sel"span.subtitle", producerHead)
			lastname = Gumbo.text(title)
			ok += 1
		end
		for tag in eachmatch(sel"nav.breadcrumbs a.breadcrumb-tag", producerHead)
			tagVal = Gumbo.text(tag)
			push!(tags, tagVal)
		end
	end
	for producerForm in eachmatch(sel"form#contact-owner-popup-form input[name=\"response-email-address\"]", html.root)
		email = Gumbo.getattr(producerForm, "value")
		ok += 1
	end
	for producerSection in eachmatch(sel"section#elm-content-6-main div#content", html.root)
		for div in eachmatch(sel"div.column-span-2 div.entry-content p#articlechapeau", producerSection)
			description = strip(Gumbo.text(div))
			 ok += 1
		end
		if description==""
			for div in eachmatch(sel"div.column-span-2 div.entry-content p", producerSection)
				t = strip(Gumbo.text(div))
				if t!=""
				   description = t
				end
			end
			if description==""
				for div in eachmatch(sel"div.column-span-2 div.entry-content ul li", producerSection)
					description *= strip(Gumbo.text(div))*"; "
				end
			end
		end
		for details in eachmatch(sel"div.item-details div.address-container div.content", producerSection)
			for div in eachmatch(sel"div.row-postal-address div.address-data", details)
				address = Gumbo.text(div)
				ok += 1
			end
			for div in eachmatch(sel"div.row-gps div.address-data p meta", details)
				itemprop = Gumbo.getattr(div, "itemprop")
				if itemprop=="latitude"
					lat = parse(Float64, Gumbo.getattr(div, "content"))
					ok += 1
				elseif itemprop=="longitude"
					lon = parse(Float64, Gumbo.getattr(div, "content"))
				end
			end
			for div in eachmatch(sel"div.row-web div.address-data", details)
				website = Gumbo.text(div)
				ok += 1
			end
			for div in eachmatch(sel"div.row-email div.address-data", details)
				email = Gumbo.text(div)
				ok += 1
			end
			for div in eachmatch(sel"div.row-telephone div.address-data p span a", details)
				if phoneNumber==""
					phoneNumber = getPhoneNumber(Gumbo.text(div))
					ok += 1
				else
					phoneNumber2 = getPhoneNumber(Gumbo.text(div))
				end
			end
		end
	end
    if ok > 2
        producer = OpenProductProducer(
            lat, lon, score, name, firstname,lastname, city, postCode,
            address, phoneNumber, phoneNumber2, "", email, website,
            "", description, openingHours, "A", # Only food product from that website
			"", ""
		)
        # println("producer : ", producer)
		id = insertOnDuplicateUpdate(producer, force=true)
		if id>0
			print("Tags: ")
			for tag in tags
				print(tag,"; ")
				setTagOnProducer(id, tag)
			end
			println()
		else
			println("Warning : not insert/update")
		end
		id
    else
        println("ERROR : parse_producer(",url,") OK=",ok)
        0
    end
end


function parse_amap44(pageNum::Int; nbPages::Int=0, type::AbstractString="producteur")
    nbProducers = 0
    # try
        println("parse_amap44(",pageNum,", ",nbPages,", ",type,")")
        pageNumStr = string(pageNum)
        tmpfile = "./parse_amap44_"*pageNumStr*".html"
		url = "https://www.amap44.org/cat/amap/page/"*pageNumStr*"/"
        url = "https://www.amap44.org/page/"*pageNumStr*"/?ait-items=producteur"
        # download(url,tmpfile); htmlStr = read(tmpfile, String); html = Gumbo.parsehtml(htmlStr)
        response = HTTP.get(url)
        html = response.body |> String |> Gumbo.parsehtml
        for producerDiv in eachmatch(sel"div.item-featured div.content div.item-data div.item-header div.item-title a", html.root)
			# println("Producer:",producerDiv)
			producerUrl = Gumbo.getattr(producerDiv, "href")
			v = parse_producer(producerUrl)
			if v>0
				nbProducers += 1
			end
        end
		if nbPages==0
			for a in eachmatch(sel"nav.pagination-below a.page-numbers", html.root)
				nbPages = parse(Int, Gumbo.text(a))
			end
			println("NbPages:",nbPages)
		end
		while pageNum<=nbPages
			pageNum+=1
			parse_amap44(pageNum, nbPages=1, type=type)
		end
    # catch err
    #     println("ERROR : fail parse_amap44() : ",err)
    # end
	nbProducers
end

nb = parse_amap44(1)
println("Parsed ",nb," producers.")



DBInterface.close!(dbConnection)

exit()
