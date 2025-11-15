#!/bin/env julia
#!/snap/bin/julia

# ADD Header :
# Date: Sat, 1 Jan 2000 12:00:59 +0200

import SMTPClient, Random, DBInterface, OteraEngine, TOML
using Dates

ENV="dev"
conffile = "../.env.production"
if isfile(conffile)
	println("Production environment")
	ENV="prod"
else
	println("Development environment")
end


CURDIR=pwd()
include_path = ".."
if ENV=="dev"
	include_path = "../../openproduct-web-svelte4"
end
include(include_path*"/scripts/connect.jl")
dbConnection = get_connection(include_path)

if ENV=="dev"
	conffile = include_path*"/.env.local"
else
	conffile = include_path*"/.env.production"
end
println("Use configuration file : ", conffile)
conf = TOML.parsefile(conffile)
SMTP_HOST = conf["SMTP_HOST"]
SMTP_PORT = conf["SMTP_PORT"]
SMTP_PASS = conf["SMTP_PASS"]
SMTP_USER = conf["SMTP_USER"]

regexMailStart = Regex("^From - ")
regexHeaderLine = Regex("^([a-zA-Z0-9-]+): (.*)")
regexHeaderProtocol = Regex("^([a-z0-9]+); (.*)")


function headerRmProtocol(value::String)::String
	m = match(regexHeaderProtocol, value)
	if m!==nothing
		value = m[2]
	end
	value
end
function processMail(mail::Dict{String, String})::Bool
	email = headerRmProtocol(mail["Final-Recipient"])
	pb = headerRmProtocol(mail["Diagnostic-Code"])
	# println("processMail(",email, ", ", pb,")")
	ok = false
	status = 0
	redo = 1 # relaunch after fx pb
	tocheck = 2 # Check f producer exists
	tomanual = 3 # Send manually : spam
	fromlocal = 4 # Send automatically from local server
	if startswith(pb, "554-Transaction") ||
			startswith(pb, "550 Subject contains invalid characters")
		# println("--> 554 : Date format ", pb)
		status = redo
	elseif startswith(pb, "451 ")
		# println("--> 451 : Try again later ", pb)
		status = redo
	elseif startswith(pb, "550 5.1.1 ") || startswith(pb, "550-5.1.1 ") || 
			startswith(pb, "550 5.2.1 ") || 
			startswith(pb, "550 5.5.0 ") || 
			startswith(pb, "550 sorry, user over quota")
		# println("-> 550 Wrong address mail ", pb)
		# - 5.1.1 Adresse d au moins un destinataire invalide.
		# - sorry, user over quota (#5.1.1)
		# - 5.2.1 This mailbox has been blocked due to inactivity
		# - 5.5.0 Requested action not taken: mailbox unavailable
		status = tocheck
	elseif startswith(pb, "550 5.7.0 ") ||
			startswith(pb, "554 5.7.1 ")
		# - 5.7.0 Server IP 109.234.163.45 listed as abusive.
		# - 5.7.1 : Relay access denied # All C-class IP's blocked
		status = fromlocal
	elseif startswith(pb, "550 spam detected") ||
			startswith(pb, "550 5.4.1 ") ||
			startswith(pb, "550 5.7.9 ") # TODO
		# - spam detected
		# - 5.4.1 Recipient address rejected: Access denied. For more information see https://aka.ms/EXOSmtpErrors
		# - 5.7.9 This mail has been blocked because the sender is unauthenticated.
		# println("-> 550 Spam detected ", pb)
		status = tomanual
	elseif startswith(pb, "X-Postfix; ")
		# Host or domain name not found. Name service error
		# println("-> X-Postfix: ", pb)
		status = tocheck
	else
		# Host or domain name not found. Name service error
		println("-> Unknown: ", pb)
	end
	if status==redo
		sql = "update producers p "*
			"set has_send_mail=false "*
			"where email='"*email*"'; -- "*pb
		println("SQL: ",sql)
		ok = true
	elseif status==tocheck
		println("TOCHECK: ",email, " -- ",pb)
		ok = true
	elseif status==tomanual
		println("TOMANUAL: ",email, " -- ",pb)
		ok = true
	elseif status==fromlocal
		println("FROMLOCAL: ",email)
		ok = true
	else
		println("TODO : processMail(",email, ", ", pb,") : Not known problem.")
	end
	ok
end




function parseMails(filepath)
	filepath = filepath*"/INBOX.sbd/TODO"
	nbMail = 0
	mail = Dict{String, String}()
	numLine = 0
	for line in eachline(filepath)
		numLine += 1
		m = match(regexHeaderLine, line)
		if m!==nothing
			# println("Line: ", line)
			mail[m[1]] = m[2]
		elseif match(regexMailStart, line)!==nothing
			nbMail+=1
			numLine = 0
			if nbMail>1
				processMail(mail)
			end
		end
	end
	println("Compute ",nbMail," mails.")
end

filepath = "/home/alberic/snap/thunderbird/common/.thunderbird/5xspk6t6.default/ImapMail/mail.openproduct.fr"
parseMails(filepath)
