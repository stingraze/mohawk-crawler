from urllib.request import urlopen
import urllib.parse
import sys
# import json
import json
#query is the sys.argv[1]
query = sys.argv[1]

query = urllib.parse.quote(query)

# store the URL in url as 
# parameter for urlopen
url = "http://api.duckduckgo.com/?q=" + query + "&format=json&pretty=1"
  
# store the response of URL
response = urlopen(url)
  
# storing the JSON response 
# from url in data
data_json = json.loads(response.read())
  
# print the json response
print(data_json)
