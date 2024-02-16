#!/bin/env python3

import requests
import mysql.connector
import yaml
import re

DB_CONFIGURATION_FILE = "../../openproduct-web/db/connection.yml"



# Get DB Configuration (user/password)
with open(DB_CONFIGURATION_FILE, 'r') as file:
	dbconfiguration = yaml.safe_load(file)
dbconf = dbconfiguration['dev']
regexHttpSchema = re.compile(r"^https?://.*", flags=0)

# Connect to DB
mydb = mysql.connector.connect(
  host=dbconf['host'],
  user=dbconf['username'],
  password=dbconf['password'],
  database=dbconf['database']
)
mycursor = mydb.cursor()

# Query for all email

def getWebSiteStatus(url):
	print("getWebSiteStatus(",url,")")
	websiteStatus = 'unknown'
	try:
		r = requests.get(url, timeout=30)
		if r.status_code==200:
			websiteStatus = 'ok'
		elif r.status_code==404:
			print(" =>",r.status_code)
		elif r.status_code>=400 and r.status_code<500:
			websiteStatus = '400'
		elif r.status_code==500 or r.status_code==503:
			websiteStatus = 'ko'
		else:
			print(" =>",r.status_code)
	except requests.exceptions.ConnectionError:
		websiteStatus = 'ConnectionError'
	except requests.exceptions.ReadTimeout:
		websiteStatus = 'ko'
	except requests.exceptions.ChunkedEncodingError:
		print(" => requests.exceptions.ChunkedEncodingError")
	except requests.exceptions.TooManyRedirects:
		print(" => requests.exceptions.TooManyRedirects")
	except requests.exceptions.MissingSchema:
		if not regexHttpSchema.match(url):
			newUrl = "https://"+url
			ok = getWebSiteStatus(newUrl)
			if ok:
				sql2 = """UPDATE producer 
					SET website="%s"
					WHERE website="%s"
					"""
				mycursor.executemany(sql2, [(newUrl, url)])
			return ok
		print(" => requests.exceptions.MissingSchema")
	# print("getWebSiteStatus(",url,") => ", websiteStatus)
	return websiteStatus

def testWebsites():
	mycursor.execute(
		"""SELECT id, name, website, websiteStatus
			FROM producer 
			WHERE (website IS NOT NULL AND website!='')
				AND websiteStatus='ko' 
				AND status not in ('hs','hors-sujet')
			ORDER BY ID
			LIMIT 1000
		"""
	)
	producers = mycursor.fetchall()
	for producer in producers:
		id = producer[0]
		website = producer[2]
		websiteStatus = getWebSiteStatus(website)
		if websiteStatus != 'unknown':
			print(" - ",website," => ",websiteStatus)
			sql2 = """UPDATE producer 
				SET websiteStatus=%s
				WHERE id=%s
				"""
			# print("SQL:",sql2%(websiteStatus, id))
			mycursor.executemany(sql2, [(websiteStatus, id)])


testWebsites()
