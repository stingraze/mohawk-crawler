#(C) Tsubasa Kato Inspire Search Corporation 2021/8/17
import csv
import sys
import os
import pandas as pd
import codecs

tsv_file_name = str(sys.argv[1])
csv_file_name = str(sys.argv[1]) + "_output.csv"


#shell_command = "LC_ALL=C" + " tr < " + str(sys.argv[1]) + ".dat -d " + "\'\000\'" + " > " + str(sys.argv[1]) + ".dat"
#os.system(shell_command)
fi = open(tsv_file_name, 'rb')
data = fi.read()
fi.close()

fo = open(tsv_file_name, 'wb')
fo.write(data.replace(b'\x00', b''))
fo.close()

#with open(tsv_file_name, "rt", encoding="utf8", errors='ignore') as f:
#	reader = csv.reader(f)

#with open(csv_file_name,'wt', encoding="utf8", errors='ignore') as fou:
#	cw = csv.writer(fou, quotechar='', quoting=csv.QUOTE_NONE, escapechar='\\')
#	cw.writerows(reader)

#tsv_file='name.tsv'


with codecs.open(tsv_file_name, mode ="r", encoding= "UTF-8",errors="ignore") as file:
    data = pd.read_csv(file, sep='\t')

data.to_csv(csv_file_name,index=False)



print("converted.")