"""Finds a screen element in a uiautomator dump and prints the centre "x y" of it.
usage: tap.py ui.xml text "Log in" [last]   |   tap.py ui.xml edit N   (N-th text box, from 0)"""
import re
import sys
import xml.etree.ElementTree as ET

ui, kind, what = sys.argv[1], sys.argv[2], sys.argv[3]
last = len(sys.argv) > 4
nodes = list(ET.parse(ui).getroot().iter('node'))

def centre(n):
    a, b, c, d = map(int, re.findall(r'\d+', n.get('bounds')))
    return f'{(a + c) // 2} {(b + d) // 2}'

if kind == 'edit':
    edits = [n for n in nodes if n.get('class') == 'android.widget.EditText']
    print(centre(edits[int(what)]) if len(edits) > int(what) else '')
else:
    hits = [n for n in nodes if (n.get('text') or '').strip() == what or (n.get('content-desc') or '').strip() == what]
    hits = [n for n in hits if n.get('clickable') == 'true'] or hits
    print(centre(hits[-1] if last else hits[0]) if hits else '')
