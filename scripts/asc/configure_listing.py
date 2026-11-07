#!/usr/bin/env python3
"""Configure the Flipabulary App Store listing for all app languages.

Idempotent: existing localizations are patched, missing ones are created.
"""

import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

BASE = "https://api.appstoreconnect.apple.com"
APP_ID = "6831894963"
APP_INFO_ID = "64555a63-89db-4b46-870c-90a59c630d2c"
AGE_RATING_ID = "64555a63-89db-4b46-870c-90a59c630d2c"
VERSION_ID = "a2cabc05-51d4-4f35-b9dd-5f298da38b63"
FREE_PRICE_POINT_ID = "eyJzIjoiNjgzMTg5NDk2MyIsInQiOiJVU0EiLCJwIjoiMTAwMDAifQ"

SUPPORT_URL = "https://mrmaier.com/flipabulary/support"
PRIVACY_URL = "https://mrmaier.com/flipabulary/privacy"
MARKETING_URL = "https://mrmaier.com/flipabulary"

TOKEN = subprocess.check_output(
    ["ruby", os.path.expanduser("~/.config/opencode/scripts/asc-jwt.rb")],
    text=True,
).strip()


def request(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        BASE + path,
        data=data,
        method=method,
        headers={
            "Authorization": "Bearer " + TOKEN,
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            payload = response.read().decode()
            return response.status, json.loads(payload) if payload else {}
    except urllib.error.HTTPError as error:
        payload = error.read().decode()
        return error.code, json.loads(payload) if payload else {}


LOCALES = [
    "en-US", "de-DE", "es-ES", "pt-BR", "fr-FR", "ru", "pl", "uk",
    "zh-Hans", "ko", "ja", "vi", "it", "nl-NL", "tr", "id",
]

APP_NAMES = {locale: "Flipabulary" for locale in LOCALES}
APP_NAMES["vi"] = "Flipabulary Từ vựng"

SUBTITLES = {
    "en-US": "Build a vocabulary that sticks",
    "de-DE": "Wortschatz, der bleibt",
    "es-ES": "Vocabulario que se queda",
    "pt-BR": "Vocabulário que fica",
    "fr-FR": "Un vocabulaire qui reste",
    "ru": "Слова, которые остаются",
    "pl": "Słownictwo, które zostaje",
    "uk": "Слова, що залишаються",
    "zh-Hans": "让单词真正留下来",
    "ko": "기억에 남는 단어장",
    "ja": "記憶に残る単語帳",
    "vi": "Từ vựng nhớ lâu",
    "it": "Parole che restano",
    "nl-NL": "Woorden die blijven",
    "tr": "Kalıcı kelime dağarcığı",
    "id": "Kosakata yang melekat",
}

PROMOTIONAL = {
    "en-US": "Remember more words with short, self-paced reviews. Everything stays offline, on your device, and on your Home Screen.",
    "de-DE": "Merke dir mehr Wörter mit kurzen, selbstbestimmten Wiederholungen. Alles bleibt offline, auf deinem Gerät und auf dem Home-Bildschirm.",
    "es-ES": "Recuerda más palabras con repasos cortos a tu ritmo. Todo se queda sin conexión, en tu dispositivo y en tu pantalla de inicio.",
    "pt-BR": "Lembre-se de mais palavras com revisões curtas no seu ritmo. Tudo fica offline, no seu dispositivo e na tela de início.",
    "fr-FR": "Retenez plus de mots grâce à de courtes révisions à votre rythme. Tout reste hors ligne, sur votre appareil et sur l'écran d'accueil.",
    "ru": "Запоминайте больше слов с короткими повторениями в удобном темпе. Всё работает офлайн, на устройстве и на экране «Домой».",
    "pl": "Zapamiętuj więcej słów dzięki krótkim powtórkom we własnym tempie. Wszystko działa offline, na urządzeniu i na ekranie początkowym.",
    "uk": "Запам'ятовуйте більше слів завдяки коротким повторенням у зручному темпі. Усе працює офлайн, на пристрої та на екрані «Домівка».",
    "zh-Hans": "用简短的自定进度复习记住更多单词。一切都在本机离线运行，也能显示在主屏幕上。",
    "ko": "짧은 자기 주도 복습으로 더 많은 단어를 기억하세요. 모든 것이 오프라인으로 기기에 저장되고 홈 화면에서도 보입니다.",
    "ja": "短い自己ペースの復習で、もっと多くの単語を覚えましょう。すべてオフラインで端末内に保存され、ホーム画面にも表示されます。",
    "vi": "Ghi nhớ nhiều từ hơn với các buổi ôn ngắn theo nhịp của bạn. Mọi thứ hoạt động ngoại tuyến, trên thiết bị và Màn hình chính.",
    "it": "Ricorda più parole con brevi ripassi al tuo ritmo. Tutto resta offline, sul dispositivo e nella schermata Home.",
    "nl-NL": "Onthoud meer woorden met korte herhalingen in je eigen tempo. Alles blijft offline, op je apparaat en op je beginscherm.",
    "tr": "Kısa ve kendi hızında tekrarlarla daha fazla kelime hatırla. Her şey çevrimdışı, cihazında ve Ana Ekran'da kalır.",
    "id": "Ingat lebih banyak kata dengan ulasan singkat sesuai ritme Anda. Semuanya tetap offline, di perangkat, dan di Layar Utama.",
}

KEYWORDS = {
    "en-US": "vocabulary,flashcards,words,language,study,learn,spaced repetition,offline,translations",
    "de-DE": "wortschatz,karteikarten,wörter,sprache,lernen,wiederholen,offline,übersetzung",
    "es-ES": "vocabulario,tarjetas,palabras,idioma,estudiar,aprender,repeticion,offline,traducciones",
    "pt-BR": "vocabulário,flashcards,palavras,idioma,estudar,aprender,repetição,offline,traduções",
    "fr-FR": "vocabulaire,cartes,mots,langue,étudier,apprendre,répétition,hors ligne,traductions",
    "ru": "словарь,карточки,слова,язык,учить,запоминать,повторение,офлайн,перевод",
    "pl": "słownictwo,fiszki,słowa,język,nauka,powtórki,offline,tłumaczenia",
    "uk": "словник,картки,слова,мова,вчити,запам'ятовувати,повторення,офлайн,переклад",
    "zh-Hans": "词汇,单词卡,单词,语言,学习,记忆,复习,离线,翻译",
    "ko": "단어장,플래시카드,단어,언어,공부,암기,복습,오프라인,번역",
    "ja": "単語帳,フラッシュカード,単語,言語,学習,暗記,復習,オフライン,翻訳",
    "vi": "từ vựng,thẻ ghi nhớ,từ ngữ,ngôn ngữ,học,ghi nhớ,ôn tập,ngoại tuyến,dịch",
    "it": "vocabolario,flashcard,parole,lingua,studiare,imparare,ripasso,offline,traduzioni",
    "nl-NL": "woordenschat,flashcards,woorden,taal,leren,studeren,herhalen,offline,vertalingen",
    "tr": "kelime,kelime kartı,dil,öğrenmek,ezberlemek,tekrar,çevrimdışı,çeviri",
    "id": "kosakata,kartu kata,bahasa,belajar,menghafal,ulangan,offline,terjemahan",
}

WHATS_NEW = {
    "en-US": "First release.",
    "de-DE": "Erste Version.",
    "es-ES": "Primera versión.",
    "pt-BR": "Primeira versão.",
    "fr-FR": "Première version.",
    "ru": "Первый выпуск.",
    "pl": "Pierwsza wersja.",
    "uk": "Перший випуск.",
    "zh-Hans": "首个版本。",
    "ko": "첫 출시.",
    "ja": "初回リリース。",
    "vi": "Bản phát hành đầu tiên.",
    "it": "Prima versione.",
    "nl-NL": "Eerste versie.",
    "tr": "İlk sürüm.",
    "id": "Rilis pertama.",
}

DESCRIPTIONS = {
    "en-US": """Flipabulary is a quiet, offline vocabulary notebook for the words you actually want to remember.

Save a word and its translation, add an example, and organize everything into stacks and tags. When it is time to practice, Flipabulary gives you short sessions built around one simple choice: Again or Good. No account, no ads, no subscription, and no connection required.

WHAT YOU CAN DO
• Save words with translations, examples, phonetics, and parts of speech
• Organize vocabulary into stacks and tags
• Search and filter by New, Learning, Learned, or Difficult
• Review with short, self-paced sessions
• Adjust learning steps, the repeat threshold, and forgetting rules
• See your vocabulary and review workload in Home Screen widgets
• Get optional local reminders when words are ready
• Use light, dark, or system appearance
• Switch the interface between 16 languages
• Study vocabulary in any language or script

PRIVATE BY DESIGN
Your library stays on your device. Flipabulary does not require an account and does not send your words to a server.

FREE TO USE
Learning, widgets, and reminders work without any purchase. If you want to support development, the Support screen offers six optional one-time tips. Tips unlock no features and can be repeated.

Flipabulary is made by one person who wanted a calmer way to keep vocabulary in view.""",
    "de-DE": """Flipabulary ist ein ruhiges, Offline-Wortschatzheft für die Wörter, die du wirklich behalten möchtest.

Speichere ein Wort und seine Übersetzung, ergänze ein Beispiel und ordne alles in Stapeln und Tags. Wenn es Zeit zum Üben ist, bekommst du kurze Sitzungen mit einer einfachen Entscheidung: Nochmal oder Gut. Kein Konto, keine Werbung, kein Abo und keine Verbindung nötig.

WAS DU MACHST
• Wörter mit Übersetzungen, Beispielen, Lautschrift und Wortarten speichern
• Wortschatz in Stapeln und Tags organisieren
• Nach Neu, Lernen, Gelernt oder Schwierig suchen und filtern
• Mit kurzen Sitzungen im eigenen Tempo wiederholen
• Lernschritte, Wiederholungsgrenze und Vergessensregeln anpassen
• Wortschatz und Lernpensum in Home-Bildschirm-Widgets sehen
• Optional lokale Erinnerungen erhalten, wenn Wörter bereit sind
• Helles, dunkles oder System-Erscheinungsbild verwenden
• Die Oberfläche in 16 Sprachen umschalten
• Wortschatz in jeder Sprache und Schrift lernen

PRIVAT GEDACHT
Deine Bibliothek bleibt auf deinem Gerät. Flipabulary braucht kein Konto und sendet deine Wörter nicht an einen Server.

KOSTENLOS NUTZBAR
Lernen, Widgets und Erinnerungen funktionieren ohne Kauf. Wenn du die Entwicklung unterstützen möchtest, bietet der Support-Bildschirm sechs freiwillige einmalige Trinkgelder. Trinkgelder schalten keine Funktionen frei und können wiederholt werden.

Flipabulary wird von einer Person gemacht, die einen ruhigeren Weg gesucht hat, Wortschatz im Blick zu behalten.""",
    "es-ES": """Flipabulary es un cuaderno de vocabulario tranquilo y sin conexión para las palabras que de verdad quieres recordar.

Guarda una palabra y su traducción, añade un ejemplo y organiza todo en pilas y etiquetas. Cuando toca practicar, Flipabulary te da sesiones cortas con una decisión sencilla: Otra vez o Bien. Sin cuenta, sin anuncios, sin suscripción y sin conexión.

LO QUE PUEDES HACER
• Guardar palabras con traducciones, ejemplos, fonética y categoría gramatical
• Organizar el vocabulario en pilas y etiquetas
• Buscar y filtrar por Nuevas, En aprendizaje, Aprendidas o Difíciles
• Repasar con sesiones cortas a tu ritmo
• Ajustar los pasos de aprendizaje, el umbral de repetición y las reglas de olvido
• Ver tu vocabulario y tu carga de repaso en widgets de la pantalla de inicio
• Recibir recordatorios locales opcionales cuando haya palabras listas
• Usar apariencia clara, oscura o del sistema
• Cambiar la interfaz entre 16 idiomas
• Estudiar vocabulario en cualquier idioma o escritura

PRIVADO POR DISEÑO
Tu biblioteca se queda en tu dispositivo. Flipabulary no requiere una cuenta ni envía tus palabras a un servidor.

GRATIS
El aprendizaje, los widgets y los recordatorios funcionan sin ninguna compra. Si quieres apoyar el desarrollo, la pantalla de Apoyo ofrece seis propinas únicas opcionales. Las propinas no desbloquean funciones y se pueden repetir.

Flipabulary está hecho por una persona que quería una forma más tranquila de mantener el vocabulario a la vista.""",
    "pt-BR": """Flipabulary é um caderno de vocabulário tranquilo e offline para as palavras que você realmente quer lembrar.

Salve uma palavra e a tradução, adicione um exemplo e organize tudo em pilhas e etiquetas. Na hora de praticar, o Flipabulary oferece sessões curtas em torno de uma escolha simples: De novo ou Bom. Sem conta, sem anúncios, sem assinatura e sem conexão.

O QUE VOCÊ PODE FAZER
• Salvar palavras com traduções, exemplos, fonética e classe gramatical
• Organizar o vocabulário em pilhas e etiquetas
• Buscar e filtrar por Novas, Aprendendo, Aprendidas ou Difíceis
• Revisar com sessões curtas no seu ritmo
• Ajustar etapas de aprendizagem, limite de repetições e regras de esquecimento
• Ver seu vocabulário e sua carga de revisão em widgets da Tela de Início
• Receber lembretes locais opcionais quando houver palavras prontas
• Usar aparência clara, escura ou do sistema
• Alternar a interface entre 16 idiomas
• Estudar vocabulário em qualquer idioma ou escrita

PRIVADO POR PRINCÍPIO
Sua biblioteca fica no seu dispositivo. O Flipabulary não exige conta e não envia suas palavras para um servidor.

GRÁTIS PARA USAR
Aprendizagem, widgets e lembretes funcionam sem nenhuma compra. Se quiser apoiar o desenvolvimento, a tela de Apoio oferece seis gorjetas únicas opcionais. As gorjetas não desbloqueiam recursos e podem ser repetidas.

O Flipabulary é feito por uma pessoa que queria uma forma mais calma de manter o vocabulário à vista.""",
    "fr-FR": """Flipabulary est un carnet de vocabulaire discret et hors ligne pour les mots que vous voulez vraiment retenir.

Enregistrez un mot et sa traduction, ajoutez un exemple et organisez tout en piles et en étiquettes. Au moment de réviser, Flipabulary propose de courtes séances autour d'un choix simple : À revoir ou Bien. Sans compte, sans publicité, sans abonnement et sans connexion.

CE QUE VOUS POUVEZ FAIRE
• Enregistrer des mots avec traductions, exemples, phonétique et nature grammaticale
• Organiser le vocabulaire en piles et en étiquettes
• Rechercher et filtrer par Nouveau, En apprentissage, Appris ou Difficile
• Réviser avec de courtes séances à votre rythme
• Ajuster les étapes d'apprentissage, le seuil de répétition et les règles d'oubli
• Voir votre vocabulaire et votre charge de révision dans les widgets de l'écran d'accueil
• Recevoir des rappels locaux facultatifs quand des mots sont prêts
• Utiliser l'apparence claire, sombre ou système
• Changer l'interface entre 16 langues
• Étudier du vocabulaire dans n'importe quelle langue ou écriture

PRIVÉ PAR CONCEPTION
Votre bibliothèque reste sur votre appareil. Flipabulary ne demande pas de compte et n'envoie pas vos mots à un serveur.

GRATUIT
L'apprentissage, les widgets et les rappels fonctionnent sans aucun achat. Pour soutenir le développement, l'écran Soutien propose six pourboires uniques facultatifs. Les pourboires ne débloquent aucune fonction et peuvent être répétés.

Flipabulary est fait par une personne qui voulait une façon plus calme de garder son vocabulaire à portée de vue.""",
    "ru": """Flipabulary — спокойная офлайн-тетрадь для слов, которые вы действительно хотите запомнить.

Сохраните слово и перевод, добавьте пример и разложите всё по стопкам и тегам. Когда придёт время повторять, Flipabulary предложит короткую сессию с простым выбором: «Ещё раз» или «Хорошо». Без аккаунта, рекламы, подписки и подключения к сети.

ЧТО МОЖНО ДЕЛАТЬ
• Сохранять слова с переводами, примерами, транскрипцией и частью речи
• Организовывать словарь в стопки и теги
• Искать и фильтровать по статусам «Новые», «Изучаются», «Выученные» и «Сложные»
• Повторять слова короткими сессиями в удобном темпе
• Настраивать шаги обучения, порог повторений и правила забывания
• Видеть словарь и нагрузку в виджетах на экране «Домой»
• Получать необязательные локальные напоминания, когда слова готовы
• Выбирать светлую, тёмную или системную тему
• Переключать интерфейс между 16 языками
• Учить слова на любом языке и в любой письменности

ПРИВАТНОСТЬ ПО УМОЛЧАНИЮ
Библиотека остаётся на вашем устройстве. Flipabulary не требует аккаунта и не отправляет слова на сервер.

БЕСПЛАТНО
Обучение, виджеты и напоминания работают без покупок. Если хотите поддержать разработку, на экране «Поддержка» есть шесть необязательных разовых чаевых. Чаевые не открывают функции, и их можно отправлять повторно.

Flipabulary делает один человек, которому нужен был более спокойный способ держать словарь перед глазами.""",
    "pl": """Flipabulary to spokojny, offline'owy zeszyt słówek dla słów, które naprawdę chcesz zapamiętać.

Zapisz słowo i tłumaczenie, dodaj przykład i uporządkuj wszystko w stosach i tagach. Gdy przyjdzie czas na powtórkę, Flipabulary zaproponuje krótką sesję z prostym wyborem: Jeszcze raz albo Dobrze. Bez konta, reklam, subskrypcji i połączenia z siecią.

CO MOŻESZ ROBIĆ
• Zapisuj słowa z tłumaczeniami, przykładami, fonetyką i częścią mowy
• Organizuj słownictwo w stosach i tagach
• Szukaj i filtruj według statusów Nowe, W nauce, Nauczone i Trudne
• Powtarzaj krótkimi sesjami we własnym tempie
• Zmieniaj kroki nauki, próg powtórzeń i zasady zapominania
• Oglądaj słownictwo i obciążenie powtórkami w widgetach na ekranie początkowym
• Otrzymuj opcjonalne lokalne przypomnienia, gdy słowa są gotowe
• Korzystaj z jasnego, ciemnego lub systemowego wyglądu
• Przełączaj interfejs między 16 językami
• Ucz się słów w dowolnym języku i piśmie

PRYWATNOŚĆ W STANDARDZIE
Twoja biblioteka pozostaje na urządzeniu. Flipabulary nie wymaga konta i nie wysyła słów na serwer.

ZA DARMO
Nauka, widżety i przypomnienia działają bez żadnych zakupów. Jeśli chcesz wesprzeć rozwój, ekran Wsparcia oferuje sześć opcjonalnych jednorazowych napiwków. Napiwki nie odblokowują funkcji i można je powtarzać.

Flipabulary tworzy jedna osoba, która chciała spokojniejszego sposobu trzymania słownictwa pod ręką.""",
    "uk": """Flipabulary — спокійний офлайн-зошит для слів, які ви справді хочете запам'ятати.

Збережіть слово й переклад, додайте приклад і впорядкуйте все в стопки та теги. Коли настане час повторювати, Flipabulary запропонує коротку сесію з простим вибором: «Ще раз» або «Добре». Без облікового запису, реклами, підписки та підключення до мережі.

ЩО МОЖНА РОБИТИ
• Зберігати слова з перекладами, прикладами, транскрипцією та частиною мови
• Організовувати словник у стопки та теги
• Шукати й фільтрувати за статусами «Нові», «Вивчаються», «Вивчені» та «Складні»
• Повторювати слова короткими сесіями у зручному темпі
• Налаштовувати кроки навчання, поріг повторень і правила забування
• Бачити словник і навантаження у віджетах на екрані «Домівка»
• Отримувати необов'язкові локальні нагадування, коли слова готові
• Обирати світлу, темну або системну тему
• Перемикати інтерфейс між 16 мовами
• Вивчати слова будь-якою мовою та письменністю

ПРИВАТНІСТЬ ЗА ЗАМОВЧУВАННЯМ
Бібліотека залишається на вашому пристрої. Flipabulary не потребує облікового запису й не надсилає слова на сервер.

БЕЗКОШТОВНО
Навчання, віджети й нагадування працюють без покупок. Якщо хочете підтримати розробку, на екрані «Підтримка» є шість необов'язкових разових чайових. Чайові не відкривають функцій, і їх можна надсилати повторно.

Flipabulary робить одна людина, якій потрібен був спокійніший спосіб тримати словник перед очима.""",
    "zh-Hans": """Flipabulary 是一本安静、离线的单词本，专门用来记住你真正想记住的词。

保存单词和释义，添加例句，再用单词堆和标签整理一切。练习时，Flipabulary 会提供简短的复习，只让你做一个选择：再来一次或记住了。无需账号、没有广告、没有订阅，也不需要联网。

你可以：
• 保存单词、释义、例句、音标和词性
• 用单词堆和标签组织词汇
• 按新词、学习中、已学会或困难进行搜索和筛选
• 以自己的节奏进行简短复习
• 调整学习步骤、重复阈值和遗忘规则
• 在主屏幕小组件中查看词汇和学习量
• 在有单词待复习时接收可选的本地提醒
• 使用浅色、深色或系统外观
• 在 16 种界面语言之间切换
• 学习任何语言或文字的词汇

隐私优先
词库保存在你的设备上。Flipabulary 不需要账号，也不会把单词发送到服务器。

免费使用
学习、小组件和提醒都无需购买。如果你想支持开发，支持页面提供六种可选的一次性打赏。打赏不会解锁任何功能，且可以重复购买。

Flipabulary 由一个人制作，他想要一种更从容的方式来记住词汇。""",
    "ko": """Flipabulary는 정말 기억하고 싶은 단어를 위한 조용한 오프라인 단어장입니다.

단어와 뜻을 저장하고 예문을 추가한 뒤 스택과 태그로 정리하세요. 복습할 때는 '다시' 또는 '좋음' 중 하나를 고르는 짧은 세션을 제공합니다. 계정, 광고, 구독, 네트워크 연결이 필요 없습니다.

할 수 있는 일
• 단어, 뜻, 예문, 발음 기호, 품사 저장
• 스택과 태그로 어휘 정리
• 새 단어, 학습 중, 학습 완료, 어려움으로 검색 및 필터링
• 내 속도에 맞춘 짧은 복습
• 학습 단계, 반복 기준, 망각 규칙 조정
• 홈 화면 위젯에서 어휘와 복습량 확인
• 단어가 준비되면 선택적 로컬 알림 받기
• 라이트, 다크, 시스템 모양 사용
• 16개 언어로 인터페이스 전환
• 어떤 언어와 문자로든 어휘 학습

개인정보 보호
단어장은 기기에 저장됩니다. Flipabulary는 계정이 필요 없으며 단어를 서버로 보내지 않습니다.

무료
학습, 위젯, 알림은 구매 없이 작동합니다. 개발을 후원하고 싶다면 지원 화면에서 여섯 가지 선택적 일회성 팁을 제공합니다. 팁은 기능을 해제하지 않으며 여러 번 보낼 수 있습니다.

Flipabulary는 어휘를 더 차분하게 곁에 두고 싶은 한 사람이 만들었습니다.""",
    "ja": """Flipabularyは、本当に覚えたい単語のための、静かなオフライン単語帳です。

単語と訳を保存し、例文を追加して、スタックとタグで整理できます。復習の時間には、「もう一度」か「覚えた」を選ぶ短いセッションを用意します。アカウント、広告、サブスクリプション、ネットワーク接続は不要です。

できること
• 単語、訳、例文、発音記号、品詞を保存
• スタックとタグで語彙を整理
• 新規、学習中、学習済み、難しいで検索・絞り込み
• 自分のペースで短く復習
• 学習ステップ、繰り返しのしきい値、忘却ルールを調整
• ホーム画面ウィジェットで語彙と復習量を確認
• 単語の準備ができたら任意のローカル通知を受け取る
• ライト、ダーク、システムの外観を使用
• 16言語でインターフェースを切り替え
• どんな言語や文字の語彙でも学習

プライバシー重視
単語帳は端末内に保存されます。Flipabularyはアカウントを必要とせず、単語をサーバーに送信しません。

無料で利用
学習、ウィジェット、リマインダーは購入なしで使えます。開発を支援したい場合は、サポート画面で6種類の任意の一回限りのチップを用意しています。チップで機能が解除されることはなく、何度でも送れます。

Flipabularyは、語彙をもっと穏やかに手元に置きたい一人の開発者が作りました。""",
    "vi": """Flipabulary là một cuốn sổ từ vựng yên tĩnh, hoạt động ngoại tuyến cho những từ bạn thật sự muốn nhớ.

Lưu một từ và bản dịch, thêm ví dụ và sắp xếp mọi thứ vào các chồng và thẻ. Khi đến lúc luyện tập, Flipabulary mang đến những buổi ôn ngắn với một lựa chọn đơn giản: Học lại hoặc Tốt. Không tài khoản, không quảng cáo, không đăng ký và không cần kết nối.

BẠN CÓ THỂ
• Lưu từ với bản dịch, ví dụ, phiên âm và từ loại
• Sắp xếp từ vựng vào chồng và thẻ
• Tìm kiếm và lọc theo Mới, Đang học, Đã học hoặc Khó
• Ôn tập bằng những buổi ngắn theo nhịp của bạn
• Điều chỉnh bước học, ngưỡng lặp lại và quy tắc quên
• Xem từ vựng và khối lượng ôn tập trong widget Màn hình chính
• Nhận nhắc nhở cục bộ tùy chọn khi có từ sẵn sàng
• Dùng giao diện sáng, tối hoặc theo hệ thống
• Chuyển giao diện giữa 16 ngôn ngữ
• Học từ vựng ở bất kỳ ngôn ngữ hay chữ viết nào

RIÊNG TƯ TỪ THIẾT KẾ
Thư viện của bạn nằm trên thiết bị. Flipabulary không yêu cầu tài khoản và không gửi từ của bạn lên máy chủ.

MIỄN PHÍ
Việc học, widget và nhắc nhở hoạt động mà không cần mua. Nếu muốn ủng hộ phát triển, màn hình Hỗ trợ có sáu khoản tip một lần tùy chọn. Tip không mở khóa tính năng và có thể gửi lặp lại.

Flipabulary được làm bởi một người muốn có cách nhẹ nhàng hơn để giữ từ vựng trong tầm mắt.""",
    "it": """Flipabulary è un quaderno di vocaboli tranquillo e offline per le parole che vuoi davvero ricordare.

Salva una parola e la traduzione, aggiungi un esempio e organizza tutto in pile e tag. Al momento di esercitarti, Flipabulary offre brevi sessioni con una scelta semplice: Ancora o Bene. Senza account, pubblicità, abbonamento e connessione.

COSA PUOI FARE
• Salvare parole con traduzioni, esempi, fonetica e parte del discorso
• Organizzare il vocabolario in pile e tag
• Cercare e filtrare per Nuove, In apprendimento, Imparate o Difficili
• Ripassare con brevi sessioni al tuo ritmo
• Regolare i passi di apprendimento, la soglia di ripetizione e le regole di oblio
• Vedere vocabolario e carico di ripasso nei widget della schermata Home
• Ricevere promemoria locali opzionali quando le parole sono pronte
• Usare l'aspetto chiaro, scuro o di sistema
• Cambiare l'interfaccia tra 16 lingue
• Studiare vocaboli in qualsiasi lingua o scrittura

PRIVATO PER DESIGN
La tua libreria resta sul dispositivo. Flipabulary non richiede un account e non invia le parole a un server.

GRATUITO
Apprendimento, widget e promemoria funzionano senza acquisti. Per sostenere lo sviluppo, la schermata Supporto offre sei mance una tantum opzionali. Le mance non sbloccano funzioni e possono essere ripetute.

Flipabulary è fatto da una persona che voleva un modo più tranquillo di tenere il vocabolario a portata di vista.""",
    "nl-NL": """Flipabulary is een rustig, offline woordenschatschrift voor de woorden die je echt wilt onthouden.

Sla een woord en de vertaling op, voeg een voorbeeld toe en orden alles in stapels en tags. Als het tijd is om te oefenen, krijg je korte sessies met één eenvoudige keuze: Opnieuw of Goed. Geen account, advertenties, abonnement of verbinding nodig.

WAT JE KUNT DOEN
• Woorden opslaan met vertalingen, voorbeelden, fonetiek en woordsoort
• Woordenschat ordenen in stapels en tags
• Zoeken en filteren op Nieuw, Leren, Geleerd of Moeilijk
• Oefenen met korte sessies in je eigen tempo
• Leerstappen, de herhaal-drempel en vergeetregels aanpassen
• Je woordenschat en oefenlast zien in widgets op het beginscherm
• Optionele lokale herinneringen krijgen wanneer woorden klaar zijn
• Licht, donker of systeemweergave gebruiken
• De interface wisselen tussen 16 talen
• Woordenschat leren in elke taal of elk schrift

PRIVÉ ONTWORPEN
Je bibliotheek blijft op je apparaat. Flipabulary heeft geen account nodig en stuurt je woorden niet naar een server.

GRATIS
Leren, widgets en herinneringen werken zonder aankoop. Wil je de ontwikkeling steunen, dan biedt het Support-scherm zes optionele eenmalige fooien. Fooien ontgrendelen geen functies en kunnen worden herhaald.

Flipabulary is gemaakt door één persoon die een rustigere manier zocht om woordenschat in beeld te houden.""",
    "tr": """Flipabulary, gerçekten hatırlamak istediğiniz kelimeler için sakin, çevrimdışı bir kelime defteridir.

Bir kelimeyi ve çevirisini kaydedin, örnek ekleyin ve her şeyi desteler ve etiketlerle düzenleyin. Pratik zamanı geldiğinde Flipabulary size basit bir seçim sunan kısa oturumlar verir: Tekrar veya İyi. Hesap, reklam, abonelik ve bağlantı gerekmez.

YAPABİLECEKLERİNİZ
• Kelimeleri çeviri, örnek, fonetik ve kelime türüyle kaydetme
• Kelime dağarcığını desteler ve etiketlerle düzenleme
• Yeni, Öğreniliyor, Öğrenildi veya Zor olarak arama ve filtreleme
• Kendi hızınızda kısa oturumlarla tekrar etme
• Öğrenme adımlarını, tekrar eşiğini ve unutma kurallarını ayarlama
• Kelime dağarcığınızı ve tekrar yükünüzü Ana Ekran widget'larında görme
• Kelimeler hazır olduğunda isteğe bağlı yerel hatırlatmalar alma
• Açık, koyu veya sistem görünümünü kullanma
• Arayüzü 16 dil arasında değiştirme
• Herhangi bir dilde veya yazıda kelime öğrenme

TASARIM GEREĞİ ÖZEL
Kitaplığınız cihazınızda kalır. Flipabulary hesap gerektirmez ve kelimelerinizi sunucuya göndermez.

ÜCRETSİZ
Öğrenme, widget'lar ve hatırlatmalar satın alma olmadan çalışır. Geliştirmeyi desteklemek isterseniz Destek ekranı altı isteğe bağlı tek seferlik bahşiş sunar. Bahşişler hiçbir özelliğin kilidini açmaz ve tekrarlanabilir.

Flipabulary, kelime dağarcığını daha sakin bir şekilde göz önünde tutmak isteyen bir kişi tarafından yapıldı.""",
    "id": """Flipabulary adalah buku kosakata offline yang tenang untuk kata-kata yang benar-benar ingin Anda ingat.

Simpan kata dan terjemahannya, tambahkan contoh, lalu atur semuanya dalam tumpukan dan tag. Saat waktunya berlatih, Flipabulary memberi sesi singkat dengan satu pilihan sederhana: Lagi atau Bagus. Tanpa akun, iklan, langganan, dan koneksi.

YANG BISA ANDA LAKUKAN
• Menyimpan kata dengan terjemahan, contoh, fonetik, dan kelas kata
• Mengatur kosakata dalam tumpukan dan tag
• Mencari dan memfilter Baru, Sedang dipelajari, Dikuasai, atau Sulit
• Mengulang dengan sesi singkat sesuai ritme Anda
• Menyesuaikan langkah belajar, ambang pengulangan, dan aturan lupa
• Melihat kosakata dan beban ulasan di widget Layar Utama
• Menerima pengingat lokal opsional saat kata siap
• Menggunakan tampilan terang, gelap, atau sistem
• Mengganti antarmuka antara 16 bahasa
• Belajar kosakata dalam bahasa atau aksara apa pun

PRIVAT SEJAK DESAIN
Pustaka Anda tetap di perangkat. Flipabulary tidak memerlukan akun dan tidak mengirim kata Anda ke server.

GRATIS
Pembelajaran, widget, dan pengingat berfungsi tanpa pembelian. Jika ingin mendukung pengembangan, layar Dukungan menawarkan enam tip sekali bayar opsional. Tip tidak membuka fitur dan dapat diulang.

Flipabulary dibuat oleh satu orang yang ingin cara yang lebih tenang untuk menjaga kosakata tetap terlihat.""",
}


def app_info_localizations():
    status, payload = request("GET", f"/v1/appInfos/{APP_INFO_ID}/appInfoLocalizations?limit=50")
    if status != 200:
        raise RuntimeError(f"List app info localizations failed: {status} {payload}")
    return {item["attributes"]["locale"]: item for item in payload.get("data", [])}


def version_localizations():
    status, payload = request("GET", f"/v1/appStoreVersions/{VERSION_ID}/appStoreVersionLocalizations?limit=50")
    if status != 200:
        raise RuntimeError(f"List version localizations failed: {status} {payload}")
    return {item["attributes"]["locale"]: item for item in payload.get("data", [])}


def configure_app_info():
    existing = app_info_localizations()
    result = {}
    for locale in LOCALES:
        attrs = {
            "name": APP_NAMES[locale],
            "subtitle": SUBTITLES[locale],
            "privacyPolicyUrl": PRIVACY_URL,
        }
        if locale in existing:
            item_id = existing[locale]["id"]
            status, payload = request(
                "PATCH",
                f"/v1/appInfoLocalizations/{item_id}",
                {"data": {"type": "appInfoLocalizations", "id": item_id, "attributes": attrs}},
            )
            expected = 200
        else:
            status, payload = request(
                "POST",
                "/v1/appInfoLocalizations",
                {
                    "data": {
                        "type": "appInfoLocalizations",
                        "attributes": {"locale": locale, **attrs},
                        "relationships": {
                            "appInfo": {"data": {"type": "appInfos", "id": APP_INFO_ID}}
                        },
                    }
                },
            )
            expected = 201
            if status == expected:
                item_id = payload["data"]["id"]
        if status != expected:
            raise RuntimeError(f"App info {locale} failed: {status} {payload}")
        result[locale] = item_id
        print(f"app info {locale}: {SUBTITLES[locale]}")
    return result


def configure_versions():
    existing = version_localizations()
    result = {}
    for locale in LOCALES:
        attrs = {
            "description": DESCRIPTIONS[locale],
            "keywords": KEYWORDS[locale],
            "promotionalText": PROMOTIONAL[locale],
            "supportUrl": SUPPORT_URL,
            "marketingUrl": MARKETING_URL,
        }
        if locale in existing:
            item_id = existing[locale]["id"]
            status, payload = request(
                "PATCH",
                f"/v1/appStoreVersionLocalizations/{item_id}",
                {"data": {"type": "appStoreVersionLocalizations", "id": item_id, "attributes": attrs}},
            )
            expected = 200
        else:
            status, payload = request(
                "POST",
                "/v1/appStoreVersionLocalizations",
                {
                    "data": {
                        "type": "appStoreVersionLocalizations",
                        "attributes": {"locale": locale, **attrs},
                        "relationships": {
                            "appStoreVersion": {"data": {"type": "appStoreVersions", "id": VERSION_ID}}
                        },
                    }
                },
            )
            expected = 201
            if status == expected:
                item_id = payload["data"]["id"]
        if status != expected:
            raise RuntimeError(f"Version localization {locale} failed: {status} {payload}")
        result[locale] = item_id
        print(f"listing {locale}: {len(attrs['description'])} chars")
    return result


def configure_categories():
    status, payload = request(
        "PATCH",
        f"/v1/appInfos/{APP_INFO_ID}",
        {
            "data": {
                "type": "appInfos",
                "id": APP_INFO_ID,
                "relationships": {
                    "primaryCategory": {"data": {"type": "appCategories", "id": "EDUCATION"}},
                    "secondaryCategory": {"data": {"type": "appCategories", "id": "PRODUCTIVITY"}},
                },
            }
        },
    )
    if status not in (200, 204):
        raise RuntimeError(f"Categories failed: {status} {payload}")
    print("categories: EDUCATION / PRODUCTIVITY")


def configure_age_rating():
    attrs = {
        "messagingAndChat": False,
        "sexualContentGraphicAndNudity": "NONE",
        "gambling": False,
        "horrorOrFearThemes": "NONE",
        "parentalControls": False,
        "advertising": False,
        "ageRatingOverrideV2": "NONE",
        "violenceRealisticProlongedGraphicOrSadistic": "NONE",
        "matureOrSuggestiveThemes": "NONE",
        "healthOrWellnessTopics": False,
        "unrestrictedWebAccess": False,
        "violenceCartoonOrFantasy": "NONE",
        "medicalOrTreatmentInformation": "NONE",
        "lootBox": False,
        "alcoholTobaccoOrDrugUseOrReferences": "NONE",
        "gamblingSimulated": "NONE",
        "violenceRealistic": "NONE",
        "profanityOrCrudeHumor": "NONE",
        "socialMedia": False,
        "contests": "NONE",
        "koreaAgeRatingOverride": "NONE",
        "ageAssurance": False,
        "userGeneratedContent": False,
        "gunsOrOtherWeapons": "NONE",
        "socialMediaAgeRestricted": False,
        "sexualContentOrNudity": "NONE",
    }
    status, payload = request(
        "PATCH",
        f"/v1/ageRatingDeclarations/{AGE_RATING_ID}",
        {"data": {"type": "ageRatingDeclarations", "id": AGE_RATING_ID, "attributes": attrs}},
    )
    if status not in (200, 204):
        raise RuntimeError(f"Age rating failed: {status} {payload}")
    print("age rating: 4+ / no objectionable content")


def configure_content_rights():
    status, payload = request(
        "PATCH",
        f"/v1/apps/{APP_ID}",
        {
            "data": {
                "type": "apps",
                "id": APP_ID,
                "attributes": {"contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"},
            }
        },
    )
    if status not in (200, 204):
        raise RuntimeError(f"Content rights failed: {status} {payload}")
    print("content rights: no third-party content")


def configure_version():
    status, payload = request(
        "PATCH",
        f"/v1/appStoreVersions/{VERSION_ID}",
        {
            "data": {
                "type": "appStoreVersions",
                "id": VERSION_ID,
                "attributes": {
                    "copyright": "2026 Andrei Maier",
                    "releaseType": "AFTER_APPROVAL",
                    "usesIdfa": False,
                },
            }
        },
    )
    if status not in (200, 204):
        raise RuntimeError(f"Version failed: {status} {payload}")
    print("version: copyright + release after approval")


def configure_price():
    status, payload = request(
        "POST",
        "/v1/appPriceSchedules",
        {
            "data": {
                "type": "appPriceSchedules",
                "relationships": {
                    "app": {"data": {"type": "apps", "id": APP_ID}},
                    "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
                    "manualPrices": {"data": [{"type": "appPrices", "id": "${FREE}"}]},
                },
            },
            "included": [
                {
                    "type": "appPrices",
                    "id": "${FREE}",
                    "attributes": {"startDate": None},
                    "relationships": {
                        "app": {"data": {"type": "apps", "id": APP_ID}},
                        "appPricePoint": {
                            "data": {"type": "appPricePoints", "id": FREE_PRICE_POINT_ID}
                        },
                    },
                }
            ],
        },
    )
    if status == 409:
        print("price: schedule already exists, leaving it unchanged")
        return
    if status != 201:
        raise RuntimeError(f"Price failed: {status} {payload}")
    print("price: free")


def main():
    app_info = configure_app_info()
    versions = configure_versions()
    configure_categories()
    configure_age_rating()
    configure_content_rights()
    configure_version()
    configure_price()

    os.makedirs("docs/app-store", exist_ok=True)
    with open("docs/app-store/localizations.json", "w", encoding="utf-8") as handle:
        json.dump(
            {"appInfo": app_info, "appStoreVersion": versions},
            handle,
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
        )
        handle.write("\n")
    print("wrote docs/app-store/localizations.json")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
