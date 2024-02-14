#!/bin/env python3

import base64
from email.mime.text import MIMEText
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from requests import HTTPError
import mysql.connector
import yaml
import random
import string

DB_CONFIGURATION_FILE = "../../openproduct-web/db/connection.yml"
# SENDER = "openproduct.fr@gmail.com"
GMAIL_API_KEY_FILE = "../private/OpenProductMailSender_OAuth2_key.json"
SUBJECT = "Promotion des producteurs locaux"
EMAIL_BODY_TEMPLATE_FILE = "template1stCommunication.html"


# Get DB Configuration (user/password)
with open(DB_CONFIGURATION_FILE, 'r') as file:
	dbconfiguration = yaml.safe_load(file)
dbconf = dbconfiguration['dev']

# Connect to DB
mydb = mysql.connector.connect(
  host=dbconf['host'],
  user=dbconf['username'],
  password=dbconf['password']
)
mycursor = mydb.cursor()

# Query for all email
mycursor.execute(
	"""SELECT name, coalesce(lastname,firstname), email, tokenAccess
		FROM openproduct.producer 
		WHERE email is not null and email!=''
			AND (sendEmail is null or sendEmail!="Never")
			AND (id in (1187))
		ORDER BY ID
	"""
)
producers = mycursor.fetchall()
print(producers)


SCOPES = [
    "https://www.googleapis.com/auth/gmail.send"
]
flow = InstalledAppFlow.from_client_secrets_file(GMAIL_API_KEY_FILE, SCOPES)
creds = flow.run_local_server(port=0)
service = build('gmail', 'v1', credentials=creds)


from jinja2 import Template
with open(EMAIL_BODY_TEMPLATE_FILE, 'r') as f:
	template = Template(f.read())

	for producer in producers:
		email = producer[2]
		token = producer[3]
		# print("-> "+email)
		if token is None or token=="":
			print("Generate token for "+email)
			token = ''.join(random.choice(string.ascii_letters+string.digits) for i in range(64))
			sql2 = """UPDATE openproduct.producer 
				SET tokenAccess="%s"
				WHERE email="%s"
				""" % (token, email)
			mycursor.execute(sql2)
		context = {
			'email': email,
			'lastname': producer[1],
			'name': producer[0],
			'token': token
		}
		body = template.render(context)

		message = MIMEText(body, 'html')
		message['to'] = email
		message['subject'] = SUBJECT
		message.add_header('List-Unsubscribe', '<https://www.openproduct.fr/unsubcribe.php?mail='+email+'token='+token+'>')
		create_message = {'raw': base64.urlsafe_b64encode(message.as_bytes()).decode()}

		try:
			message = (service
				.users().messages()
				.send(userId="me", body=create_message)
				.execute()
			)
			print(F'sent message to {email} Message Id: {message["id"]}')
		except HTTPError as error:
			print(F'An error occurred: {error}')
			message = None

