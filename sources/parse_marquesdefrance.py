#!/bin/env python3
# source ../communication/venv/bin/activate.fish
# ./parse_marquesdefrance.py > ./parse_marquesdefrance.lst
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.chrome.options import Options
import time
import random

# Configure Chrome options
chrome_options = Options()
chrome_options.add_argument("--headless")  # Remove if you want to see browser
chrome_options.add_argument("--no-sandbox")
chrome_options.add_argument("--disable-dev-shm-usage")
# Initialize driver


# from requests_html import HTMLSession
# session = HTMLSession()
# r = session.get('https://www.marques-de-france.fr/atelier/?page=5')
# r.html.render(sleep=2)  # Render JavaScript
# print(r.html.html)

def parse_marquesdefrance(page_num:int):
	# scraping web selenium
	# https://www.pythoniaformation.com/blog/tutoriels-python-par-categories/automatiser-avec-python/comment-faire-web-scraping-selenium-python
	# https://datascientest.com/selenium-python-web-scraping
	# print("parse_marquesdefrance(",page_num,")")
	driver = webdriver.Chrome(options=chrome_options)
	url = f"https://www.marques-de-france.fr/atelier/?page={page_num}"
	driver.get(url)
	# time.sleep(3)
	# Wait for content to load
	try:
		time.sleep(3)
		driver.execute_script("window.scrollTo(0, document.body.scrollHeight);")
		WebDriverWait(driver, 5).until(
			EC.presence_of_element_located((By.CLASS_NAME, "ais-InfiniteHits-item"))  # Adjust selector
		)
	except:
		print()
		# Extract data
	csspath = "li.ais-InfiniteHits-item a" # .col.d-block
	elems = driver.find_elements(By.CSS_SELECTOR, csspath)
	for elem in elems:
		print(elem.get_attribute('href'))
	driver.quit()

for p in range(1,22):
	parse_marquesdefrance(p)
	# time.sleep(random.uniform(2, 5))

