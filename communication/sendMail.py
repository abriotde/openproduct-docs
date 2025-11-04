#!/bin/env python3

from email.mime.text import MIMEText
import random
import os.path
import tomli
import psycopg
import smtplib, ssl
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
import time

EMAIL_BODY_1ST_COMM_TEMPLATE_FILE = "template1stCommunication.html"
EMAIL_BODY_TEMPLATE_FILE = "templateMail.html"
EMAIL_SUBJECT = "OpenProduct évolue. Gérez désormais votre profil en direct"



ENV="dev"
conffile = "../.env.production"
if os.path.isfile(conffile):
	print("Production environment")
	ENV="prod"
else:
	conffile = "../../openproduct-web-svelte4/.env.local"
	print("Development environment")

DB_CONNECTION = None
def get_connection(root_path=".."):
	global DB_CONNECTION
	if DB_CONNECTION is None:
		# println("get_connection()", pwd())
		conffile = root_path+"/.env.production"
		if ENV=="dev":
			conffile = "../../openproduct-web-svelte4/.env.local"
		print("Use configuration file : ", conffile)
		with open(conffile, "rb") as f:
			conf = tomli.load(f)
			DATABASE_NAME = conf["DATABASE_NAME"]
			DATABASE_USER = conf["DATABASE_USER"]
			DATABASE_PASSWORD = conf["DATABASE_PASSWORD"]
			connection = psycopg.connect(dbname=DATABASE_NAME,
				user=DATABASE_USER, password=DATABASE_PASSWORD,
				host="localhost", port=5432)
			DB_CONNECTION = connection.cursor()
			print("Connected")
	return DB_CONNECTION
db_cnx = get_connection()

SMTP_USER = None
SMTP_HOST = None
SMTP_PORT = None
SMTP_PASS = None
with open(conffile, "rb") as f:
	conf = tomli.load(f)
	SMTP_USER = conf["SMTP_USER"]
	SMTP_HOST = conf["SMTP_HOST"]
	SMTP_PORT = conf["SMTP_PORT"]
	SMTP_PASS = conf["SMTP_PASS"]
	
def sendMail(to, subject, body, token):
	global SMTP_USER
	fromC = "OpenProduct <"+SMTP_USER+">"
	premsg = "List-Unsubscribe: <https://www.openproduct.fr/new/unsubscribe?mail="+to+"&token="+token+">\r\n"
	context = ssl.create_default_context()
	message = MIMEMultipart("alternative")
	message["Subject"] = subject
	message["From"] = fromC
	message["To"] = to
	message.attach(MIMEText(body, "html"))
	message.add_header('List-Unsubscribe', '<https://www.openproduct.fr/new/unsubscribe?mail='+to+'token='+token+'>')
	context = ssl.create_default_context()
	with smtplib.SMTP_SSL(SMTP_HOST, SMTP_PORT, context=context) as server:
		server.login(SMTP_USER, SMTP_PASS)
		ok = server.sendmail(SMTP_USER, to, message.as_string())
		return True
	return False

# Query for all email
db_cnx.execute(
	"""SELECT p.company_name, coalesce(lastname, firstname , '') lastname, email, token
		FROM producers p 
		WHERE email is not null and email!=''
			AND send_email='ok'
			AND status in('actif', 'to-check', 'unknown')
			AND has_send_mail=false
		ORDER BY ID
		LIMIT 10
	"""
)
producers = db_cnx.fetchall()
print(producers)

# sendMail("alberic.delacrochais@protonmail.com", EMAIL_SUBJECT, "Un test", "ugiofnkjulblfu")
# producers = [('OpenHomeSystem', 'Albéric', 'alberic.delacrochais@protonmail.com', '5b76db3e3f1d426ede4fce655844366b')]

from jinja2 import Template
with open(EMAIL_BODY_TEMPLATE_FILE, 'r') as f:
	template = Template(f.read())

	for producer in producers:
		email = producer[2]
		token = producer[3]
		context = {
			'email': email,
			'lastname': producer[1],
			'name': producer[0],
			'token': token
		}
		body = template.render(context)
		slp =  random.randrange(1, 240)
		print("Sleep ",slp," s.")
		time.sleep(slp)
		if sendMail(email, EMAIL_SUBJECT, body, token):
			sql = "UPDATE producers SET has_send_mail=True WHERE email='"+email+"'"
			db_cnx.execute(sql)
			print("Sent message to ",email," successfully.")
		else:
			print("Fail send mail to ",email)

