#Most code from: https://zenn.dev/shikumiya_hata/articles/b18e362e2eae09
import sys
#import io
from janome.analyzer import Analyzer
from janome.charfilter import UnicodeNormalizeCharFilter, RegexReplaceCharFilter
from janome.tokenizer import Tokenizer as JanomeTokenizer  # sumyのTokenizerと名前が被るため
from janome.tokenfilter import POSKeepFilter, ExtractAttributeFilter
import re
import neologdn

from sumy.parsers.plaintext import PlaintextParser
from sumy.nlp.tokenizers import Tokenizer
from sumy.summarizers.lex_rank import LexRankSummarizer

import requests
from bs4 import BeautifulSoup

import emoji
import mojimoji
#sys.stdout = io.open(sys.stdout.fileno(), 'w', encoding='utf8')
input1 = sys.argv[1]
def preprocessing(text):
    text = re.sub(r'\n', '', text)
    text = re.sub(r'\r', '', text)
    text = re.sub(r'\s', '', text)
    text = text.lower()
    text = mojimoji.zen_to_han(text, kana=True)
    text = mojimoji.han_to_zen(text, digit=False, ascii=False)
    text = ''.join(c for c in text if c not in emoji.UNICODE_EMOJI)
    text = neologdn.normalize(text)

    return text

# スクレイピング対象の URL にリクエストを送り HTML を取得する
res = requests.get(input1)

# レスポンスの HTML から BeautifulSoup オブジェクトを作る
soup = BeautifulSoup(res.text, 'html.parser')
for script in soup(["script", "style"]):
	script.decompose()

text2 = soup.get_text()
#print(text2)
print("Summary:\n")
text = re.findall("[^。]+。?", preprocessing(soup.get_text()))
#text=soup.get_text()

# 形態素解析(単語単位に分割する)
analyzer = Analyzer(char_filters=[UnicodeNormalizeCharFilter(), RegexReplaceCharFilter(r'[(\)「」、。]', ' ')], tokenizer=JanomeTokenizer(), token_filters=[POSKeepFilter(['名詞', '形容詞', '副詞', '動詞']), ExtractAttributeFilter('base_form')])

corpus = [' '.join(analyzer.analyze(sentence)) + u'。' for sentence in text]
#print(corpus)
#print(len(corpus))

# 文書要約処理実行
parser = PlaintextParser.from_string(''.join(corpus), Tokenizer('japanese'))

# LexRankで要約を原文書の3割程度抽出
summarizer = LexRankSummarizer()
summarizer.stop_words = [' ']

# 文書の重要なポイントは2割から3割といわれている?ので、それを参考にsentences_countを設定する。
summary = summarizer(document=parser.document, sentences_count=int(len(corpus)/10*3))

print(u'文書要約結果')
print(len(summary))
for sentence in summary:
  print(text[corpus.index(sentence.__str__())])
