#!/usr/local/bin/julia
using ArgParse
import HTTP, JSON, URIs
using Cascadia
DEBUG = false

include("OpenProductProducer.jl")
function updateWebsiteStatus(id, websiteStatus)
	sql2 = "UPDATE producer SET websiteStatus='"*websiteStatus*"' WHERE id="*string(id)
	println("SQL:",sql2,";")
	# DBInterface.execute(dbConnection, sql2)
end
function testWebsites()
	sql = """SELECT id, name, website, websiteStatus
			FROM producer 
			WHERE (website IS NOT NULL AND website!="")
				AND websiteStatus="unknown"
				AND status not in ("hs","hors-sujet")
			ORDER BY ID
		"""
	res = DBInterface.execute(dbConnection, sql)
	for websiteParams in res
		id = websiteParams[:id]
		website = websiteParams[:website]
		websiteStatus = getWebSiteStatus(website)
		if websiteStatus != "unknown"
			println("URL:", website, " => ", websiteStatus)
			updateWebsiteStatus(id, websiteStatus)
		end
	end
end

testWebsites()



DBInterface.close!(dbConnection)
