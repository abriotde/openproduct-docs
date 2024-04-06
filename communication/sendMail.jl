#!/bin/env julia

import SMTPClient, Random, DBInterface, OteraEngine

EMAIL_BODY_TEMPLATE_FILE = "template1stCommunication.html"
SUBJECT = "Promotion des producteurs locaux"


include("../lib/OpenProduct.jl/src/OpenProduct.jl")
# using OpenProduct
dbConnection = OpenProduct.dbConnect("../../openproduct-web/db/connection.yml")
OpenProduct.op_start(dbConnection)

function sendMail(to, subject, message)::Bool
	from = "contact@openproduct.fr"
	fromC = "OpenProduct <"*from*">"
	mime_msg = SMTPClient.get_mime_msg(HTML(replace(message, "\n"=>"\r\n")))
	rcpt = [to]
	body = SMTPClient.get_body(rcpt, fromC, subject, mime_msg)
	url = "smtps://mail.openproduct.fr:465"
	opt = SMTPClient.SendOptions(isSSL=true, username=from, passwd="wkWfQrToToGmr2B")
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

function sendMailToNewProducers()
	sql2 = "UPDATE producer SET sendEmail='Yes' WHERE email=?"
	sqlUpdateSendEmail = DBInterface.prepare(dbConnection, sql2)
	sqlUpdateToken = nothing

	template1stCommunication = OteraEngine.Template(EMAIL_BODY_TEMPLATE_FILE)

	sql = """SELECT name, coalesce(lastname,firstname,"") lastname, email, tokenAccess
		FROM producer 
		WHERE email is not null and email!=''
			AND (sendEmail is null) AND tokenAccess is NULL
		ORDER BY ID
		"""
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
				sql2 = """UPDATE producer 
					SET tokenAccess=?
					WHERE email=?
					"""
				sqlUpdateToken = DBInterface.prepare(dbConnection, sql2)
			end
			DBInterface.execute(sqlUpdateToken, [token, email])
		end
		dictionary=Dict(
			"email"=> email,
			"lastname"=> lastname,
			"name"=> name,
			"token"=> token
		)
		message = template1stCommunication(init=dictionary)
		DBInterface.execute(sqlUpdateSendEmail, [email])
		ok = sendMail(email, SUBJECT, message)
		if ok
			println("sent message to ",email," (",name,", ",lastname,")")
		end
	end
end

sendMailToNewProducers()

OpenProduct.op_stop(OpenProduct.ok ,dbConnection)
