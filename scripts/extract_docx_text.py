import sys
import zipfile
import xml.etree.ElementTree as ET

def docx_to_text(path):
    with zipfile.ZipFile(path) as z:
        with z.open('word/document.xml') as f:
            tree = ET.parse(f)
            root = tree.getroot()
            # Word XML namespace
            ns = {'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
            paragraphs = []
            for p in root.findall('.//w:p', ns):
                texts = [node.text for node in p.findall('.//w:t', ns) if node.text]
                if texts:
                    paragraphs.append(''.join(texts))
            return '\n'.join(paragraphs)

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: extract_docx_text.py <file.docx>')
        sys.exit(2)
    path = sys.argv[1]
    try:
        txt = docx_to_text(path)
        print(txt)
    except Exception as e:
        print('ERROR:', e)
        sys.exit(1)
