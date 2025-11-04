#!/bin/env julia
#!/snap/bin/julia

# ADD Header :
# Date: Sat, 1 Jan 2000 12:00:59 +0200

import SMTPClient, Random, DBInterface, OteraEngine, TOML
using Dates

EMAIL_BODY_1ST_COMM_TEMPLATE_FILE = "template1stCommunication.html"
EMAIL_BODY_TEMPLATE_FILE = "templateMail.html"



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

# using OpenProduct

function sendMail(to, subject, message, token)::Bool
	from = SMTP_USER
	fromC = "OpenProduct <"*from*">"
	nowdt = Dates.now()
	date = Dates.format(nowdt, RFC1123Format)*" +0100"
	premsg = "Date: "*date*"\r\n"*
		"List-Unsubscribe: <https://www.openproduct.fr/new/unsubscribe?mail="*to*"&token="*token*">\r\n"
	mime_msg = premsg*SMTPClient.get_mime_msg(HTML(replace(message, "\n"=>"\r\n")))
	println("MimeMsg:\n\n", premsg);
	rcpt = [to]
	body = SMTPClient.get_body(rcpt, fromC, subject, mime_msg)
	# println("Body:",String(take!(body)))
	url = "smtps://"*SMTP_HOST*":"*string(SMTP_PORT)
	opt = SMTPClient.SendOptions(isSSL=true, username=SMTP_USER, passwd=SMTP_PASS)
	resp = SMTPClient.send(url, rcpt, from, body, opt)
	if resp.code==250
		true
	else
		println("ERROR : fail send mail to ",to," : ",resp)
		false
	end
end

function generateToken()::String
	Random.seed!(0)
	Random.randstring(64)
end

function sendMail2AllProducers(subject, templateFilepath4Body)
	sql2 = """UPDATE producers
		SET has_send_mail=true
		WHERE email=\$1
		"""
	sqlUpdateSendEmail = DBInterface.prepare(dbConnection, sql2)
	sqlUpdateToken = nothing

	templateMailBody = OteraEngine.Template(templateFilepath4Body)

	sql = """SELECT p.company_name, coalesce(lastname, firstname , '') lastname, email, token
		FROM producers p 
		WHERE email is not null and email!=''
			AND send_email='ok'
			AND status in('actif', 'hs', 'to-check', 'unknown')
			AND has_send_mail=false
		ORDER BY ID
		LIMIT 10"""
	println("SQL:", sql);
	producers = DBInterface.execute(dbConnection, sql)
	myProducers = []
	for producer in producers
		push!(myProducers, (producer[1], producer[2], producer[3], producer[4]))
	end
	for producer in myProducers
		name = producer[1]
		lastname = producer[2]
		email = producer[3]
		token = producer[4]
		if ismissing(token) || token==""
			println("Generate token for ",email)
			token = generateToken()
			if isnothing(sqlUpdateToken)
				sql2 = """UPDATE producers 
					SET token=\$1
					WHERE email=\$2
					"""
				sqlUpdateToken = DBInterface.prepare(dbConnection, sql2)
			end
			DBInterface.execute(sqlUpdateToken, [token, email])
		end
		dictionary=Dict(
			Symbol("email")=> email,
			Symbol("lastname")=> lastname,
			Symbol("name")=> name,
			Symbol("token")=> token
		)
		message = templateMailBody(init=dictionary)
		slp = rand(1:240)
		println("Sleep ",slp," s.")
		sleep(slp) # Sleep between up to 4 minutes.
		# println("Send mail to ",email,".")
		ok = sendMail(email, subject, message, token)
		if ok
			DBInterface.execute(sqlUpdateSendEmail, [email])
			println("Sent message to ",email," (",name,", ",lastname,")")
		else
			println("Fail sent email")
		end
	end
end

function sendMailToNewProducers()
	sql2 = "UPDATE producers SET send_email='Ok' WHERE email=\$1"
	sqlUpdateSendEmail = DBInterface.prepare(dbConnection, sql2)
	sqlUpdateToken = nothing

	template1stCommunication = OteraEngine.Template(EMAIL_BODY_1ST_COMM_TEMPLATE_FILE)
	subject = ""

	sql = """SELECT name, coalesce(lastname,firstname,"") lastname, email, token
		FROM producers
		WHERE email is not null and email!=''
			AND send_email='unknown'
		ORDER BY ID
		"""
	println("SQL:", sql)
	producers = DBInterface.execute(dbConnection, sql)
	for producer in producers
		name = producer[1]
		lastname = producer[2]
		email = producer[3]
		token = producer[4]
		if ismissing(token) || token==""
			println("Generate token for ",email)
			token = generateToken()
			if isnothing(sqlUpdateToken)
				sql2 = """UPDATE producers
					SET token=\$1
					WHERE email=\$2
					"""
				sqlUpdateToken = DBInterface.prepare(dbConnection, sql2)
			end
			DBInterface.execute(sqlUpdateToken, [token, email])
		end
		dictionary=Dict(
			Symbol("email")=> email,
			Symbol("lastname")=> lastname,
			Symbol("name")=> name,
			Symbol("token")=> token
		)
		message = template1stCommunication(init=dictionary)
		ok = sendMail(email, subject, message, token)
		if ok
			DBInterface.execute(sqlUpdateSendEmail, [email])
			println("sent message to ",email," (",name,", ",lastname,")")
		end
	end
end

# sendMailToNewProducers()
# sendMailForAG()
sendMail2AllProducers(
	"OpenProduct évolue. Gérez désormais votre profil en direct",
	EMAIL_BODY_TEMPLATE_FILE
)
# sendMail("alberic.delacrochais@protonmail.com", "Test", "Un petit message de test")

