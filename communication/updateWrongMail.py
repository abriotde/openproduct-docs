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
  password=dbconf['password'],
  database=dbconf['database']
)
mycursor = mydb.cursor()

SCOPES = [
#   "https://www.googleapis.com/auth/gmail.send"
	"https://www.googleapis.com/auth/gmail.readonly"
]
flow = InstalledAppFlow.from_client_secrets_file(GMAIL_API_KEY_FILE, SCOPES)
creds = flow.run_local_server(port=0)
service = build('gmail', 'v1', credentials=creds)

def disableEmail(email):
	mycursor.execute(
		"""UPDATE producer
			SET sendEmail='wrongEmail', status=if(status='actif','to-check',status)
			WHERE email='%s'
			LIMIT 2
		""" % email
	)

msgs = service.users().messages().list(userId='me',q='in:inbox is:unread', maxResults=70).execute()
print(msgs)
for msg in msgs['messages']:
	resp = service.users().messages().get(userId='me', id=msg['id']).execute()
	print("- Id:",resp['id'])
	parts = resp['payload']['parts']
	for part in parts:
		# print(" - PartId:", part['partId'])
		if 'parts' in part:
			# print(" - hasSubParts")
			subparts = part['parts']
			for subpart in subparts:
				# print(" - subpart/PartId:", subpart['partId'])
				headers = subpart['headers']
				for header in headers:
					# print("   header[",header['name'],"]")
					if header['name']=='To':
						print("  => to ",header['value'])
						disableEmail(header['value'])
		


