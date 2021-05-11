#(C)Inspire Search Corporation 2021
import ddg3
import sys
import urllib
q = sys.argv[1]
q = q.rstrip()
urllib.parse.quote(q)
#Change here for query
r = ddg3.query(q)
#print(q)
if r.type == 'answer':
        r.abstract.url
if r.type == 'disambiguation':
        for i in r.related:
                print(i.url)
else:
	print("try again")
